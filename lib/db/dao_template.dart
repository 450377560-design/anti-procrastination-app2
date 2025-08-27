import 'dart:convert';
import 'package:sqflite/sqflite.dart'; // ← 补这行
import '../models/task.dart';
import 'package:anti_procrastination_app2/db/app_db.dart';

class TemplateDao {
  static Future<int> saveTemplate(String name, Task task) async {
    final db = await AppDb.db;
    final payload = jsonEncode(task.toMap()..remove('id'));
    return db.insert('templates', {'name': name, 'payload': payload});
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final db = await AppDb.db;
    return db.query('templates', orderBy: 'id DESC');
  }

  static Future<Task> apply(int id, String date) async {
    final db = await AppDb.db;
    final row = (await db.query('templates', where: 'id=?', whereArgs: [id])).first;
    final map = Map<String, dynamic>.from(jsonDecode(row['payload'] as String));
    map['date'] = date;
    map['done'] = 0;
    return Task.fromMap(map);
  }

  static Future<int> delete(int id) async {
    final db = await AppDb.db;
    return db.delete('templates', where: 'id=?', whereArgs: [id]);
  }

  // 首次启动时补充一批默认模板（不存在时才插入）
  static Future<void> seedDefaults(String date) async {
    final db = await AppDb.db;
    final cnt = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM templates')) ?? 0;
    if (cnt > 0) return;

    final defs = [
      ('晨间规划 10min', Task(title: '晨间规划', expectedMinutes: 10, priority: 2, labels: '规划', project: '日常', date: date)),
      ('深度工作 50min', Task(title: '深度工作块', expectedMinutes: 50, priority: 1, labels: '专注', project: '工作', date: date, estimatePomos: 2)),
      ('阅读 20min', Task(title: '阅读', expectedMinutes: 20, priority: 2, labels: '学习', project: '自我提升', date: date)),
      ('锻炼 30min', Task(title: '锻炼', expectedMinutes: 30, priority: 2, labels: '健康', project: '身体', date: date)),
    ];

    for (final e in defs) {
      await saveTemplate(e.$1, e.$2);
    }
  }
}
