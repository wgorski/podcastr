import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Persists the library to SharedPreferences as a JSON array.
/// Deletes the audio file from disk when a track is removed.
class LibraryStore {
  static const _key = 'podcastr.tracks.v1';

  Future<List<Track>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(Track.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Track> tracks) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(tracks.map((t) => t.toJson()).toList()));
  }

  /// Best-effort: remove the audio file. Missing files are ignored.
  Future<void> deleteFileFor(Track t) async {
    final path = t.filePath;
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {/* swallow — we still drop the entry */}
    }
  }
}
