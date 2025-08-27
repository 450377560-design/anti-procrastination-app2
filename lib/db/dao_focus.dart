// lib/db/dao_focus.dart
import 'package:sqflite/sqflite.dart';
import 'app_db.dart';

/// 专注/打断/休息 数据访问层
class FocusDao {
  // ---------- 会话写入 ----------

  /// 开始一次专注会话
  /// - [plannedMinutes] 计划分钟
  /// - [taskId] 可为空，绑定任务
  /// - [start] 允许外部指定开始时间（一般不用）
  static Future<int> startSession({
    required int plannedMinutes,
    int? taskId,
    DateTime? start,
  }) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final now = (start ?? DateTime.now()).millisecondsSinceEpoch;

    return await db.insert('focus_sessions', {
      'start_ts': now,
      'planned_minutes': plannedMinutes,
      'completed': 0,
      'task_id': taskId,
    });
  }

  /// 结束会话
  /// - [completed] 是否完成
  /// - [restSeconds] 累计休息秒（暂停时累加）
  /// - [end] 允许外部指定结束时间（一般不用）
  static Future<void> finishSession(
    int sessionId, {
    required bool completed,
    int? restSeconds,
    DateTime? end,
  }) async {
    final db = await AppDb.db;
    await _ensureTables(db);

    // 读取起始时间 & 计划分钟
    final rows = await db.query(
      'focus_sessions',
      where: 'id=?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final startTs = (rows.first['start_ts'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    final endTs = (end ?? DateTime.now()).millisecondsSinceEpoch;

    // 实际分钟 = (结束-开始)/60_000（向下取整，至少 0）
    int actualMin = ((endTs - startTs) ~/ 60000);
    if (actualMin < 0) actualMin = 0;

    await db.update(
      'focus_sessions',
      {
        'end_ts': endTs,
        'actual_minutes': actualMin,
        'completed': completed ? 1 : 0,
      },
      where: 'id=?',
      whereArgs: [sessionId],
    );

    // 记录休息时长（可选）
    if ((restSeconds ?? 0) > 0) {
      await db.insert('focus_rest', {
        'session_id': sessionId,
        'ts': endTs,
        'seconds': restSeconds,
      });
    }
  }

  /// 记录一次打断
  static Future<void> addInterruption(int sessionId, String reason) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    await db.insert('interruptions', {
      'session_id': sessionId,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'reason': reason,
    });
  }

  // ---------- 统计查询 ----------

  /// 查询区间内会话（每行含 minutes 字段，便于累计）
  static Future<List<Map<String, Object?>>> loadSessionsBetween(
      DateTime from, DateTime to) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;

    // minutes 统一为 actual_minutes；若还未结束则用 0
    final rows = await db.rawQuery('''
      SELECT
        id,
        start_ts,
        end_ts,
        planned_minutes,
        COALESCE(actual_minutes, 0) AS minutes,
        CASE completed WHEN 1 THEN 1 ELSE 0 END AS completed
      FROM focus_sessions
      WHERE start_ts BETWEEN ? AND ?
         OR (end_ts IS NOT NULL AND end_ts BETWEEN ? AND ?)
      ORDER BY start_ts ASC
    ''', [f, t, f, t]);

    return rows;
  }

  /// 查询区间内打断记录（按 reason 聚合）
  static Future<List<Map<String, Object?>>> loadInterruptionsBetween(
      DateTime from, DateTime to) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;

    final rows = await db.rawQuery('''
      SELECT id, session_id, ts, reason
      FROM interruptions
      WHERE ts BETWEEN ? AND ?
      ORDER BY ts ASC
    ''', [f, t]);
    return rows;
  }

  /// 区间内休息秒数
  static Future<int> restSecondsBetween(DateTime from, DateTime to) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;

    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(seconds),0) AS s FROM focus_rest WHERE ts BETWEEN ? AND ?',
      [f, t],
    );
    return (r.first['s'] as int?) ?? 0;
  }

  /// 连续达成天数（以“当天是否至少完成一单次”为准，从今天往前数）
  static Future<int> streakDays() async {
    final db = await AppDb.db;
    await _ensureTables(db);

    DateTime d = DateTime.now();
    int streak = 0;
    while (true) {
      final dayStart = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      final dayEnd = DateTime(d.year, d.month, d.day, 23, 59, 59, 999).millisecondsSinceEpoch;
      final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM focus_sessions WHERE completed=1 AND end_ts BETWEEN ? AND ?',
        [dayStart, dayEnd],
      );
      final cnt = (r.first['c'] as int?) ?? 0;
      if (cnt <= 0) break;
      streak += 1;
      d = d.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 总积分：简单按“完成一次 +10”
  static Future<int> pointsTotal() async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM focus_sessions WHERE completed=1',
    );
    final c = (r.first['c'] as int?) ?? 0;
    return c * 10;
  }

  /// 本月累计专注分钟
  static Future<int> minutesThisMonth() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    return minutesBetween(from, to);
  }

  /// 全部累计专注分钟
  static Future<int> minutesAll() async {
    final from = DateTime(2000, 1, 1);
    final to = DateTime.now();
    return minutesBetween(from, to);
  }

  /// 区间累计分钟
  static Future<int> minutesBetween(DateTime from, DateTime to) async {
    final rows = await loadSessionsBetween(from, to);
    int total = 0;
    for (final r in rows) {
      total += (r['minutes'] as int?) ?? 0;
    }
    return total;
  }

  // ---------- 表结构 ----------
  static Future<void> _ensureTables(Database db) async {
    // 会话表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS focus_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_ts INTEGER,
        end_ts INTEGER,
        planned_minutes INTEGER,
        actual_minutes INTEGER,
        completed INTEGER DEFAULT 0,
        task_id INTEGER
      )
    ''');

    // 打断表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS interruptions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        ts INTEGER,
        reason TEXT
      )
    ''');

    // 休息时长（暂停累加）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS focus_rest(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        ts INTEGER,
        seconds INTEGER
      )
    ''');
  }
}
