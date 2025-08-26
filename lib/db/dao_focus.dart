import 'app_db.dart';

class FocusDao {
  static Future<int> startSession(int plannedMinutes, {int? taskId, String? goalText}) async {
    final db = await AppDB.db;
    return await db.insert('focus_sessions', {
      'start_ts': DateTime.now().millisecondsSinceEpoch,
      'planned_minutes': plannedMinutes,
      'completed': 0,
      'task_id': taskId,
      'goal_text': goalText,
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
    if (completed) {
      final row = await db.query('focus_sessions', columns: ['task_id'], where: 'id=?', whereArgs: [id], limit: 1);
      final taskId = (row.isNotEmpty ? row.first['task_id'] as int? : null);
      if (taskId != null) {
        await db.rawUpdate('UPDATE tasks SET actual_pomos = COALESCE(actual_pomos,0) + 1 WHERE id=?', [taskId]);
      }
    }
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

  static Future<int> streakDays() async {
    final db = await AppDB.db;
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

  static Future<int> pointsTotal() async {
    final db = await AppDB.db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM focus_sessions WHERE completed=1');
    final cnt = (rows.first['cnt'] as int?) ?? 0;
    return cnt * 10;
  }
}
