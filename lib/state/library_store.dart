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
      // Any entry left in `downloading` or `queued` is a zombie from a
      // previous run (the in-process DownloadManager can't survive app
      // death). Drop the row and best-effort-delete its partial files.
      // Persist immediately so the next read is clean.
      final survivors = <Track>[];
      var purgedAny = false;
      for (final t in tracks) {
        if (t.status == TrackStatus.downloading ||
            t.status == TrackStatus.queued) {
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

  /// Best-effort: remove every file belonging to the track — audio, thumbnail,
  /// and subtitle. Used for permanent deletion. Deletes the paths recorded on
  /// the track AND sweeps the tracks directory for any stray `<id>.*` files,
  /// since an archived track has its audio/subtitle paths nulled out yet the
  /// bytes (or a partial re-download) may still be on disk. Pass [tracksDir] so
  /// the sweep works even for a track that has no recorded paths to locate its
  /// directory by (e.g. one that never had a thumbnail). Missing files are
  /// ignored.
  Future<void> deleteFileFor(Track t, {String? tracksDir}) async {
    await _deletePaths([t.filePath, t.thumbnailPath, t.subtitlePath]);
    await _sweepById(t, tracksDir);
  }

  /// Best-effort: remove only the audio and subtitle files, leaving the
  /// thumbnail in place. Used when archiving a track — the cover and metadata
  /// survive so the row can be re-downloaded on unarchive.
  Future<void> deleteAudioFor(Track t) async {
    await _deletePaths([t.filePath, t.subtitlePath]);
  }

  Future<void> _deletePaths(List<String?> paths) async {
    for (final path in paths) {
      if (path == null) continue;
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {/* swallow — we still drop the entry */}
      }
    }
  }

  /// Delete any leftover `<id>.*` files (audio/subtitle/thumbnail) in the tracks
  /// directory. The directory is [tracksDir] when given, otherwise derived from
  /// whichever recorded path survives; if neither is available there's nothing
  /// to locate it by, so this is a no-op. The trailing dot in the prefix keeps a
  /// track id from matching a different id that merely starts with it (e.g.
  /// `abc` vs `abcd`).
  Future<void> _sweepById(Track t, String? tracksDir) async {
    final ref = tracksDir ?? t.thumbnailPath ?? t.filePath ?? t.subtitlePath;
    if (ref == null) return;
    final dir = tracksDir != null ? Directory(tracksDir) : File(ref).parent;
    if (!await dir.exists()) return;
    final prefix = '${t.id}.';
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix)) continue;
      try {
        await entity.delete();
      } catch (_) {/* swallow — best effort */}
    }
  }
}
