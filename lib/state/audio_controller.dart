import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/track.dart';
import 'position_store.dart';

/// Thin wrapper around `just_audio`'s [AudioPlayer] that surfaces the bits the
/// UI cares about as plain getters + a `Listenable`-ish change callback.
class AudioController {
  final AudioPlayer _player = AudioPlayer();
  final PositionStore _positions = PositionStore();
  // In-memory mirror of the persisted resume points (track id → seconds), so
  // the UI can render a track's progress synchronously even when it isn't the
  // engine's current track (the now-playing screen is view-only until play is
  // hit). Kept coherent with `_positions` on every set / remove.
  Map<String, int> _posCache = {};
  final void Function() _onChanged;
  final void Function(String trackId)? _onCompleted;

  Track? _current;
  double _speed = 1.0;
  bool _ready = false;
  // Tracks the last broadcast `playing` flag so we can detect playing→paused
  // transitions (the spot where "abandoned near the end" should mark the track
  // as finished). Bare !playing fires on every state event, so we'd otherwise
  // mark every load / preload tick.
  bool _wasPlaying = false;
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  // Last position emitted by positionStream while playing. Used as the source
  // of truth for `_saveNow` because `_player.position` falls back to the last
  // *broadcast* updatePosition once `playing` flips false — and just_audio's
  // Android side does not broadcast on pause, so that fallback is typically
  // the position from when STATE_READY last fired (i.e. play start). Saving
  // it would clobber the per-second autosave with that stale value, which is
  // exactly the regression where pausing from the media-session notification
  // rewound the resume point to "before I started listening".
  Duration _latestPosition = Duration.zero;

  late final StreamSubscription _posSub;
  late final StreamSubscription _stateSub;

