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
  /// Fires when a `start()` request is held back behind another download.
  /// The UI flips that track to [TrackStatus.queued].
  final void Function(String trackId)? onQueued;
  /// Fires when a queued request comes off the queue and actually begins.
  /// The UI flips that track back to [TrackStatus.downloading].
  final void Function(String trackId)? onDequeued;

  // Up to [_maxConcurrent] downloads run in parallel. googlevideo aborts
  // older long-lived streams when a newer one opens from the same client,
  // so [YoutubeDownloader.download] uses short Range-chunked requests
  // instead of a single long GET — that lets multiple downloads coexist
  // without the server killing the older one. Additional requests beyond
  // the cap sit in [_queue] until a slot frees up.
  static const _maxConcurrent = 3;
  final Map<String, _ActiveDownload> _active = {};
  final List<_Pending> _queue = [];
  // Stable per-track progress notifier — survives across attempts and is
  // created on the first lookup. This decouples "is there a live download
  // right now" from "is something subscribed to the progress" so the
  // library card doesn't lose updates if it builds before start() runs.
  final Map<String, ValueNotifier<DownloadProgress?>> _progress = {};

  DownloadManager({
    required this.onCompleted,
    required this.onFailed,
    this.onQueued,
    this.onDequeued,
    YoutubeDownloader? downloader,
    DownloadNotifier? notifier,
  })  : _downloader = downloader ?? YoutubeDownloader(),
        _notifier = notifier ?? DownloadNotifier();

  bool isActive(String trackId) => _active.containsKey(trackId);
  bool isQueued(String trackId) =>
      _queue.any((p) => p.track.id == trackId);

  /// A listenable that always reflects current progress for [trackId].
  /// Returns the same instance across calls so subscribers stay attached
  /// even if the track transitions through downloading / failed / retry.
  ValueListenable<DownloadProgress?> progressFor(String trackId) =>
      _notifierFor(trackId);

  ValueNotifier<DownloadProgress?> _notifierFor(String trackId) =>
      _progress.putIfAbsent(trackId, () => ValueNotifier<DownloadProgress?>(null));

  /// Schedule a download for [track]. If no other download is in flight,
  /// it starts immediately; otherwise it joins the back of the queue and
  /// the row is flipped to [TrackStatus.queued] via [onQueued]. The track
  /// must already carry `filePath` (the destination on disk) and the row
  /// should already be in the library before this is called.
  Future<void> start(Track track, ResolvedVideo resolved) async {
    if (_active.containsKey(track.id) || isQueued(track.id)) return;
    final filePath = track.filePath;
    if (filePath == null) {
      onFailed(track.id, 'Internal: missing filePath for download.');
      return;
    }
    if (_active.length >= _maxConcurrent) {
      _queue.add(_Pending(track, resolved));
      onQueued?.call(track.id);
      return;
    }
    await _startNow(track, resolved, filePath);
  }

  Future<void> _startNow(Track track, ResolvedVideo resolved, String filePath) async {
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
        _finalizeFailed(track.id, _shortenError(e));
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
        _drainQueue();
      },
    );
  }

  /// Pull pending requests off the queue until [_maxConcurrent] is hit or
  /// the queue is empty.
  void _drainQueue() {
    while (_active.length < _maxConcurrent && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      final filePath = next.track.filePath;
      if (filePath == null) {
        onFailed(next.track.id, 'Internal: missing filePath for download.');
        continue;
      }
      onDequeued?.call(next.track.id);
      // Fire-and-forget — we don't want callers awaiting an arbitrary chain.
      unawaited(_startNow(next.track, next.resolved, filePath));
    }
  }

  /// Cancel the active or queued download for [trackId]. Marks the track
  /// as failed via the [onFailed] callback so the row stays in the library
  /// and the user can retry.
  Future<void> cancel(String trackId) async {
    if (_active.containsKey(trackId)) {
      await _finalizeFailed(trackId, 'Cancelled');
      return;
    }
    final qi = _queue.indexWhere((p) => p.track.id == trackId);
    if (qi >= 0) {
      _queue.removeAt(qi);
      onFailed(trackId, 'Cancelled');
    }
  }

  /// Remove the active or queued download entirely (e.g., when the user
  /// deletes the row outright). Unlike [cancel], this does NOT fire
  /// [onFailed]. Also drops the cached progress notifier — the track is
  /// gone for good.
  Future<void> abort(String trackId) async {
    _queue.removeWhere((p) => p.track.id == trackId);
    final entry = _active.remove(trackId);
    if (entry == null) {
      _progress.remove(trackId)?.dispose();
      _drainQueue();
      return;
    }
    await entry.subscription?.cancel();
    await _notifier.cancel(entry.notificationId);
    await _deletePartial(entry.filePath);
    _progress.remove(trackId)?.dispose();
    _drainQueue();
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
    _drainQueue();
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
      onFailed(downloadingTrack.id, _shortenError(e));
    }
  }

  // Trim noise out of network error messages so the failed-download UI
  // doesn't show a multi-line googlevideo.com URL. We keep the human part
  // of the message and drop the class prefix and the `, uri=…` suffix.
  static String _shortenError(Object e) {
    var s = e.toString();
    // "ClientException: foo" → "foo"
    final colon = s.indexOf(': ');
    if (colon > 0 && colon < 40 && !s.substring(0, colon).contains(' ')) {
      s = s.substring(colon + 2);
    }
    // Strip everything from ", uri=" onwards (googlevideo.com URLs are
    // hundreds of characters of query string).
    final uriIdx = s.indexOf(', uri=');
    if (uriIdx > 0) s = s.substring(0, uriIdx);
    return s.trim();
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

class _Pending {
  final Track track;
  final ResolvedVideo resolved;
  _Pending(this.track, this.resolved);
}
