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
  // Stable per-track progress notifier — survives across attempts and is
  // created on the first lookup. This decouples "is there a live download
  // right now" from "is something subscribed to the progress" so the
  // library card doesn't lose updates if it builds before start() runs.
  final Map<String, ValueNotifier<DownloadProgress?>> _progress = {};

  DownloadManager({
    required this.onCompleted,
    required this.onFailed,
    YoutubeDownloader? downloader,
    DownloadNotifier? notifier,
  })  : _downloader = downloader ?? YoutubeDownloader(),
        _notifier = notifier ?? DownloadNotifier();

  bool isActive(String trackId) => _active.containsKey(trackId);

  /// A listenable that always reflects current progress for [trackId].
  /// Returns the same instance across calls so subscribers stay attached
  /// even if the track transitions through downloading / failed / retry.
  ValueListenable<DownloadProgress?> progressFor(String trackId) =>
      _notifierFor(trackId);

  ValueNotifier<DownloadProgress?> _notifierFor(String trackId) =>
      _progress.putIfAbsent(trackId, () => ValueNotifier<DownloadProgress?>(null));

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
    final progress = _notifierFor(track.id);
    // Reset to "starting" so a previous failed attempt's last value isn't
    // surfaced on a fresh start.
    progress.value = null;

    // Insert synchronously so isActive() and the byte-stream subscription
    // are wired before any await below.
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
  /// Also drops the cached progress notifier — the track is gone for good.
  Future<void> abort(String trackId) async {
    final entry = _active.remove(trackId);
    if (entry == null) {
      _progress.remove(trackId)?.dispose();
      return;
    }
    await entry.subscription?.cancel();
    await _notifier.cancel(entry.notificationId);
    await _deletePartial(entry.filePath);
    _progress.remove(trackId)?.dispose();
  }

  Future<void> _finalizeFailed(String trackId, String message) async {
    final entry = _active.remove(trackId);
    if (entry != null) {
      await entry.subscription?.cancel();
      await _notifier.cancel(entry.notificationId);
      await _deletePartial(entry.filePath);
    }
    // Keep the progress notifier alive — the user may retry, and the
    // library card may still be subscribed.
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
    _active.remove(trackId);
    // Track succeeded — drop the progress notifier; the library card will
    // re-render with the ready meta row and no longer subscribes.
    _progress.remove(trackId)?.dispose();
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
    }
    _active.clear();
    for (final n in _progress.values) {
      n.dispose();
    }
    _progress.clear();
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
