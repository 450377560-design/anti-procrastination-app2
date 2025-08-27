import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'equivalents_model.dart';

/// 只提供异步方法，绝不在文件顶层或构造阶段访问插件。
class EquivalentsStore {
  static const _key = 'equivalents.v1';

  static Future<List<EquivalentUnit>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.isEmpty) {
        return List.of(kDefaultEquivalentUnits);
      }
      final list = (jsonDecode(raw) as List)
          .map((e) => EquivalentUnit.fromJson(e as Map<String, dynamic>))
          .toList();
      // 容错：万一有人把 minutes 写成 0，回落默认
      if (list.any((e) => e.minutes <= 0)) {
        return List.of(kDefaultEquivalentUnits);
      }
      return list;
    } catch (_) {
      // 任何异常都回落默认，避免卡首屏
      return List.of(kDefaultEquivalentUnits);
    }
  }

  static Future<void> save(List<EquivalentUnit> units) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(units.map((e) => e.toJson()).toList());
    await sp.setString(_key, raw);
  }

  static Future<void> reset() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
