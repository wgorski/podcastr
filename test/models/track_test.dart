import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/models/track.dart';

void main() {
  group('Track', () {
    const sample = Track(
      id: 'abc123',
      title: 'Hello world',
      channel: 'Some Channel',
      duration: 3725,
      size: '12.3 MB',
      addedAt: 'Today',
      color1: Color(0xFFAABBCC),
      color2: Color(0xFF112233),
      filePath: '/tmp/abc123.m4a',
      thumbnailPath: '/tmp/abc123.jpg',
    );

    test('toJson/fromJson round-trips all fields', () {
      final json = sample.toJson();
      final restored = Track.fromJson(json);

      expect(restored.id, sample.id);
      expect(restored.title, sample.title);
      expect(restored.channel, sample.channel);
      expect(restored.duration, sample.duration);
      expect(restored.size, sample.size);
      expect(restored.addedAt, sample.addedAt);
      expect(restored.color1.toARGB32(), sample.color1.toARGB32());
      expect(restored.color2.toARGB32(), sample.color2.toARGB32());
      expect(restored.filePath, sample.filePath);
      expect(restored.thumbnailPath, sample.thumbnailPath);
    });

    test('fromJson tolerates null filePath and thumbnailPath', () {
      final json = sample.toJson()
        ..['filePath'] = null
        ..['thumbnailPath'] = null;
      final restored = Track.fromJson(json);
      expect(restored.filePath, isNull);
      expect(restored.thumbnailPath, isNull);
    });

    test('copyWith only overrides explicit fields', () {
      final updated = sample.copyWith(size: '99 MB', filePath: '/new/path.m4a');
      expect(updated.size, '99 MB');
      expect(updated.filePath, '/new/path.m4a');
      // Untouched fields preserved.
      expect(updated.id, sample.id);
      expect(updated.title, sample.title);
      expect(updated.channel, sample.channel);
      expect(updated.duration, sample.duration);
      expect(updated.thumbnailPath, sample.thumbnailPath);
    });

    test('copyWith returns identical content when no args passed', () {
      final twin = sample.copyWith();
      expect(twin.toJson(), sample.toJson());
    });

    test('seed is deterministic and based on first*last char', () {
      // 'a'=97, 'c'=99 → 97*99 = 9603
      const t = Track(
        id: 'abc',
        title: '',
        channel: '',
        duration: 0,
        size: '',
        addedAt: '',
        color1: Color(0xFF000000),
        color2: Color(0xFF000000),
      );
      expect(t.seed, 97 * 99);
    });

    test('seed handles single-char id (first == last)', () {
      const t = Track(
        id: 'a',
        title: '',
        channel: '',
        duration: 0,
        size: '',
        addedAt: '',
        color1: Color(0xFF000000),
        color2: Color(0xFF000000),
      );
      expect(t.seed, 97 * 97);
    });

    test('seed uses fallback when id is empty', () {
      const t = Track(
        id: '',
        title: '',
        channel: '',
        duration: 0,
        size: '',
        addedAt: '',
        color1: Color(0xFF000000),
        color2: Color(0xFF000000),
      );
      // 'x' = 120
      expect(t.seed, 120 * 120);
    });
  });

  group('paletteForId', () {
    test('is deterministic for the same id', () {
      final a = paletteForId('dQw4w9WgXcQ');
      final b = paletteForId('dQw4w9WgXcQ');
      expect(a.c1.toARGB32(), b.c1.toARGB32());
      expect(a.c2.toARGB32(), b.c2.toARGB32());
    });

    test('returns colors from the documented palette set', () {
      const validColors = {
        0xFFF0A868, 0xFFC9622E,
        0xFF6AB7FF, 0xFF2D6BB8,
        0xFFB794FF, 0xFF7558C4,
        0xFFFF6B5B, 0xFFC4382B,
        0xFF5EE3D4, 0xFF2A9D8F,
        0xFFF5D96C, 0xFFB89934,
        0xFFFF8DB2, 0xFFC25288,
      };
      for (final id in ['a', 'video1', 'somethingelse', 'XYZ', 'dQw4w9WgXcQ']) {
        final p = paletteForId(id);
        expect(validColors, contains(p.c1.toARGB32()));
        expect(validColors, contains(p.c2.toARGB32()));
      }
    });
  });

  group('formatDuration', () {
    test('seconds-only formats as 0:SS', () {
      expect(formatDuration(7), '0:07');
      expect(formatDuration(59), '0:59');
    });

    test('minutes:SS without hours', () {
      expect(formatDuration(65), '1:05');
      expect(formatDuration(125), '2:05');
      expect(formatDuration(3599), '59:59');
    });

    test('hours:MM:SS once an hour is reached', () {
      expect(formatDuration(3600), '1:00:00');
      expect(formatDuration(3725), '1:02:05');
      expect(formatDuration(7322), '2:02:02');
    });

    test('zero', () {
      expect(formatDuration(0), '0:00');
    });
  });

  group('formatShort', () {
    test('minutes-only when under an hour', () {
      expect(formatShort(0), '0 min');
      expect(formatShort(59), '0 min');
      expect(formatShort(60), '1 min');
      expect(formatShort(900), '15 min');
    });

    test('hours+minutes once an hour reached', () {
      expect(formatShort(3600), '1h 0m');
      expect(formatShort(3661), '1h 1m');
      expect(formatShort(7320), '2h 2m');
    });
  });

  group('waveformBars', () {
    test('default count returns 64 bars', () {
      expect(waveformBars('seed').length, 64);
    });

    test('explicit count is honored', () {
      expect(waveformBars('seed', count: 16).length, 16);
      expect(waveformBars('seed', count: 1).length, 1);
    });

    test('values are clamped to [0.08, 1.0]', () {
      final bars = waveformBars('whatever', count: 128);
      for (final v in bars) {
        expect(v, greaterThanOrEqualTo(0.08));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });

    test('deterministic for the same seed', () {
      final a = waveformBars('abc');
      final b = waveformBars('abc');
      expect(a, b);
    });

    test('different seeds produce different bars', () {
      final a = waveformBars('one');
      final b = waveformBars('two');
      expect(a, isNot(equals(b)));
    });
  });
}
