import 'package:sqflite/sqflite.dart';
import '../models/task.dart';
import 'app_db.dart';

class TaskDao {
  static Future<int> insert(Task t) async {
    final db = await AppDb.db;
    return db.insert('tasks', t.toMap());
  }

  static Future<void> update(Task t) async {
    final db = await AppDb.db;
    await db.update('tasks', t.toMap(), where: 'id=?', whereArgs: [t.id]);
  }

  static Future<void> deleteMany(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await AppDb.db;
    final q = 'DELETE FROM tasks WHERE id IN (${List.filled(ids.length, '?').join(',')})';
    await db.rawDelete(q, ids);
  }

  static Future<void> setDoneMany(List<int> ids, bool done) async {
    if (ids.isEmpty) return;
    final db = await AppDb.db;
    final q = 'UPDATE tasks SET done=? WHERE id IN (${List.filled(ids.length, '?').join(',')})';
    await db.rawUpdate(q, [done ? 1 : 0, ...ids]);
  }

  static Future<void> toggleDone(Task t) async {
    final db = await AppDb.db;
    await db.update('tasks', {'done': t.done ? 0 : 1}, where: 'id=?', whereArgs: [t.id]);
  }

  static Future<List<Task>> listByDate(String date, {String sort = 'priority'}) async {
    final db = await AppDb.db;
    String orderBy = 'priority ASC, start_time ASC';
    if (sort == 'time') orderBy = 'start_time ASC, priority ASC';
    final rows = await db.query('tasks', where: 'date=?', whereArgs: [date], orderBy: orderBy);
    return rows.map(Task.fromMap).toList();
    }

  static Future<int> moveUnfinishedToTomorrow(String date) async {
    final db = await AppDb.db;
    final today = DateTime.parse(date);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    return db.rawUpdate(
      'UPDATE tasks SET date=? WHERE date=? AND done=0',
      ['${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}', date],
    );
  }

  static Future<Map<String, int>> completionByDay(int days) async {
    final db = await AppDb.db;
    final start = DateTime.now().subtract(Duration(days: days - 1));
    final startStr = '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final rows = await db.rawQuery('''
      SELECT date,
             SUM(CASE WHEN done=1 THEN 1 ELSE 0 END)*100/COUNT(*) AS rate
      FROM tasks
      WHERE date>=?
      GROUP BY date
      ORDER BY date
    ''', [startStr]);
    final map = <String, int>{};
    for (final r in rows) {
      map[r['date'] as String] = (r['rate'] as num).round();
    }
    return map;
  }

  static Future<Map<String, Map<String, int>>> countsByDateRange(String startDate, String endDate) async {
    final db = await AppDb.db;
    final rows = await db.rawQuery('''
      SELECT date,
             COUNT(*) AS total,
             SUM(CASE WHEN done=1 THEN 1 ELSE 0 END) AS done
      FROM tasks
      WHERE date>=? AND date<=?
      GROUP BY date
      ORDER BY date
    ''', [startDate, endDate]);
    final map = <String, Map<String, int>>{};
    for (final r in rows) {
      map[r['date'] as String] = {
        'total': (r['total'] as int?) ?? 0,
        'done': (r['done'] as int?) ?? 0,
      };
    }
    return map;
  }

  // 导出：在日期范围内所有“已完成”的任务
  static Future<List<Task>> completedInRange(DateTime from, DateTime to) async {
    final db = await AppDb.db;
    String d(DateTime x) => '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final rows = await db.query(
      'tasks',
      where: 'date>=? AND date<=? AND done=1',
      whereArgs: [d(from), d(to)],
      orderBy: 'date ASC, priority ASC, start_time ASC',
    );
    return rows.map(Task.fromMap).toList();
  }
}
