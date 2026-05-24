import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../services/youtube_downloader.dart';

/// Owns the lifecycle of in-flight YouTube audio downloads.
///
/// The actual byte stream lives in a native WorkManager-backed foreground
/// service ([DownloadWorker.kt]); this class is just the Dart-side façade
/// that fans worker events out to the UI:
///
///   - per-track progress notifier (so a card subscribes only to its own
///     progress and isn't rebuilt on every byte from a sibling download)
///   - completion → assembled [Track] → [onCompleted]
///   - failure / cancel → [onFailed] with a user-facing message
///   - queued / dequeued → status callbacks for [TrackStatus] transitions
///
/// Restart-resilience: [reconnect] re-attaches to any work that's still
/// running (or already completed) in the background after an app kill.
class DownloadManager {
  final YoutubeDownloader _downloader;
  final void Function(Track readyTrack) onCompleted;
  final void Function(String trackId, String errorMessage) onFailed;
  final void Function(String trackId)? onQueued;
  final void Function(String trackId)? onDequeued;

  final Map<String, ValueNotifier<DownloadProgress?>> _progress = {};
  final Map<String, _Tracked> _active = {};
  StreamSubscription<DownloadEvent>? _eventsSub;

  DownloadManager({
    required this.onCompleted,
    required this.onFailed,
    this.onQueued,
    this.onDequeued,
    YoutubeDownloader? downloader,
  }) : _downloader = downloader ?? YoutubeDownloader() {
    _eventsSub = _downloader.events.listen(_onEvent);
  }

  bool isActive(String trackId) => _active.containsKey(trackId);
  bool isQueued(String trackId) => _active[trackId]?.queued == true;

  /// Stable progress notifier per track. Survives across retries so a
  /// subscribing card built before [start] returns still sees the
  /// progress when the first event arrives.
  ValueListenable<DownloadProgress?> progressFor(String trackId) =>
      _notifierFor(trackId);

  ValueNotifier<DownloadProgress?> _notifierFor(String trackId) =>
      _progress.putIfAbsent(trackId, () => ValueNotifier<DownloadProgress?>(null));

  /// Enqueue a fresh download for [track]. Requires the track to carry
  /// the original YouTube `sourceUrl` (the worker re-resolves it
  /// internally — googlevideo URLs expire across app restarts).
  Future<void> start(Track track) async {
    if (_active.containsKey(track.id)) return;
    final sourceUrl = track.sourceUrl;
    if (sourceUrl == null) {
      onFailed(track.id, 'No source URL on file for download.');
      return;
    }
    final tracksDir = await YoutubeDownloader.tracksDir();
    _active[track.id] = _Tracked(track: track);
    _notifierFor(track.id).value = null;
    await _downloader.enqueue(
      videoId: track.id,
      sourceUrl: sourceUrl,
      tracksDir: tracksDir,
      title: track.title,
      channel: track.channel,
    );
  }

  /// User-initiated cancel — the row stays in the library marked as
  /// failed so the user can retry.
  Future<void> cancel(String trackId) async {
    if (!_active.containsKey(trackId)) return;
    await _downloader.cancel(trackId);
    // The native side will emit a 'failed' event with message
    // "Cancelled" — handled in [_onEvent].
  }

  /// User deleted the row outright. Drops both the work and the progress
  /// notifier; does NOT fire [onFailed].
  Future<void> abort(String trackId) async {
    _active.remove(trackId);
    await _downloader.abandon(trackId);
    _progress.remove(trackId)?.dispose();
  }

  /// Re-enqueue a previously failed download. Caller is expected to have
  /// already flipped the row to [TrackStatus.downloading] for UI feedback.
  Future<void> retry(Track downloadingTrack) => start(downloadingTrack);

  /// Re-attach to in-flight work after an app restart. For each
  /// [downloadingTracks], asks the native side what state the work is in
  /// — events arrive via [_onEvent] just like a fresh download.
  Future<void> reconnect(Iterable<Track> downloadingTracks) async {
    for (final t in downloadingTracks) {
      if (_active.containsKey(t.id)) continue;
      _active[t.id] = _Tracked(track: t);
      _notifierFor(t.id).value = null;
      try {
        await _downloader.restore(t.id);
      } catch (e) {
        _active.remove(t.id);
        onFailed(t.id, _shortenError(e));
      }
    }
  }

  void _onEvent(DownloadEvent e) {
    final tracked = _active[e.videoId];
    if (tracked == null) return;
    if (e is DownloadQueued) {
      // Ignore the very first ENQUEUED — WorkManager always passes through
      // it on the way to RUNNING, and the row is already painted as
      // "downloading" optimistically. Only flip to queued if we've already
      // seen progress and the work was re-queued by the scheduler.
      if (tracked.hasSeenProgress && !tracked.queued) {
        tracked.queued = true;
        onQueued?.call(e.videoId);
      }
    } else if (e is DownloadProgressEvent) {
      if (tracked.queued) {
        tracked.queued = false;
        onDequeued?.call(e.videoId);
      }
      tracked.hasSeenProgress = true;
      _notifierFor(e.videoId).value = e.progress;
    } else if (e is DownloadCompleted) {
      _active.remove(e.videoId);
      final ready = _buildTrack(tracked.track, e);
      _progress.remove(e.videoId)?.dispose();
      onCompleted(ready);
    } else if (e is DownloadFailed) {
      _active.remove(e.videoId);
      // Keep the progress notifier alive — the user may retry, and a
      // library card may still be subscribed.
      onFailed(e.videoId, e.message);
    }
  }

  Track _buildTrack(Track original, DownloadCompleted e) {
    final palette = paletteForId(e.videoId);
    return Track(
      id: e.videoId,
      title: e.title.isNotEmpty ? e.title : original.title,
      channel: e.channel.isNotEmpty ? e.channel : original.channel,
      duration: e.durationSeconds > 0 ? e.durationSeconds : original.duration,
      size: _formatSize(e.bytesReceived),
      addedAt: 'Today',
      color1: palette.c1,
      color2: palette.c2,
      filePath: e.filePath,
      thumbnailPath: e.thumbnailPath,
      subtitlePath: e.subtitlePath,
      subtitleLanguage: e.subtitleLanguage,
      subtitleIsAutoGenerated: e.subtitleAutoGenerated,
      sourceUrl: original.sourceUrl,
    );
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '— MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  static String _shortenError(Object e) {
    var s = e.toString();
    final colon = s.indexOf(': ');
    if (colon > 0 && colon < 40 && !s.substring(0, colon).contains(' ')) {
      s = s.substring(colon + 2);
    }
    final uriIdx = s.indexOf(', uri=');
    if (uriIdx > 0) s = s.substring(0, uriIdx);
    return s.trim();
  }

  void dispose() {
    _eventsSub?.cancel();
    _eventsSub = null;
    for (final n in _progress.values) {
      n.dispose();
    }
    _progress.clear();
    _active.clear();
  }
}

class _Tracked {
  final Track track;
  bool hasSeenProgress = false;
  bool queued = false;
  _Tracked({required this.track});
}
