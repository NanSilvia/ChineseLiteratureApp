import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/card_model.dart';
import '../models/folder_model.dart';
import '../models/user_model.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  Database? _db;

  DbService._internal();

  factory DbService() {
    return _instance;
  }

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'zhapp.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Cards table with userId for user isolation
    await db.execute('''
      CREATE TABLE cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        title TEXT,
        textZh TEXT NOT NULL,
        folderId INTEGER,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        source TEXT DEFAULT 'manual'
      )
    ''');

    // Folders table with userId for user isolation
    await db.execute('''
      CREATE TABLE folders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        name TEXT NOT NULL
      )
    ''');

    // User/Auth table (stores current user session)
    await db.execute('''
      CREATE TABLE user(
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        email TEXT,
        token TEXT
      )
    ''');

    // Legacy texts table for migration
    await db.execute('''
      CREATE TABLE IF NOT EXISTS texts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        value TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Create new tables
      await _createTables(db, newVersion);

      // Migrate old texts to cards
      final oldTexts = await db.query('texts', orderBy: 'id ASC');
      for (var text in oldTexts) {
        await db.insert('cards', {
          'title': null,
          'textZh': text['value'],
          'folderId': null,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': null,
          'source': 'manual',
        });
      }
    }

    if (oldVersion < 3) {
      // Add userId column if not exists
      try {
        await db.execute('ALTER TABLE cards ADD COLUMN userId INTEGER');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE folders ADD COLUMN userId INTEGER');
      } catch (e) {
        // Column might already exist
      }
    }
  }

  // ==================== CARD OPERATIONS ====================

  Future<int> saveCard(CardModel card) async {
    final database = await db;
    final data = card.toMap();
    data.remove('id'); // Let SQLite generate ID
    return await database.insert('cards', {
      'title': data['title'],
      'textZh': data['textZh'],
      'folderId': data['folderId'],
      'createdAt': data['createdAt'],
      'updatedAt': data['updatedAt'],
      'source': data['source'],
    });
  }

  Future<void> updateCard(CardModel card) async {
    if (card.id == null) return;
    final database = await db;
    await database.update(
      'cards',
      {
        'title': card.title,
        'textZh': card.textZh,
        'folderId': card.folderId,
        'updatedAt': DateTime.now().toIso8601String(),
        'source': card.source,
      },
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<List<CardModel>> loadCards({int? folderId}) async {
    final database = await db;
    List<Map<String, dynamic>> rows;

    if (folderId != null) {
      rows = await database.query(
        'cards',
        where: 'folderId = ?',
        whereArgs: [folderId],
        orderBy: 'createdAt DESC',
      );
    } else {
      rows = await database.query('cards', orderBy: 'createdAt DESC');
    }

    return rows.map((e) => CardModel.fromMap(e)).toList();
  }

  Future<CardModel?> getCardById(int id) async {
    final database = await db;
    final rows = await database.query(
      'cards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CardModel.fromMap(rows.first);
  }

  Future<void> deleteCard(int id) async {
    final database = await db;
    await database.delete('cards', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== FOLDER OPERATIONS ====================

  Future<int> saveFolder(FolderModel folder) async {
    final database = await db;
    return await database.insert('folders', {'name': folder.name});
  }

  Future<List<FolderModel>> loadFolders() async {
    final database = await db;
    final rows = await database.query('folders', orderBy: 'name ASC');
    return rows.map((e) => FolderModel.fromMap(e)).toList();
  }

  Future<void> deleteFolder(int id) async {
    final database = await db;
    // Set folderId to null for cards in this folder
    await database.update(
      'cards',
      {'folderId': null},
      where: 'folderId = ?',
      whereArgs: [id],
    );
    await database.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== USER/AUTH OPERATIONS ====================

  Future<void> saveUser(UserModel user) async {
    final database = await db;
    // Clear existing user data
    await database.delete('user');
    // Insert new user
    await database.insert('user', user.toMap());
  }

  Future<UserModel?> getUser() async {
    final database = await db;
    final rows = await database.query('user', limit: 1);
    if (rows.isEmpty) return null;
    return UserModel.fromMap(rows.first);
  }

  /// Alias for getUser - used by AuthService
  Future<UserModel?> getCurrentUser() async {
    return getUser();
  }

  Future<void> clearUser() async {
    final database = await db;
    await database.delete('user');
  }

  /// Alias for clearUser - used by AuthService
  Future<void> deleteUser() async {
    return clearUser();
  }

  /// Clear all user-specific data (cards, folders) for a given user
  /// Called on logout to ensure data isolation
  Future<void> clearUserData(int userId) async {
    final database = await db;
    await database.delete('cards', where: 'userId = ?', whereArgs: [userId]);
    await database.delete('folders', where: 'userId = ?', whereArgs: [userId]);
  }

  // ==================== SYNC OPERATIONS ====================

  /// Replace all local cards with server data
  Future<void> syncCards(List<CardModel> cards) async {
    final database = await db;
    await database.delete('cards');
    for (var card in cards) {
      await database.insert('cards', {
        'id': card.id,
        'title': card.title,
        'textZh': card.textZh,
        'folderId': card.folderId,
        'createdAt': card.createdAt.toIso8601String(),
        'updatedAt': card.updatedAt?.toIso8601String(),
        'source': card.source,
      });
    }
  }

  /// Replace all local folders with server data
  Future<void> syncFolders(List<FolderModel> folders) async {
    final database = await db;
    await database.delete('folders');
    for (var folder in folders) {
      await database.insert('folders', {'id': folder.id, 'name': folder.name});
    }
  }

  // ==================== LEGACY OPERATIONS ====================

  @Deprecated('Use saveCard instead')
  Future<void> saveText(String text) async {
    if (text.trim().isEmpty) return;
    final card = CardModel(
      textZh: text,
      createdAt: DateTime.now(),
      source: 'ocr',
    );
    await saveCard(card);
  }

  @Deprecated('Use loadCards instead')
  Future<List<String>> loadTexts() async {
    final cards = await loadCards();
    return cards.map((e) => e.textZh).toList();
  }

  @Deprecated('Use deleteCard instead')
  Future<void> deleteText(int index, List<String> texts) async {
    final cards = await loadCards();
    if (index < 0 || index >= cards.length) return;
    final cardId = cards[index].id;
    if (cardId != null) {
      await deleteCard(cardId);
    }
  }
}
