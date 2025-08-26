import 'app_db.dart';

class FocusDao {
  static Future<int> startSession(int plannedMinutes) async {
    final db = await AppDB.db;
    return await db.insert('focus_sessions', {
      'start_ts': DateTime.now().millisecondsSinceEpoch,
      'planned_minutes': plannedMinutes,
      'completed': 0,
    });
  }

  static Future<void> finishSession(int id, {required bool completed}) async {
    final db = await AppDB.db;
    await db.update(
      'focus_sessions',
      {
        'end_ts': DateTime.now().millisecondsSinceEpoch,
        'completed': completed ? 1 : 0,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  static Future<void> addInterruption(int sessionId, String reason) async {
    final db = await AppDB.db;
    await db.insert('interruptions', {
      'session_id': sessionId,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'reason': reason,
    });
  }

  static Future<List<Map<String, dynamic>>> loadSessionsBetween(int fromMs, int toMs) async {
    final db = await AppDB.db;
    return db.query(
      'focus_sessions',
      where: 'start_ts>=? AND start_ts<? AND end_ts IS NOT NULL',
      whereArgs: [fromMs, toMs],
      orderBy: 'start_ts DESC',
    );
  }

  static Future<List<Map<String, dynamic>>> loadInterruptionsBetween(int fromMs, int toMs) async {
    final db = await AppDB.db;
    return db.rawQuery('''
      SELECT reason, COUNT(*) cnt
      FROM interruptions
      WHERE ts>=? AND ts<?
      GROUP BY reason
      ORDER BY cnt DESC
    ''', [fromMs, toMs]);
  }

  /// 连续专注天数（从今天往前，直到遇到没有完成会话的那天）
  static Future<int> streakDays() async {
    final db = await AppDB.db;
    // 取最近 180 天有完成记录的日期集合
    final from = DateTime.now().subtract(const Duration(days: 180)).millisecondsSinceEpoch;
    final to = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;
    final rows = await db.rawQuery('''
      SELECT start_ts
      FROM focus_sessions
      WHERE end_ts IS NOT NULL AND completed=1 AND start_ts>=? AND start_ts<?
    ''', [from, to]);

    final days = <String>{};
    for (final r in rows) {
      final ts = r['start_ts'] as int;
      final d = DateTime.fromMillisecondsSinceEpoch(ts);
      final key = "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      days.add(key);
    }

    int streak = 0;
    DateTime cur = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    while (true) {
      final key = "${cur.year.toString().padLeft(4, '0')}-${cur.month.toString().padLeft(2, '0')}-${cur.day.toString().padLeft(2, '0')}";
      if (days.contains(key)) {
        streak += 1;
        cur = cur.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }
}
