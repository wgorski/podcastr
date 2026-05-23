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
      final tracks = list.map(Track.fromJson).toList();
      // Any entry left in `downloading` is a zombie from a previous run
      // (the in-process DownloadManager can't survive app death). Drop the
      // row and best-effort-delete its partial files. Persist immediately
      // so the next read is clean.
      final survivors = <Track>[];
      var purgedAny = false;
      for (final t in tracks) {
        if (t.status == TrackStatus.downloading) {
          await deleteFileFor(t);
          purgedAny = true;
        } else {
          survivors.add(t);
        }
      }
      if (purgedAny) await save(survivors);
      return survivors;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Track> tracks) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(tracks.map((t) => t.toJson()).toList()));
  }

  /// Best-effort: remove the audio file and thumbnail. Missing files are ignored.
  Future<void> deleteFileFor(Track t) async {
    for (final path in [t.filePath, t.thumbnailPath]) {
      if (path == null) continue;
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {/* swallow — we still drop the entry */}
      }
    }
  }
}
