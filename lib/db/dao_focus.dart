import 'package:sqflite/sqflite.dart';
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
}
