import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'equivalents_model.dart';

const _kEqKey = 'eq_units_v1';

class EquivalentsStore {
  static Future<List<EquivalentUnit>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kEqKey);
    if (raw == null || raw.isEmpty) return List.of(kDefaultEquivalentUnits);
    try {
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map((e) => EquivalentUnit.fromJson(e))
          .toList();
      if (list.isEmpty) return List.of(kDefaultEquivalentUnits);
      return list;
    } catch (_) {
      return List.of(kDefaultEquivalentUnits);
    }
  }

  static Future<void> save(List<EquivalentUnit> units) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(units.map((e) => e.toJson()).toList());
    await sp.setString(_kEqKey, raw);
  }

  static Future<void> reset() => save(List.of(kDefaultEquivalentUnits));
}
