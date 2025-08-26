import 'package:sqflite/sqflite.dart';
import '../models/task.dart';
import 'app_db.dart';

class TaskDao {
  static Future<int> insert(Task t) async {
    final db = await AppDB.db;
    return db.insert('tasks', t.toMap());
  }

  static Future<int> update(Task t) async {
    final db = await AppDB.db;
    return db.update('tasks', t.toMap(), where: 'id=?', whereArgs: [t.id]);
  }

  static Future<int> delete(int id) async {
    final db = await AppDB.db;
    return db.delete('tasks', where: 'id=?', whereArgs: [id]);
  }

  static Future<void> deleteMany(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await AppDB.db;
    await db.delete('tasks', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  static Future<void> setDoneMany(List<int> ids, bool done) async {
    if (ids.isEmpty) return;
    final db = await AppDB.db;
    await db.update('tasks', {'done': done ? 1 : 0},
        where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  static Future<List<Task>> listByDate(String date,
      {String sort = 'priority', bool asc = true}) async {
    final db = await AppDB.db;
    final order = switch (sort) {
      'priority' => 'priority',
      'time' => "start_time IS NULL, start_time",
      _ => 'id'
    };
    final rows = await db.query(
      'tasks',
      where: 'date=?',
      whereArgs: [date],
      orderBy: '$order ${asc ? 'ASC' : 'DESC'}',
    );
    return rows.map(Task.fromMap).toList();
  }

  /// 最近 N 天（含今天）每天的完成率（0~100）
  static Future<Map<String, int>> completionByDay(int days) async {
    final db = await AppDB.db;
    final res = <String, int>{};
    final now = DateTime.now();
    for (int i = days - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final dateStr = "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      final rows = await db.query('tasks', where: 'date=?', whereArgs: [dateStr]);
      if (rows.isEmpty) {
        res[dateStr] = 0;
      } else {
        final done = rows.where((r) => (r['done'] as int? ?? 0) == 1).length;
        res[dateStr] = ((done * 100) / rows.length).round();
      }
    }
    return res;
  }
}
