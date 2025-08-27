import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'app_db.dart';

/// 说明：
/// 1) 兼容既有表：focus_sessions / interruptions / focus_rest
///    - focus_sessions: id, start_ts, end_ts, planned_minutes, actual_minutes, completed(0/1), task_id
///    - interruptions : id, session_id, ts, reason
///    - focus_rest    : id, session_id, ts, seconds
/// 2) 即使某些列不存在（如 completed / actual_minutes），也会有降级行为：
///    - “完成”以 end_ts 非空近似
///    - “分钟”优先 actual_minutes，其次 planned_minutes，再其次 (end-start)/60
class FocusDao {
  // ------------------- 写入类接口（供专注页调用） -------------------

  /// 开始一次专注；返回 sessionId
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
      'task_id': taskId,
      'completed': 0,
    });
  }

  /// 结束一次专注；completed=true 代表“完成”，false 代表“中止/打断”
  static Future<void> finishSession(
    int sessionId, {
    required bool completed,
    DateTime? end,
  }) async {
    final db = await AppDb.db;
    await _ensureTables(db);

    // 读取开始时间和计划分钟，用于兜底计算
    final rows = await db.query('focus_sessions',
        columns: ['start_ts', 'planned_minutes'],
        where: 'id=?',
        whereArgs: [sessionId]);
    if (rows.isEmpty) return;

    final mStart = (rows.first['start_ts'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    final planned = (rows.first['planned_minutes'] as int?) ?? 0;

    final endMs = (end ?? DateTime.now()).millisecondsSinceEpoch;
    final diffMin = ((endMs - mStart) / 60000).round();
    final actual = diffMin > 0 ? diffMin : (planned > 0 ? planned : 0);

    // 可能不存在 completed/actual_minutes 列，做两次更新尝试
    try {
      await db.update(
        'focus_sessions',
        {
          'end_ts': endMs,
          'actual_minutes': actual,
          'completed': completed ? 1 : 0,
        },
        where: 'id=?',
        whereArgs: [sessionId],
      );
    } catch (_) {
      // 降级：只更新 end_ts
      await db.update(
        'focus_sessions',
        {'end_ts': endMs},
        where: 'id=?',
        whereArgs: [sessionId],
      );
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

  /// 追加休息时长（秒）。暂停→恢复时由专注页累加一次即可。
  static Future<void> addRestSeconds(int sessionId, int seconds) async {
    if (seconds <= 0) return;
    final db = await AppDb.db;
    await _ensureTables(db);
    await db.insert('focus_rest', {
      'session_id': sessionId,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'seconds': seconds,
    });
  }

  // ------------------- 统计聚合接口（供统计页调用） -------------------

  /// 区间内所有专注会话（用于按条目渲染或外部自定义汇总）
  /// 返回 Map 至少包含：minutes（本方法计算后的分钟数）
  static Future<List<Map<String, Object?>>> loadSessionsBetween(
      DateTime from, DateTime to) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;

    // 选取可能的分钟列，兜底用 (end-start)/60
    final rows = await db.rawQuery('''
      SELECT
        id,
        start_ts,
        end_ts,
        planned_minutes,
        actual_minutes,
        CASE
          WHEN actual_minutes IS NOT NULL THEN actual_minutes
          WHEN end_ts IS NOT NULL AND start_ts IS NOT NULL
            THEN CAST(ROUND((end_ts - start_ts) / 60000.0) AS INTEGER)
          WHEN planned_minutes IS NOT NULL THEN planned_minutes
          ELSE 0
        END AS minutes,
        completed,
        task_id
      FROM focus_sessions
      WHERE
        (start_ts BETWEEN ? AND ?)
        OR (end_ts IS NOT NULL AND end_ts BETWEEN ? AND ?)
    ''', [f, t, f, t]);

    return rows;
  }

  /// 区间内的打断记录
  static Future<List<Map<String, Object?>>> loadInterruptionsBetween(
      DateTime from, DateTime to) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;
    return await db.query(
      'interruptions',
      where: 'ts BETWEEN ? AND ?',
      whereArgs: [f, t],
      orderBy: 'ts ASC',
    );
  }

  /// 区间内休息秒数总和
  static Future<int> restSecondsBetween(DateTime from, DateTime to) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;
    try {
      final r = await db.rawQuery(
          'SELECT COALESCE(SUM(seconds),0) AS s FROM focus_rest WHERE ts BETWEEN ? AND ?',
          [f, t]);
      return (r.first['s'] as int?) ?? 0;
    } catch (_) {
      // 如果没有 focus_rest 表/列，返回 0
      return 0;
    }
  }

  /// 连续达成天数（从今天往回数，某天有“完成”会话则+1）
  static Future<int> streakDays() async {
    final db = await AppDb.db;
    await _ensureTables(db);

    int streak = 0;
    DateTime cursor =
        DateTime.now(); // 今天 23:59:59 作为上界，逐天回溯
    while (true) {
      final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
      final dayEnd = dayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

      final f = dayStart.millisecondsSinceEpoch;
      final t = dayEnd.millisecondsSinceEpoch;

      // 优先用 completed=1，其次用 end_ts 非空近似
      int cnt = 0;
      try {
        final r = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM focus_sessions WHERE completed=1 AND end_ts BETWEEN ? AND ?',
          [f, t],
        );
        cnt = (r.first['c'] as int?) ?? 0;
      } catch (_) {
        final r = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM focus_sessions WHERE end_ts IS NOT NULL AND end_ts BETWEEN ? AND ?',
          [f, t],
        );
        cnt = (r.first['c'] as int?) ?? 0;
      }

      if (cnt > 0) {
        streak += 1;
        cursor = dayStart.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// 积分总计：每完成一次会话 +10 分
  static Future<int> pointsTotal() async {
    final db = await AppDb.db;
    await _ensureTables(db);
    try {
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM focus_sessions WHERE completed=1');
      final c = (r.first['c'] as int?) ?? 0;
      return c * 10;
    } catch (_) {
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM focus_sessions WHERE end_ts IS NOT NULL');
      final c = (r.first['c'] as int?) ?? 0;
      return c * 10;
    }
  }

  /// 区间内专注分钟总和（供“等价卡片”口径）
  static Future<int> minutesBetween(DateTime from, DateTime to) async {
    final rows = await loadSessionsBetween(from, to);
    var sum = 0;
    for (final r in rows) {
      sum += (r['minutes'] as int?) ?? 0;
    }
    return sum;
  }

  /// 本月专注分钟
  static Future<int> minutesThisMonth() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    return minutesBetween(from, to);
  }

  /// 累计专注分钟（全表）
  static Future<int> minutesAll() async {
    final db = await AppDb.db;
    await _ensureTables(db);
    // 直接聚合，避免全量拉回
    try {
      final r = await db.rawQuery('''
        SELECT SUM(
          CASE
            WHEN actual_minutes IS NOT NULL THEN actual_minutes
            WHEN end_ts IS NOT NULL AND start_ts IS NOT NULL
              THEN CAST(ROUND((end_ts - start_ts)/60000.0) AS INTEGER)
            WHEN planned_minutes IS NOT NULL THEN planned_minutes
            ELSE 0
          END
        ) AS total
        FROM focus_sessions
      ''');
      return (r.first['total'] as int?) ?? 0;
    } catch (_) {
      // 极端降级：读全部后在内存算
      final rows = await db.query('focus_sessions');
      var sum = 0;
      for (final r in rows) {
        final am = r['actual_minutes'] as int?;
        final pm = r['planned_minutes'] as int?;
        final st = r['start_ts'] as int?;
        final et = r['end_ts'] as int?;
        int m = 0;
        if (am != null) {
          m = am;
        } else if (st != null && et != null) {
          m = ((et - st) / 60000).round();
        } else if (pm != null) {
          m = pm;
        }
        sum += m;
      }
      return sum;
    }
  }

  // ------------------- 表结构兜底（如不存在则创建最小结构） -------------------

  static Future<void> _ensureTables(Database db) async {
    // focus_sessions
    await db.execute('''
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
    // interruptions
    await db.execute('''
      CREATE TABLE IF NOT EXISTS interruptions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        ts INTEGER,
        reason TEXT
      )
    ''');
    // focus_rest
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
