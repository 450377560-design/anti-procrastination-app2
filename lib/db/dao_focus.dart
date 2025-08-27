import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:anti_procrastination_app2/db/app_db.dart';

/// 说明：
/// - 保留与兼容：startSession 现在既支持「位置参数 minutes」也支持命名参数 plannedMinutes，
///   这样你现有的 focus_page.dart 不用改；
/// - finishSession 兼容可选命名参数 restSeconds（你的代码里有传），会自动累加到休息表；
/// - 聚合接口补齐：minutesThisMonth / minutesAll 用于统计页“等价卡片”本月/累计；
class FocusDao {
  // ------------------- 写入类接口（供专注页调用） -------------------

  /// 开始一次专注；返回 sessionId
  /// 兼容两种用法：
  ///   startSession(25) 或 startSession(plannedMinutes: 25, taskId: 1)
  static Future<int> startSession([int? minutes, {
    int? plannedMinutes,
    int? taskId,
    DateTime? start,
  }]) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final now = (start ?? DateTime.now()).millisecondsSinceEpoch;
    final plan = plannedMinutes ?? minutes ?? 25;
    return await db.insert('focus_sessions', {
      'start_ts': now,
      'planned_minutes': plan,
      'task_id': taskId,
      'completed': 0,
    });
  }

  /// 结束一次专注；completed=true 代表“完成”，false 代表“中止/打断”
  /// 兼容可选参数 restSeconds：若传入则同时记入休息统计
  static Future<void> finishSession(
    int sessionId, {
    required bool completed,
    int? restSeconds,
    DateTime? end,
  }) async {
    final db = await AppDb.db;
    await _ensureTables(db);

    // 读取 start_ts / planned_minutes 做兜底
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
      // 降级（老表无 completed/actual_minutes）
      await db.update('focus_sessions', {'end_ts': endMs}, where: 'id=?', whereArgs: [sessionId]);
    }

    // 若带了休息秒数，记一条
    if (restSeconds != null && restSeconds > 0) {
      await addRestSeconds(sessionId, restSeconds);
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

  /// 区间内所有专注会话；返回 Map 至少包含：minutes（计算后的分钟数）
  static Future<List<Map<String, Object?>>> loadSessionsBetween(
      DateTime from, DateTime to) async {
    final db = await AppDb.db;
    await _ensureTables(db);
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;

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
      return 0;
    }
  }

  /// 连续达成天数（有完成会话算 1 天）
  static Future<int> streakDays() async {
    final db = await AppDb.db;
    await _ensureTables(db);

    int streak = 0;
    DateTime cursor = DateTime.now();
    while (true) {
      final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
      final dayEnd = dayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

      final f = dayStart.millisecondsSinceEpoch;
      final t = dayEnd.millisecondsSinceEpoch;

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
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM focus_sessions WHERE completed=1');
      final c = (r.first['c'] as int?) ?? 0;
      return c * 10;
    } catch (_) {
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM focus_sessions WHERE end_ts IS NOT NULL');
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS interruptions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        ts INTEGER,
        reason TEXT
      )
    ''');
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
