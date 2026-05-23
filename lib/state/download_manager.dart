import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../services/download_notifier.dart';
import '../services/youtube_downloader.dart';

/// Owns the in-flight YouTube audio downloads.
///
/// One [_ActiveDownload] per track id. Progress is exposed via a per-track
/// [ValueListenable] so widgets can subscribe without rebuilding the entire
/// tree. The actual byte stream still comes from [YoutubeDownloader].
class DownloadManager {
  final YoutubeDownloader _downloader;
  final DownloadNotifier _notifier;
  final void Function(Track readyTrack) onCompleted;
  final void Function(String trackId, String errorMessage) onFailed;

  final Map<String, _ActiveDownload> _active = {};
  static final ValueNotifier<DownloadProgress?> _emptyProgress =
      ValueNotifier<DownloadProgress?>(null);

  DownloadManager({
    required this.onCompleted,
    required this.onFailed,
    YoutubeDownloader? downloader,
    DownloadNotifier? notifier,
  })  : _downloader = downloader ?? YoutubeDownloader(),
        _notifier = notifier ?? DownloadNotifier();

  bool isActive(String trackId) => _active.containsKey(trackId);

  /// A listenable that always reflects current progress for [trackId], or
  /// emits null when the track isn't actively downloading.
  ValueListenable<DownloadProgress?> progressFor(String trackId) {
    return _active[trackId]?.progress ?? _emptyProgress;
  }

  /// Begin streaming bytes for [track]. The track must already carry
  /// `filePath` (the destination on disk) and `status == downloading`. The
  /// row should already be in the library before this is called.
  Future<void> start(Track track, ResolvedVideo resolved) async {
    if (_active.containsKey(track.id)) return;
    final filePath = track.filePath;
    if (filePath == null) {
      onFailed(track.id, 'Internal: missing filePath for download.');
      return;
    }
    final notificationId = _notificationIdFor(track.id);
    final progress = ValueNotifier<DownloadProgress?>(null);

    // Insert synchronously so progressFor() returns the live notifier before
    // any awaits below.
    final entry = _ActiveDownload(
      progress: progress,
      notificationId: notificationId,
      filePath: filePath,
    );
    _active[track.id] = entry;

    await _notifier.progress(
      id: notificationId,
      title: track.title,
      channel: track.channel,
      percent: null,
      payload: track.id,
    );

    final stream = _downloader.download(resolved, filePath: filePath);
    entry.subscription = stream.listen(
      (p) {
        progress.value = p;
        _notifier.progress(
          id: notificationId,
          title: track.title,
          channel: track.channel,
          percent: p.totalBytes > 0 ? (p.fraction * 100).round() : null,
          payload: track.id,
        );
      },
      onError: (Object e) {
        _finalizeFailed(track.id, e.toString());
      },
      onDone: () async {
        final lastP = progress.value;
        final received = lastP?.bytesReceived ?? 0;
        if (received <= 0) {
          await _finalizeFailed(track.id,
              'Download returned no audio bytes. The stream URL is likely invalid for this video.');
          return;
        }
        String? thumbPath;
        try {
          thumbPath = await _downloader.downloadThumbnail(resolved);
        } catch (_) {/* fall back to procedural art */}
        await _notifier.complete(
          id: notificationId,
          title: track.title,
          channel: track.channel,
        );
        final readyTrack = YoutubeDownloader.buildTrack(
          resolved,
          filePath,
          received,
          thumbnailPath: thumbPath,
        );
        _cleanup(track.id);
        onCompleted(readyTrack);
      },
    );
  }

  /// Cancel the active download for [trackId]. Marks the track as failed
  /// via the [onFailed] callback so the row stays in the library and the
  /// user can retry.
  Future<void> cancel(String trackId) async {
    if (!_active.containsKey(trackId)) return;
    await _finalizeFailed(trackId, 'Cancelled');
  }

  /// Remove the active download entirely (e.g., when the user deletes the
  /// row outright). Unlike [cancel], this does NOT fire [onFailed].
  Future<void> abort(String trackId) async {
    final entry = _active.remove(trackId);
    if (entry == null) return;
    await entry.subscription?.cancel();
    await _notifier.cancel(entry.notificationId);
    await _deletePartial(entry.filePath);
    entry.progress.dispose();
  }

  Future<void> _finalizeFailed(String trackId, String message) async {
    final entry = _active.remove(trackId);
    if (entry != null) {
      await entry.subscription?.cancel();
      await _notifier.cancel(entry.notificationId);
      await _deletePartial(entry.filePath);
      entry.progress.dispose();
    }
    onFailed(trackId, message);
  }

  Future<void> _deletePartial(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {/* swallow — best effort */}
    }
  }

  void _cleanup(String trackId) {
    final entry = _active.remove(trackId);
    entry?.progress.dispose();
  }

  /// Deterministic per-track notification id so re-runs don't pile up.
  int _notificationIdFor(String trackId) =>
      trackId.hashCode & 0x7fffffff;

  /// Re-resolve a failed track and start it over. Caller is expected to
  /// have already flipped the row to [TrackStatus.downloading] for UI feedback.
  Future<void> resolveAndStart(Track downloadingTrack) async {
    final url = downloadingTrack.sourceUrl;
    if (url == null) {
      onFailed(downloadingTrack.id, 'No source URL on file for retry.');
      return;
    }
    try {
      final resolved = await _downloader.resolve(url);
      await start(downloadingTrack, resolved);
    } catch (e) {
      onFailed(downloadingTrack.id, e.toString());
    }
  }

  void dispose() {
    for (final entry in _active.values) {
      entry.subscription?.cancel();
      entry.progress.dispose();
    }
    _active.clear();
  }
}

class _ActiveDownload {
  StreamSubscription<DownloadProgress>? subscription;
  final ValueNotifier<DownloadProgress?> progress;
  final int notificationId;
  final String filePath;
  _ActiveDownload({
    required this.progress,
    required this.notificationId,
    required this.filePath,
  });
}
