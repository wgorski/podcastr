import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-track playback position (in seconds), so resume-from-where-you-paused
/// works across app launches. One key, one JSON map — fine for hundreds of
/// tracks; switch to SQLite if the library grows much past that.
class PositionStore {
  static const _key = 'podcastr.positions.v1';

  Future<Map<String, int>> _loadAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map;
      return m.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<int?> get(String id) async => (await _loadAll())[id];

  Future<void> set(String id, int seconds) async {
    final all = await _loadAll();
    all[id] = seconds;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(all));
  }

  Future<void> remove(String id) async {
    final all = await _loadAll();
    all.remove(id);
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(all));
  }
}
