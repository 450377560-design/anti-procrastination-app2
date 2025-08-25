import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AppDB {
  static Database? _db;
  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'anti_procrastination_app2.db');
    _db = await openDatabase(path, version: 1, onCreate: _onCreate, onUpgrade: _onUpgrade);
    return _db!;
  }

  static Future _onCreate(Database d, int v) async {
    await d.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        priority INTEGER NOT NULL DEFAULT 2,
        start_time TEXT,
        end_time TEXT,
        expected_minutes INTEGER,
        labels TEXT,
        project TEXT,
        date TEXT,
        done INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await d.execute('''
      CREATE TABLE templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        payload TEXT NOT NULL
      );
    ''');

    await d.execute('''
      CREATE TABLE focus_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER,
        planned_minutes INTEGER NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await d.execute('''
      CREATE TABLE interruptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        ts INTEGER NOT NULL,
        reason TEXT,
        FOREIGN KEY(session_id) REFERENCES focus_sessions(id)
      );
    ''');

    await d.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
  }

  static Future _onUpgrade(Database d, int oldV, int newV) async {
    // 迁移脚本预留
  }
}
