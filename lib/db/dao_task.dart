// lib/db/dao_task.dart
import 'package:sqflite/sqflite.dart';
import 'app_db.dart';
import '../models/task.dart';

class TaskDao {
  /// YYYY-MM-DD
  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // 确保表存在（只在首次调用时）
  static Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks(
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
        done INTEGER DEFAULT 0,
        estimate_pomos INTEGER,
        actual_pomos INTEGER,
        note TEXT
      )
    ''');
  }

  /// 插入任务。若上层未填 date，则兜底为今天，避免列表按日期查询时查不到
  static Future<int> insert(Task t) async {
    final db = await AppDb.db;
    await _ensureTable(db);
    final m = t.toMap();
    final date = (m['date'] as String?)?.trim();
    if (date == null || date.isEmpty) {
      m['date'] = _fmtDate(DateTime.now());
    }
    final id = await db.insert('tasks', m);
    return id;
  }

  static Future<void> update(Task t) async {
    if (t.id == null) return;
    final db = await AppDb.db;
    await _ensureTable(db);
    await db.update('tasks', t.toMap(), where: 'id=?', whereArgs: [t.id]);
  }

  static Future<void> deleteMany(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await AppDb.db;
    await _ensureTable(db);
    final ph = List.filled(ids.length, '?').join(',');
    await db.delete('tasks', where: 'id IN ($ph)', whereArgs: ids);
  }

  static Future<void> setDoneMany(List<int> ids, bool done) async {
    if (ids.isEmpty) return;
    final db = await AppDb.db;
    await _ensureTable(db);
    final ph = List.filled(ids.length, '?').join(',');
    await db.update('tasks', {'done': done ? 1 : 0}, where: 'id IN ($ph)', whereArgs: ids);
  }

  static Future<void> toggleDone(int id) async {
    final db = await AppDb.db;
    await _ensureTable(db);
    // 直接翻转
    await db.execute('UPDATE tasks SET done = CASE done WHEN 1 THEN 0 ELSE 1 END WHERE id=?', [id]);
  }

  /// 当天任务列表；[sort] 可为 'priority' 或 'time'
  static Future<List<Task>> listByDate(String date, {String sort = 'priority'}) async {
    final db = await AppDb.db;
    await _ensureTable(db);
    String orderBy = 'priority ASC, start_time ASC';
    if (sort == 'time') orderBy = 'start_time ASC, priority ASC';
    final rows = await db.query('tasks', where: 'date=?', whereArgs: [date], orderBy: orderBy);
    return rows.map(Task.fromMap).toList();
  }

  /// 将某天的未完成任务顺延到明天
  static Future<int> moveUnfinishedToTomorrow(String date) async {
    final db = await AppDb.db;
    await _ensureTable(db);
    final d = DateTime.parse(date);
    final tomorrow = _fmtDate(d.add(const Duration(days: 1)));
    return await db.update(
      'tasks',
      {'date': tomorrow},
      where: 'date=? AND done=0',
      whereArgs: [date],
    );
  }

  /// 统计某区间内（含端点）每天：total/done
  /// 返回：{ 'YYYY-MM-DD': {'total': X, 'done': Y}, ... }
  static Future<Map<String, Map<String, int>>> countsByDateRange(
      String fromDate, String toDate) async {
    final db = await AppDb.db;
    await _ensureTable(db);
    // 包含端点：BETWEEN from AND to
    final rows = await db.rawQuery('''
      SELECT date,
             COUNT(*) AS total,
             SUM(CASE done WHEN 1 THEN 1 ELSE 0 END) AS done
      FROM tasks
      WHERE date BETWEEN ? AND ?
      GROUP BY date
      ORDER BY date ASC
    ''', [fromDate, toDate]);

    final out = <String, Map<String, int>>{};
    for (final r in rows) {
      final d = r['date'] as String;
      out[d] = {
        'total': (r['total'] as int?) ?? 0,
        'done': (r['done'] as int?) ?? 0,
      };
    }
    return out;
  }

  /// 导出：某区间内已完成任务
  static Future<List<Task>> completedInRange(String fromDate, String toDate) async {
    final db = await AppDb.db;
    await _ensureTable(db);
    final rows = await db.query(
      'tasks',
      where: 'done=1 AND date BETWEEN ? AND ?',
      whereArgs: [fromDate, toDate],
      orderBy: 'date ASC, start_time ASC',
    );
    return rows.map(Task.fromMap).toList();
  }
}
