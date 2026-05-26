import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/services/elevenlabs_tts.dart';

void main() {
  group('ElevenLabsTts.chunkText', () {
    test('returns a single chunk when the text is under the limit', () {
      final out = ElevenLabsTts.chunkText('Hello world.', 100);
      expect(out, ['Hello world.']);
    });

    test('returns a single chunk exactly at the limit', () {
      final text = 'a' * 100;
      final out = ElevenLabsTts.chunkText(text, 100);
      expect(out.length, 1);
      expect(out.first.length, 100);
    });

    test('splits at paragraph boundaries when possible', () {
      final a = 'A' * 1500; // one paragraph of 1500 chars
      final b = 'B' * 1500;
      final c = 'C' * 1500;
      // Three paragraphs joined by blank lines, limit 2000.
      final text = '$a\n\n$b\n\n$c';
      final chunks = ElevenLabsTts.chunkText(text, 2000);
      expect(chunks.length, greaterThanOrEqualTo(2));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(2000));
      }
    });

    test(
        'splits a single overlong paragraph at sentence boundaries '
        'when no paragraph break is available', () {
      // One paragraph with several sentences, total > limit.
      final sentence = 'The fox jumps over the lazy dog. ';
      final text = sentence * 40; // 33 * 40 = ~1320 chars
      final chunks = ElevenLabsTts.chunkText(text, 300);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(300));
      }
      // No chunk should split a sentence mid-word.
      for (final chunk in chunks) {
        expect(chunk.trim().endsWith('.'), isTrue,
            reason: 'Chunk should end at a sentence boundary: "$chunk"');
      }
    });

    test('preserves the visible word content across all chunks', () {
      final text = List.generate(
              200, (i) => 'Paragraph $i sits on its own line and ends here.')
          .join('\n\n');
      final chunks = ElevenLabsTts.chunkText(text, 500);

      // Every chunk respects the limit.
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(500));
      }

      // Every paragraph survives at least once in the joined output.
      final joined = chunks.join('\n\n');
      for (var i = 0; i < 200; i++) {
        expect(joined, contains('Paragraph $i sits on its own line'));
      }
    });

    test('hard-slices a single sentence longer than the limit', () {
      // A single "sentence" with no terminator and no whitespace — the
      // packer can't find a clean boundary, so it falls back to slicing.
      final text = 'x' * 5000;
      final chunks = ElevenLabsTts.chunkText(text, 1000);
      expect(chunks.length, 5);
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(1000));
      }
    });

    test('packs short paragraphs together up to the limit', () {
      final paragraphs =
          List.generate(20, (i) => 'Para $i is short.').join('\n\n');
      final chunks = ElevenLabsTts.chunkText(paragraphs, 200);
      // 20 short paragraphs (~16 chars each + "\n\n" separators) should
      // comfortably pack into a small number of chunks, not 20.
      expect(chunks.length, lessThan(5));
    });
  });
}
