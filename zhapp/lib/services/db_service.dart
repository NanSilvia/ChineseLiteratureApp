import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
    final path = join(dbPath, 'texts.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) => db.execute(
        'CREATE TABLE texts(id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT)',
      ),
    );
  }

  Future<void> saveText(String text) async {
    if (text.trim().isEmpty) return;
    final database = await db;
    await database.insert('texts', {'value': text});
  }

  Future<List<String>> loadTexts() async {
    final database = await db;
    final rows = await database.query('texts', orderBy: 'id DESC');
    return rows.map((e) => e['value'] as String).toList();
  }

  Future<void> deleteText(int index, List<String> texts) async {
    if (index < 0 || index >= texts.length) return;
    final database = await db;
    final textToDelete = texts[index];
    await database.delete(
      'texts',
      where: 'value = ?',
      whereArgs: [textToDelete],
    );
  }
}
