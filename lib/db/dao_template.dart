import 'dart:convert';
import '../models/task.dart';
import 'app_db.dart';

class TemplateDao {
  static Future<int> saveTemplate(String name, Task task) async {
    final db = await AppDB.db;
    final payload = jsonEncode(task.toMap()..remove('id'));
    return db.insert('templates', {'name': name, 'payload': payload});
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final db = await AppDB.db;
    return db.query('templates', orderBy: 'id DESC');
  }

  static Future<Task> apply(int id, String date) async {
    final db = await AppDB.db;
    final row = (await db.query('templates', where: 'id=?', whereArgs: [id])).first;
    final map = Map<String, dynamic>.from(jsonDecode(row['payload'] as String));
    map['date'] = date;
    map['done'] = 0;
    return Task.fromMap(map);
  }

  static Future<int> delete(int id) async {
    final db = await AppDB.db;
    return db.delete('templates', where: 'id=?', whereArgs: [id]);
  }
}
