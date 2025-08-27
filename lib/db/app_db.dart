import 'dart:async';
import 'package:sqflite/sqflite.dart';

/// 统一的数据库入口。
/// - 首次打开时确保专注相关三张表存在；
/// - 其他表（任务/模板/笔记）由各自 Dao 负责创建即可。
class AppDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = '$dir/anti_procrastination_app2.db';

    _db = await openDatabase(
      path,
      version: 2,
      onOpen: (d) async {
        // 专注会话表
        await d.execute('''
          CREATE TABLE IF NOT EXISTS focus_sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_ts INTEGER,
            end_ts INTEGER,
            planned_minutes INTEGER,
            actual_minutes INTEGER,
            completed INTEGER,
            task_id INTEGER
          )
        ''');

        // 打断记录表
        await d.execute('''
          CREATE TABLE IF NOT EXISTS interruptions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER,
            ts INTEGER,
            reason TEXT
          )
        ''');

        // 休息时长表（暂停累加）
        await d.execute('''
          CREATE TABLE IF NOT EXISTS focus_rest(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER,
            ts INTEGER,
            seconds INTEGER
          )
        ''');
      },
    );
    return _db!;
  }
}