  AudioController({
    required void Function() onChanged,
    void Function(String trackId)? onCompleted,
  })  : _onChanged = onChanged,
        _onCompleted = onCompleted {
    _posSub = _player.positionStream.listen((pos) {
      _latestPosition = pos;
      _onChanged();
      _maybeSavePosition();
    });
    _stateSub = _player.playerStateStream.listen((s) {
      // When the file finishes, pause but leave the position at the end so
      // the UI keeps the waveform fully filled. Next call to [play] will
      // rewind to zero.
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        final t = _current;
        if (t != null) {
          _posCache.remove(t.id);
          _positions.remove(t.id);
          _onCompleted?.call(t.id);
        }
      } else if (_wasPlaying && !s.playing) {
        // Real pause: the user (or notification / headset / Bluetooth) stopped
        // playback. `_saveNow` reads `_latestPosition`, not `_player.position`,
        // so it captures the pause point even though just_audio does not
        // refresh updatePosition on pause. Also fire onCompleted if the user
        // gave up within the final minute — close enough to count as listened.
        unawaited(_saveNow());
        _maybeMarkFinished();
      }
      _wasPlaying = s.playing;
      _onChanged();
    });
  }

  /// Load the persisted resume points into memory. Call once at startup so
  /// [resumeProgress] / [resumePosition] return real values on the first build.
  Future<void> primePositions() async {
    _posCache = await _positions.all();
    _onChanged();
  }

  /// Saved progress 0..1 for any track, usable when it is *not* the engine's
  /// current track. A finished track reads as full (its resume point is dropped
  /// on completion, mirroring the live "waveform stays filled when done" rule).
  double resumeProgress(Track t) {
    if (t.finished) return 1.0;
    final secs = _posCache[t.id];
    if (secs == null || t.duration <= 0) return 0.0;
    return (secs / t.duration).clamp(0.0, 1.0);
  }

  /// Saved playback position for any track, mirroring [resumeProgress].
  Duration resumePosition(Track t) {
    if (t.finished) return Duration(seconds: t.duration);
    return Duration(seconds: _posCache[t.id] ?? 0);
  }

  /// Drop the saved resume point for a track (used when the track is deleted).
  Future<void> forget(String id) {
    _posCache.remove(id);
    return _positions.remove(id);
  }

  /// Move the saved resume point for a track that is *not* the engine's
  /// current one — e.g. the user scrubbed the waveform of a track they're only
  /// viewing while something else plays. Updates the in-memory mirror and
  /// persists so [resumeProgress] / [resumePosition] reflect the drag
  /// immediately, without disturbing live playback. Playing the track later
  /// resumes from here (see [load], which restores the saved point).
  Future<void> setResume(Track t, double fraction) async {
    if (t.duration <= 0) return;
    final secs = (fraction.clamp(0.0, 1.0) * t.duration).round();
    _posCache[t.id] = secs;
    _onChanged();
    await _positions.set(t.id, secs);
  }

  /// Treat the current track as finished if playback is within the final
  /// minute. Called when the user pauses or switches away from a track.
  /// Safe to call repeatedly — the host marks tracks as finished idempotently.
  void _maybeMarkFinished() {
    final t = _current;
    if (t == null) return;
    final cb = _onCompleted;
    if (cb == null) return;
    final pos = _effectivePosition;
    final total = _player.duration ?? Duration(seconds: t.duration);
    if (total <= Duration.zero) return;
    if (pos <= Duration.zero) return;
    if (total - pos < const Duration(seconds: 60)) {
      cb(t.id);
    }
  }

  void _maybeSavePosition() {
    final now = DateTime.now();
    // Save roughly once a second while playing — the throttle is short so a
    // crash, kill, or missed pause event loses at most a second of progress.
    if (now.difference(_lastSavedAt) < const Duration(seconds: 1)) return;
    unawaited(_saveNow());
  }

  Future<void> _saveNow() async {
    final t = _current;
    if (t == null) return;
    // Prefer the live extrapolated position while playing; once paused, fall
    // back to the last value positionStream emitted while playing. See
    // [_latestPosition] for why `_player.position` is unreliable on pause.
    final pos = _effectivePosition;
    final total = _player.duration ?? Duration(seconds: t.duration);
    // Don't save the trivial endpoints: 0 means "fresh", end means "done".
    if (pos > const Duration(seconds: 2) && pos < total - const Duration(seconds: 2)) {
      _lastSavedAt = DateTime.now();
      _posCache[t.id] = pos.inSeconds;
      await _positions.set(t.id, pos.inSeconds);
    }
  }

  Track? get current => _current;
  bool get playing => _player.playing;
  double get speed => _speed;

  /// True once the current track's source is fully loaded *and* seeked to its
  /// resume point. False during [load]'s setup window — where `_player.position`
  /// transiently reads 0 after `setAudioSource` but before the resume seek. The
  /// UI uses this to keep showing the resume point (instead of a flickering 0:00)
  /// until live playback position is trustworthy.
  bool get ready => _ready;

  /// The position to report to the UI and persistence. While playing,
  /// `_player.position` is live and accurate. Once paused, it is unreliable on
  /// Android — it falls back to the last *broadcast* updatePosition, and the
  /// Android side does not broadcast on pause, so it typically reads the
  /// position from when STATE_READY last fired (≈ play start). [_latestPosition]
  /// holds the last trustworthy position (last positionStream tick while
  /// playing, kept fresh on every seek), so we report that when paused. See
  /// [_latestPosition].
  Duration get _effectivePosition => effectivePosition(
        playing: _player.playing,
        playerPosition: _player.position,
        latestPosition: _latestPosition,
      );

  /// Pure position-selection rule shared by the UI getters, [_saveNow], and
  /// [_maybeMarkFinished]. Extracted so the paused-position behavior (the
  /// media-session-pause regression) is unit-testable without the audio engine.
  @visibleForTesting
  static Duration effectivePosition({
    required bool playing,
    required Duration playerPosition,
    required Duration latestPosition,
  }) =>
      playing ? playerPosition : latestPosition;

  /// Pure progress-fraction rule, extracted alongside [effectivePosition] so
  /// the now-playing waveform's value is unit-testable.
  @visibleForTesting
  static double progressFraction({
    required Duration position,
    required Duration total,
    required bool completed,
  }) {
    if (completed) return 1.0;
    if (total.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Fraction 0..1 — based on actual loaded duration when available, otherwise
  /// the metadata duration from the Track. A finished track stays at 1.0 until
  /// the user hits play again, at which point [play] seeks back to zero.
  double get progress => progressFraction(
        position: _effectivePosition,
        total: duration,
        completed: _player.processingState == ProcessingState.completed,
      );

  Duration get position => _effectivePosition;
  Duration get duration =>
      _player.duration ?? Duration(seconds: _current?.duration ?? 0);

  /// Load a track but don't auto-play. If [andPlay] is true, plays immediately.
  /// Resumes from the last persisted position if one exists.
  Future<void> load(Track t, {bool andPlay = false}) async {
    // Persist the previous track's position before switching off it.
    await _saveNow();
    // If the user is opening a *different* podcast, the one they're leaving
    // counts as finished when only the final minute is left.
    if (_current != null && _current!.id != t.id) {
      _maybeMarkFinished();
    }
    _current = t;
    _latestPosition = Duration.zero;
    _ready = false;
    _wasPlaying = false;
    final path = t.filePath;
    if (path == null) {
      _onChanged();
      return;
    }
    try {
      // `setAudioSource` preserves the player's play/pause flag. Loading a new
      // track while another one is playing would otherwise immediately start
      // the new source. Pause first unless the caller explicitly asked to play
      // (e.g. opening a track from the library should not auto-start it).
      if (!andPlay && _player.playing) await _player.pause();
      final source = AudioSource.uri(
        Uri.file(path),
        tag: MediaItem(
          id: t.id,
          title: t.title,
          artist: t.channel,
          duration: Duration(seconds: t.duration),
          artUri: (t.thumbnailPath != null && File(t.thumbnailPath!).existsSync())
              ? Uri.file(t.thumbnailPath!)
              : null,
        ),
      );
      await _player.setAudioSource(source);
      await _player.setSpeed(_speed);
      // Restore the saved resume point, if any.
      final saved = await _positions.get(t.id);
      if (saved != null) {
        _posCache[t.id] = saved;
      } else {
        _posCache.remove(t.id);
      }
      if (saved != null && saved > 0) {
        final total = _player.duration ?? Duration(seconds: t.duration);
        final target = Duration(seconds: saved);
        if (target < total - const Duration(seconds: 1)) {
          await _player.seek(target);
          // Anchor the trustworthy position to the resume point now, so a
          // paused now-playing view renders it without waiting for the first
          // positionStream tick.
          _latestPosition = target;
        }
      }
      _ready = true;
      _onChanged();
      if (andPlay) await _player.play();
    } catch (_) {
      _ready = false;
      _onChanged();
    }
  }

  Future<void> play() async {
    if (!_ready && _current?.filePath != null) {
      await load(_current!, andPlay: true);
      return;
    }
    // After the track has played through, the player sits at the end with
    // processingState=completed. Hitting play again should restart from zero.
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
      _latestPosition = Duration.zero;
    }
    await _player.play();
  }

  Future<void> pause() async => _player.pause();

  Future<void> toggle() async => playing ? pause() : play();

  Future<void> seekFraction(double f) async {
    final total = duration.inMilliseconds;
    if (total == 0) return;
    final target = Duration(milliseconds: (f.clamp(0.0, 1.0) * total).round());
    await _player.seek(target);
    // Keep the trustworthy position current so a seek while paused (e.g.
    // scrubbing the waveform) is reflected immediately, not only on the next
    // positionStream tick. See [_latestPosition].
    _latestPosition = target;
  }

  Future<void> seekRelative(Duration delta) async {
    // Base the delta on the trustworthy position, not `_player.position`, which
    // is stale while paused (see [_latestPosition]).
    final next = _effectivePosition + delta;
    final clamped = next.isNegative ? Duration.zero : (next > duration ? duration : next);
    await _player.seek(clamped);
    _latestPosition = clamped;
  }

  Future<void> setSpeed(double s) async {
    _speed = s;
    await _player.setSpeed(s);
    _onChanged();
  }

  Future<void> stop() async {
    await _player.stop();
    _current = null;
    _latestPosition = Duration.zero;
    _ready = false;
    _onChanged();
  }

  Future<void> dispose() async {
    await _saveNow();
    await _posSub.cancel();
    await _stateSub.cancel();
    await _player.dispose();
  }
}
