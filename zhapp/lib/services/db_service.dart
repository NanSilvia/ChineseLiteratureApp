import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../models/card_model.dart';
import '../models/folder_model.dart';
import '../models/user_model.dart';

void _initializeDatabaseFactory() {
  try {
    databaseFactory;
  } catch (e) {
    // If databaseFactory is not initialized, it will be handled by sqflite
  }
}

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
      version: 6,
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
        token TEXT,
        refreshToken TEXT
      )
    ''');

    // Legacy texts table for migration
    await db.execute('''
      CREATE TABLE IF NOT EXISTS texts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        value TEXT
      )
    ''');

    // Annotation cache — persists MandarinSpot & other API results across sessions
    await db.execute('''
      CREATE TABLE IF NOT EXISTS annotation_cache(
        cache_key TEXT PRIMARY KEY,
        namespace TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT
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

    if (oldVersion < 4) {
      // Add annotation_cache table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS annotation_cache(
          cache_key TEXT PRIMARY KEY,
          namespace TEXT NOT NULL,
          data TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 5) {
      // Add refreshToken column to user table
      try {
        await db.execute('ALTER TABLE user ADD COLUMN refreshToken TEXT');
      } catch (e) {
        // Column might already exist
      }
    }

    if (oldVersion < 6) {
      // Add expires_at column to annotation_cache
      try {
        await db.execute(
          'ALTER TABLE annotation_cache ADD COLUMN expires_at TEXT',
        );
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
    await database.insert('user', {
      'id': user.id,
      'username': user.username,
      'email': user.email,
      'token': user.token,
      'refreshToken': user.refreshToken,
    });
  }

  Future<UserModel?> getUser() async {
    final database = await db;
    final rows = await database.query('user', limit: 1);
    if (rows.isEmpty) return null;
    return UserModel.fromMap(rows.first);
  }

  // Alias for getUser - used by AuthService
  Future<UserModel?> getCurrentUser() async {
    return getUser();
  }

  Future<void> clearUser() async {
    final database = await db;
    await database.delete('user');
  }

  // Alias for clearUser - used by AuthService
  Future<void> deleteUser() async {
    return clearUser();
  }

  // Clear all user-specific data (cards, folders) for a given user
  // Called on logout to ensure data isolation
  Future<void> clearUserData(int userId) async {
    final database = await db;
    await database.delete('cards', where: 'userId = ?', whereArgs: [userId]);
    await database.delete('folders', where: 'userId = ?', whereArgs: [userId]);
  }

  // Clear ALL local data — user session, cards, folders, and annotation cache.
  // Called on logout to ensure no stale data leaks to the next session.
  Future<void> clearAllLocalData() async {
    final database = await db;
    await database.delete('user');
    await database.delete('cards');
    await database.delete('folders');
    await database.delete('annotation_cache');
  }

  // ==================== SYNC OPERATIONS ====================

  // Replace all local cards with server data
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

  // Replace all local folders with server data
  Future<void> syncFolders(List<FolderModel> folders) async {
    final database = await db;
    await database.delete('folders');
    for (var folder in folders) {
      await database.insert('folders', {'id': folder.id, 'name': folder.name});
    }
  }

  // ==================== ANNOTATION CACHE ====================

  // Store a JSON-serializable value in the persistent annotation cache.
  Future<void> putCache(
    String key,
    String namespace,
    dynamic data, {
    DateTime? expiresAt,
  }) async {
    final database = await db;
    await database.insert('annotation_cache', {
      'cache_key': key,
      'namespace': namespace,
      'data': jsonEncode(data),
      'created_at': DateTime.now().toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Retrieve a cached value by key, or `null` if not found or expired.
  Future<dynamic> getCache(String key) async {
    final database = await db;
    final rows = await database.query(
      'annotation_cache',
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    // Check expiry
    final expiresAtStr = row['expires_at'] as String?;
    if (expiresAtStr != null) {
      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        // Expired — delete and return null
        await database.delete(
          'annotation_cache',
          where: 'cache_key = ?',
          whereArgs: [key],
        );
        return null;
      }
    }
    return jsonDecode(row['data'] as String);
  }

  // Remove a single cached entry by key.
  Future<void> clearCacheByKey(String key) async {
    final database = await db;
    await database.delete(
      'annotation_cache',
      where: 'cache_key = ?',
      whereArgs: [key],
    );
  }

  // Remove all cached entries for a given namespace (e.g. 'annotate', 'defs').
  Future<void> clearCacheByNamespace(String namespace) async {
    final database = await db;
    await database.delete(
      'annotation_cache',
      where: 'namespace = ?',
      whereArgs: [namespace],
    );
  }

  // Remove all cached entries.
  Future<void> clearAllCache() async {
    final database = await db;
    await database.delete('annotation_cache');
  }

  // Count of cached entries (useful for debug / settings page).
  Future<int> cacheSize() async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) as cnt FROM annotation_cache',
    );
    return result.first['cnt'] as int;
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
