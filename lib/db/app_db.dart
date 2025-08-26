import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AppDB {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'anti_procrastination_app2.db');
    _db = await openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
    return _db!;
  }

  static Future _onCreate(Database d, int v) async {
    await d.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        priority INTEGER,
        start_time TEXT,
        end_time TEXT,
        expected_minutes INTEGER,
        labels TEXT,
        project TEXT,
        date TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        estimate_pomos INTEGER,
        actual_pomos INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await d.execute('''
      CREATE TABLE templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        payload TEXT NOT NULL
      );
    ''');

    await d.execute('''
      CREATE TABLE focus_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER,
        planned_minutes INTEGER NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        task_id INTEGER,
        goal_text TEXT
      );
    ''');

    await d.execute('''
      CREATE TABLE interruptions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        ts INTEGER NOT NULL,
        reason TEXT NOT NULL
      );
    ''');
  }

  static Future _onUpgrade(Database d, int oldV, int newV) async {
    await _safeAddColumn(d, 'focus_sessions', 'task_id', 'INTEGER');
    await _safeAddColumn(d, 'focus_sessions', 'goal_text', 'TEXT');
    await _safeAddColumn(d, 'tasks', 'estimate_pomos', 'INTEGER');
    await _safeAddColumn(d, 'tasks', 'actual_pomos', 'INTEGER NOT NULL DEFAULT 0');
  }

  static Future _safeAddColumn(Database d, String table, String col, String def) async {
    try {
      final info = await d.rawQuery('PRAGMA table_info($table)');
      final exists = info.any((c) => c['name'] == col);
      if (!exists) {
        await d.execute('ALTER TABLE $table ADD COLUMN $col $def');
      }
    } catch (_) {}
  }
}
