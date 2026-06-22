import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/state/audio_controller.dart';

void main() {
  group('AudioController.effectivePosition', () {
    test('while playing, reports the live player position', () {
      final pos = AudioController.effectivePosition(
        playing: true,
        playerPosition: const Duration(seconds: 42),
        latestPosition: const Duration(seconds: 10),
      );
      expect(pos, const Duration(seconds: 42));
    });

    // The regression: pausing from the media-session notification while the app
    // is backgrounded leaves `_player.position` stale on Android (it falls back
    // to the last broadcast updatePosition, ≈ play start). The controller must
    // report the last position seen while playing instead, so the now-playing
    // waveform stays at the real pause point.
    test('while paused, ignores the stale player position and reports the last '
        'known playing position', () {
      final pos = AudioController.effectivePosition(
        playing: false,
        playerPosition: const Duration(seconds: 3), // stale ≈ play start
        latestPosition: const Duration(seconds: 95), // real pause point
      );
      expect(pos, const Duration(seconds: 95));
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
