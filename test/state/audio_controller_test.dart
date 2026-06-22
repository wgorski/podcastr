import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:podcastr/state/audio_controller.dart';

void main() {
  group('AudioController.frozenPositionAtPause', () {
    // The regression: on a real device with the screen off, Android throttles
    // Flutter's Dart timer so positionStream ticks arrive seconds apart while
    // local-file audio keeps playing. Freezing to the last (stale) tick would
    // resume several seconds behind. Extrapolating the last tick forward by the
    // elapsed wall time recovers the true stop position.
    test('extrapolates a stale tick forward by the elapsed wall time', () {
      final p = AudioController.frozenPositionAtPause(
        lastTick: const Duration(seconds: 1158), // 19:18, last sparse tick
        sinceLastTick: const Duration(seconds: 7), // ticks were 7s apart
        speed: 1.0,
        total: const Duration(seconds: 1187),
      );
      expect(p, const Duration(seconds: 1165)); // 19:25, where audio really was
    });

    test('scales the extrapolation by playback speed', () {
      final p = AudioController.frozenPositionAtPause(
        lastTick: const Duration(seconds: 100),
        sinceLastTick: const Duration(seconds: 8),
        speed: 1.5,
        total: const Duration(seconds: 600),
      );
      expect(p, const Duration(seconds: 112)); // 100 + 8*1.5
    });

    test('clamps to total so it never overshoots past the end', () {
      final p = AudioController.frozenPositionAtPause(
        lastTick: const Duration(seconds: 595),
        sinceLastTick: const Duration(seconds: 30),
        speed: 1.0,
        total: const Duration(seconds: 600),
      );
      expect(p, const Duration(seconds: 600));
    });

    test('caps the extrapolation so a stale anchor cannot reach the end', () {
      final p = AudioController.frozenPositionAtPause(
        lastTick: const Duration(seconds: 100),
        sinceLastTick: const Duration(minutes: 14), // pathological stale anchor
        speed: 1.0,
        total: const Duration(seconds: 1187),
        maxExtrapolation: const Duration(minutes: 2),
      );
      expect(p, const Duration(seconds: 220)); // 100 + 120, not fast-forwarded to the end
    });

    test('fresh tick (sub-second gap) is effectively unchanged', () {
      final p = AudioController.frozenPositionAtPause(
        lastTick: const Duration(milliseconds: 42000),
        sinceLastTick: const Duration(milliseconds: 200),
        speed: 1.0,
        total: const Duration(seconds: 600),
      );
      expect(p, const Duration(milliseconds: 42200));
    });
  });

  group('AudioController.playerTornDown', () {
    // A media-session / Bluetooth *stop* (or notification dismissal) routes
    // through just_audio_background.stop(), which disposes the platform player
    // and drops the state to idle. The controller must treat that as "no longer
    // ready" so the next play() re-loads from the saved resume point instead of
    // resuming on a torn-down player that reports position ~0 — the bug where
    // the waveform snaps to 0:00 while audio plays from the right spot.
    test('idle while a track is current signals a teardown', () {
      expect(
        AudioController.playerTornDown(ProcessingState.idle, hasCurrent: true),
        isTrue,
      );
    });

    test('idle with no current track is our own stop(), not a teardown', () {
      expect(
        AudioController.playerTornDown(ProcessingState.idle, hasCurrent: false),
        isFalse,
      );
    });

    test('non-idle states are never a teardown', () {
      for (final s in [
        ProcessingState.loading,
        ProcessingState.buffering,
        ProcessingState.ready,
        ProcessingState.completed,
      ]) {
        expect(
          AudioController.playerTornDown(s, hasCurrent: true),
          isFalse,
          reason: '$s should not count as a teardown',
        );
      }
    });
  });

  group('AudioController.livePosition', () {
    test('while paused, reports the frozen anchor (ignores elapsed wall time)', () {
      final pos = AudioController.livePosition(
        playing: false,
        latestPosition: const Duration(seconds: 95), // real pause point
        sinceAnchor: const Duration(seconds: 30), // would matter only if playing
        speed: 1.0,
        total: const Duration(seconds: 600),
      );
      expect(pos, const Duration(seconds: 95));
    });

    test('while playing, extrapolates the anchor forward by wall time', () {
      final pos = AudioController.livePosition(
        playing: true,
        latestPosition: const Duration(seconds: 40),
        sinceAnchor: const Duration(seconds: 2),
        speed: 1.0,
        total: const Duration(seconds: 600),
      );
      expect(pos, const Duration(seconds: 42));
    });

    test('while playing, scales the extrapolation by speed', () {
      final pos = AudioController.livePosition(
        playing: true,
        latestPosition: const Duration(seconds: 100),
        sinceAnchor: const Duration(seconds: 4),
        speed: 1.5,
        total: const Duration(seconds: 600),
      );
      expect(pos, const Duration(seconds: 106));
    });

    test('clamps to total', () {
      final pos = AudioController.livePosition(
        playing: true,
        latestPosition: const Duration(seconds: 598),
        sinceAnchor: const Duration(seconds: 10),
        speed: 1.0,
        total: const Duration(seconds: 600),
      );
      expect(pos, const Duration(seconds: 600));
    });
  });

  group('AudioController.isForwardTick', () {
    // The regression: resuming from pause, just_audio briefly reports the old
    // play-start position (here ~5s behind where we know we are). That backward
    // jump must be rejected so the displayed time doesn't dip.
    test('rejects a stale backward tick after resume', () {
      expect(
        AudioController.isForwardTick(
          tickPosition: const Duration(seconds: 593), // stale play-start
          extrapolated: const Duration(seconds: 598), // where we really are
        ),
        isFalse,
      );
    });

    test('accepts normal forward progress', () {
      expect(
        AudioController.isForwardTick(
          tickPosition: const Duration(milliseconds: 598200),
          extrapolated: const Duration(milliseconds: 598000),
        ),
        isTrue,
      );
    });

    test('accepts a tick within tolerance (jitter) so steady play re-anchors', () {
      expect(
        AudioController.isForwardTick(
          tickPosition: const Duration(milliseconds: 41800),
          extrapolated: const Duration(milliseconds: 42000),
        ),
        isTrue,
      );
    });
  });

  group('AudioController.progressFraction', () {
    test('is the position/total ratio mid-track', () {
      final f = AudioController.progressFraction(
        position: const Duration(seconds: 30),
        total: const Duration(seconds: 120),
        completed: false,
      );
      expect(f, closeTo(0.25, 1e-9));
    });

    test('is 1.0 when completed regardless of position', () {
      final f = AudioController.progressFraction(
        position: Duration.zero,
        total: const Duration(seconds: 120),
        completed: true,
      );
      expect(f, 1.0);
    });

    test('is 0 when total duration is unknown', () {
      final f = AudioController.progressFraction(
        position: const Duration(seconds: 30),
        total: Duration.zero,
        completed: false,
      );
      expect(f, 0);
    });

    test('clamps to 1.0 when position overshoots total', () {
      final f = AudioController.progressFraction(
        position: const Duration(seconds: 130),
        total: const Duration(seconds: 120),
        completed: false,
      );
      expect(f, 1.0);
    });
  });
}
