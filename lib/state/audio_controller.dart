import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/track.dart';
import 'position_store.dart';

/// Thin wrapper around `just_audio`'s [AudioPlayer] that surfaces the bits the
/// UI cares about as plain getters + a `Listenable`-ish change callback.
class AudioController {
  final AudioPlayer _player = AudioPlayer();
  final PositionStore _positions = PositionStore();
  final void Function() _onChanged;
  final void Function(String trackId)? _onCompleted;

  Track? _current;
  double _speed = 1.0;
  bool _ready = false;
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
          _positions.remove(t.id);
          _onCompleted?.call(t.id);
        }
      } else if (!s.playing) {
        // Pause from any source (in-app button, notification, Bluetooth,
        // headset). `_saveNow` reads `_latestPosition`, not `_player.position`,
        // so this captures the actual pause point even though just_audio does
        // not refresh updatePosition on pause.
        unawaited(_saveNow());
      }
      _onChanged();
    });
  }

  /// Drop the saved resume point for a track (used when the track is deleted).
  Future<void> forget(String id) => _positions.remove(id);

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
    final pos = _player.playing ? _player.position : _latestPosition;
    final total = _player.duration ?? Duration(seconds: t.duration);
    // Don't save the trivial endpoints: 0 means "fresh", end means "done".
    if (pos > const Duration(seconds: 2) && pos < total - const Duration(seconds: 2)) {
      _lastSavedAt = DateTime.now();
      await _positions.set(t.id, pos.inSeconds);
    }
  }

  Track? get current => _current;
  bool get playing => _player.playing;
  double get speed => _speed;

  /// Fraction 0..1 — based on actual loaded duration when available, otherwise
  /// the metadata duration from the Track. A finished track stays at 1.0 until
  /// the user hits play again, at which point [play] seeks back to zero.
  double get progress {
    if (_player.processingState == ProcessingState.completed) return 1.0;
    final pos = _player.position.inMilliseconds;
    final total = (_player.duration ?? Duration(seconds: _current?.duration ?? 0)).inMilliseconds;
    if (total == 0) return 0;
    return (pos / total).clamp(0.0, 1.0);
  }

  Duration get position => _player.position;
  Duration get duration =>
      _player.duration ?? Duration(seconds: _current?.duration ?? 0);

  /// Load a track but don't auto-play. If [andPlay] is true, plays immediately.
  /// Resumes from the last persisted position if one exists.
  Future<void> load(Track t, {bool andPlay = false}) async {
    // Persist the previous track's position before switching off it.
    await _saveNow();
    _current = t;
    _latestPosition = Duration.zero;
    _ready = false;
    final path = t.filePath;
    if (path == null) {
      _onChanged();
      return;
    }
    try {
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
      if (saved != null && saved > 0) {
        final total = _player.duration ?? Duration(seconds: t.duration);
        final target = Duration(seconds: saved);
        if (target < total - const Duration(seconds: 1)) {
          await _player.seek(target);
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
    }
    await _player.play();
  }

  Future<void> pause() async => _player.pause();

  Future<void> toggle() async => playing ? pause() : play();

  Future<void> seekFraction(double f) async {
    final total = duration.inMilliseconds;
    if (total == 0) return;
    await _player.seek(Duration(milliseconds: (f.clamp(0.0, 1.0) * total).round()));
  }

  Future<void> seekRelative(Duration delta) async {
    final next = _player.position + delta;
    final clamped = next.isNegative ? Duration.zero : (next > duration ? duration : next);
    await _player.seek(clamped);
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
