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

  // 统计：时间段内的会话
  static Future<List<Map<String, dynamic>>> loadSessionsBetween(int fromMs, int toMs) async {
    final db = await AppDB.db;
    return db.query(
      'focus_sessions',
      where: 'start_ts>=? AND start_ts<? AND end_ts IS NOT NULL',
      whereArgs: [fromMs, toMs],
      orderBy: 'start_ts DESC',
    );
  }

  // 统计：时间段内的打断原因聚合
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
}
