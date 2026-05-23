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

  Track? _current;
  double _speed = 1.0;
  bool _ready = false;
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  late final StreamSubscription _posSub;
  late final StreamSubscription _stateSub;

  AudioController({required void Function() onChanged}) : _onChanged = onChanged {
    _posSub = _player.positionStream.listen((_) {
      _onChanged();
      _maybeSavePosition();
    });
    _stateSub = _player.playerStateStream.listen((s) {
      // When the file finishes, reset position + drop the saved resume point.
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        final t = _current;
        if (t != null) _positions.remove(t.id);
      } else if (!s.playing) {
        _saveNow();
      }
      _onChanged();
    });
  }

  /// Drop the saved resume point for a track (used when the track is deleted).
  Future<void> forget(String id) => _positions.remove(id);

  void _maybeSavePosition() {
    final now = DateTime.now();
    if (now.difference(_lastSavedAt) < const Duration(seconds: 5)) return;
    _saveNow();
  }

  void _saveNow() {
    final t = _current;
    if (t == null) return;
    final pos = _player.position;
    final total = _player.duration ?? Duration(seconds: t.duration);
    // Don't save the trivial endpoints: 0 means "fresh", end means "done".
    if (pos > const Duration(seconds: 2) && pos < total - const Duration(seconds: 2)) {
      _positions.set(t.id, pos.inSeconds);
      _lastSavedAt = DateTime.now();
    }
  }

  Track? get current => _current;
  bool get playing => _player.playing;
  double get speed => _speed;

  /// Fraction 0..1 — based on actual loaded duration when available, otherwise
  /// the metadata duration from the Track.
  double get progress {
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
    _saveNow();
    _current = t;
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
    _ready = false;
    _onChanged();
  }

  Future<void> dispose() async {
    _saveNow();
    await _posSub.cancel();
    await _stateSub.cancel();
    await _player.dispose();
  }
}
