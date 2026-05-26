import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/services/article_extractor.dart';
import 'package:podcastr/services/jina_reader.dart';
import 'package:podcastr/services/readability_extractor.dart';

ExtractedArticle _article(String url, {String title = 'Title'}) {
  return ExtractedArticle(
    id: ExtractedArticle.idFromUrl(url),
    sourceUrl: url,
    title: title,
    byline: 'Byline',
    text:
        'A reasonably long paragraph of text that more than covers the minimum '
        'word count expected by downstream code paths.',
    wordCount: 24,
    thumbnailUrl: null,
  );
}

class _StubJina extends JinaReader {
  final Future<ExtractedArticle> Function(String url) handler;
  int calls = 0;
  _StubJina(this.handler) : super();

  @override
  Future<ExtractedArticle> extract(String url) async {
    calls++;
    return handler(url);
  }

  @override
  void dispose() {/* no-op */}
}

class _StubReadability extends ReadabilityExtractor {
  final Future<ExtractedArticle> Function(String url) handler;
  int calls = 0;
  _StubReadability(this.handler) : super();

  @override
  Future<ExtractedArticle> extract(String url) async {
    calls++;
    return handler(url);
  }
}

void main() {
  group('ArticleExtractor', () {
    test('rejects an obviously invalid URL before calling extractors', () async {
      final jina = _StubJina((_) async => _article('x'));
      final ready = _StubReadability((_) async => _article('x'));
      final extractor = ArticleExtractor(jina: jina, readability: ready);

      await expectLater(
        extractor.extract('not a url'),
        throwsA(isA<ArticleException>()),
      );
      expect(jina.calls, 0);
      expect(ready.calls, 0);
    });

    test('returns the Jina result and never calls the fallback when Jina works',
        () async {
      const url = 'https://example.com/post';
      final jina = _StubJina((u) async => _article(u));
      final ready =
          _StubReadability((u) async => fail('Readability should not run'));
      final extractor = ArticleExtractor(jina: jina, readability: ready);

      final out = await extractor.extract(url);
      expect(out.sourceUrl, url);
      expect(out.usedFallback, isFalse);
      expect(out.fallbackReason, isNull);
      expect(jina.calls, 1);
      expect(ready.calls, 0);
    });

    test(
        'falls back to Readability when Jina fails, '
        'and tags the result with the reason',
        () async {
      const url = 'https://example.com/post';
      final jina = _StubJina(
          (_) async => throw const JinaException('Jina Reader timed out.'));
      final ready = _StubReadability((u) async => _article(u, title: 'From R'));
      final extractor = ArticleExtractor(jina: jina, readability: ready);

      final out = await extractor.extract(url);
      expect(out.usedFallback, isTrue);
      expect(out.fallbackReason, 'Jina Reader timed out.');
      expect(out.title, 'From R');
      expect(jina.calls, 1);
      expect(ready.calls, 1);
    });

    test('throws ArticleException when both Jina and Readability fail',
        () async {
      const url = 'https://example.com/post';
      final jina = _StubJina(
          (_) async => throw const JinaException('Jina dead'));
      final ready = _StubReadability(
          (_) async => throw const ReadabilityException('No DOM'));
      final extractor = ArticleExtractor(jina: jina, readability: ready);

      await expectLater(
        extractor.extract(url),
        throwsA(isA<ArticleException>()
            .having((e) => e.toString(), 'message',
                allOf(contains('Jina dead'), contains('No DOM')))),
      );
      expect(jina.calls, 1);
      expect(ready.calls, 1);
    });

    test('does NOT fall back when Jina throws a generic non-Jina error',
        () async {
      // Bug guard: if the JinaReader itself blows up with something we
      // didn't anticipate, we want the error to surface — not silently
      // burn a slow Readability attempt that may also fail.
      const url = 'https://example.com/post';
      final jina = _StubJina((_) async => throw StateError('boom'));
      final ready = _StubReadability(
          (_) async => fail('Readability must not run on non-Jina errors'));
      final extractor = ArticleExtractor(jina: jina, readability: ready);

      await expectLater(extractor.extract(url), throwsA(isA<StateError>()));
      expect(ready.calls, 0);
    });

    group('ExtractionMode.localOnly', () {
      test('skips Jina and calls Readability directly', () async {
        const url = 'https://example.com/post';
        final jina = _StubJina((_) async => fail('Jina must not be called'));
        final ready = _StubReadability((u) async => _article(u));
        final extractor = ArticleExtractor(jina: jina, readability: ready);

        final out =
            await extractor.extract(url, mode: ExtractionMode.localOnly);
        expect(jina.calls, 0);
        expect(ready.calls, 1);
        // Local-only is a user preference, not a fallback — no banner.
        expect(out.usedFallback, isFalse);
        expect(out.fallbackReason, isNull);
      });

      test('surfaces a Readability failure as ArticleException, no Jina retry',
          () async {
        const url = 'https://example.com/post';
        final jina = _StubJina((_) async => fail('Jina must not be called'));
        final ready = _StubReadability(
            (_) async => throw const ReadabilityException('No DOM'));
        final extractor = ArticleExtractor(jina: jina, readability: ready);

        await expectLater(
          extractor.extract(url, mode: ExtractionMode.localOnly),
          throwsA(isA<ArticleException>()
              .having((e) => e.toString(), 'message', contains('No DOM'))),
        );
        expect(jina.calls, 0);
      });

      test('respects the constructor default mode when no override is passed',
          () async {
        const url = 'https://example.com/post';
        final jina = _StubJina((_) async => fail('Jina must not be called'));
        final ready = _StubReadability((u) async => _article(u));
        final extractor = ArticleExtractor(
          jina: jina,
          readability: ready,
          defaultMode: ExtractionMode.localOnly,
        );

        await extractor.extract(url);
        expect(jina.calls, 0);
        expect(ready.calls, 1);
      });

      test('per-call mode overrides the constructor default', () async {
        const url = 'https://example.com/post';
        final jina = _StubJina((u) async => _article(u));
        final ready = _StubReadability(
            (_) async => fail('Readability must not be called'));
        final extractor = ArticleExtractor(
          jina: jina,
          readability: ready,
          defaultMode: ExtractionMode.localOnly,
        );

        await extractor.extract(url,
            mode: ExtractionMode.jinaWithLocalFallback);
        expect(jina.calls, 1);
        expect(ready.calls, 0);
      });
    });
  });

  group('ExtractedArticle', () {
    test('idFromUrl is deterministic and prefixed', () {
      const url = 'https://example.com/article/123';
      expect(ExtractedArticle.idFromUrl(url),
          ExtractedArticle.idFromUrl(url));
      expect(ExtractedArticle.idFromUrl(url), startsWith('art-'));
      expect(ExtractedArticle.idFromUrl(url).length, 'art-'.length + 8);
    });

    test('idFromUrl differs across distinct URLs', () {
      expect(
        ExtractedArticle.idFromUrl('https://example.com/a'),
        isNot(ExtractedArticle.idFromUrl('https://example.com/b')),
      );
    });

    test('countWords handles empty / single / multi-word strings', () {
      expect(ExtractedArticle.countWords(''), 0);
      expect(ExtractedArticle.countWords('   '), 0);
      expect(ExtractedArticle.countWords('hello'), 1);
      expect(ExtractedArticle.countWords('hello world'), 2);
      expect(ExtractedArticle.countWords('  a  b   c\n d\t e '), 5);
    });

    test('estimatedDurationSeconds matches ~150 wpm', () {
      final a = ExtractedArticle(
        id: 'art-x',
        sourceUrl: 'u',
        title: '',
        byline: '',
        text: '',
        wordCount: 150,
        thumbnailUrl: null,
      );
      expect(a.estimatedDurationSeconds, 60);
    });

    test('copyWith flips the fallback flags without touching content', () {
      final base = _article('https://example.com/a');
      final tagged = base.copyWith(
        usedFallback: true,
        fallbackReason: 'because',
      );
      expect(tagged.usedFallback, isTrue);
      expect(tagged.fallbackReason, 'because');
      expect(tagged.title, base.title);
      expect(tagged.text, base.text);
      expect(tagged.id, base.id);
    });
  });
}
