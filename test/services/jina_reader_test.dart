import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/services/jina_reader.dart';

void main() {
  group('JinaReader.stripMarkdownSyntax', () {
    test('drops link syntax but keeps the visible text', () {
      expect(JinaReader.stripMarkdownSyntax('Click [here](https://x.com).'),
          'Click here.');
    });

    test('drops image syntax entirely', () {
      expect(
        JinaReader.stripMarkdownSyntax('Before ![alt](x.png) after.'),
        'Before  after.',
      );
    });

    test('drops ATX heading markers but keeps the text', () {
      expect(JinaReader.stripMarkdownSyntax('## Hello'), 'Hello');
    });

    test('drops emphasis markers around words', () {
      expect(JinaReader.stripMarkdownSyntax('**bold** _italic_ ~~strike~~'),
          'bold italic strike');
    });

    test('drops list bullets', () {
      const md = '*   Apples\n*   Bananas\n*   Cherries';
      final out = JinaReader.stripMarkdownSyntax(md);
      expect(out, 'Apples\nBananas\nCherries');
    });

    test('drops fenced code blocks', () {
      const md = 'Before\n```\nint main() {}\n```\nAfter';
      final out = JinaReader.stripMarkdownSyntax(md);
      expect(out.contains('int main'), isFalse);
      expect(out.contains('Before'), isTrue);
      expect(out.contains('After'), isTrue);
    });

    test('drops blockquote markers', () {
      expect(JinaReader.stripMarkdownSyntax('> quoted text'), 'quoted text');
    });

    test('drops horizontal rules', () {
      const md = 'A\n\n* * *\n\nB';
      final out = JinaReader.stripMarkdownSyntax(md);
      expect(out.contains('* * *'), isFalse);
      expect(out.contains('A'), isTrue);
      expect(out.contains('B'), isTrue);
    });

    test('drops inline code backticks but keeps the code text', () {
      expect(JinaReader.stripMarkdownSyntax('Run `flutter pub get`.'),
          'Run flutter pub get.');
    });
  });

  group('JinaReader.extractArticleText', () {
    test('on the BBC Jina sample, picks only the article body', () {
      final md =
          File('test/fixtures/jina_bbc_iran.md').readAsStringSync();
      final out = JinaReader.extractArticleText(md);

      // Article body sentences are present.
      expect(out, contains('launched new strikes on southern Iran'));
      expect(out, contains('self-defense'));
      expect(out, contains('US Central Command'));
      expect(out, contains('continues to defend our forces'));
      expect(out, contains('is not imminent'));

      // Site chrome is gone.
      expect(out, isNot(contains('Sign In')));
      expect(out, isNot(contains('Subscribe')));
      expect(out, isNot(contains('Watch Live')));
      expect(out, isNot(contains('Copyright')));
      expect(out, isNot(contains('Skip to content')));
      expect(out, isNot(contains('BBC in other languages')));
      expect(out, isNot(contains('Terms of Use')));
      expect(out, isNot(contains('Privacy Policy')));

      // Nav menu items don't bleed into the prose run.
      expect(out, isNot(contains('Documentaries')));
      expect(out, isNot(contains('Newsletters')));

      // Related-article teaser bodies are kept out — they each sit alone
      // between non-prose blocks, so the article's six-paragraph run wins.
      expect(out, isNot(contains("Mexico's President Claudia Sheinbaum")));
      expect(out,
          isNot(contains('I survived a missile strike in the Strait of Hormuz')));

      // Sanity: most of the result should be the article body, not cruft.
      // The article body itself is ~800 chars across six paragraphs.
      expect(out.length, greaterThan(500));
      expect(out.length, lessThan(1500));
    });

    test('keeps the prose run across a single non-prose interruption', () {
      // Mimics a Wikipedia-style article: two prose paragraphs broken up
      // by a short section heading. The heading is short enough to be
      // non-prose, but the 1-block gap tolerance should bridge them.
      const md = '''
Some site header

Home News About Contact

# The Article Title

The first paragraph is a real piece of prose that runs across several clauses, contains a period at the end, and is long enough to clear the heuristic length and word-count thresholds without any difficulty.

## A Section Heading

The second paragraph also runs across multiple clauses and ends with proper punctuation, mirroring the first paragraph in length and shape so that the prose-detection heuristic recognises it.

Site footer
''';
      final out = JinaReader.extractArticleText(md);
      expect(out, contains('first paragraph'));
      expect(out, contains('second paragraph'));
      expect(out, isNot(contains('Home News')));
      expect(out, isNot(contains('Site footer')));
    });

    test('returns empty string when no paragraph qualifies as prose', () {
      const md = '''
[Home](/)
[News](/news)
[Sport](/sport)

Advertisement

* * *

Copyright
''';
      expect(JinaReader.extractArticleText(md), isEmpty);
    });

    test('returns the body unchanged when the input is already clean prose',
        () {
      const md =
          'The quick brown fox jumps over the lazy dog. The same fox repeats this gesture for emphasis and clarity, demonstrating its prose-shaped nature to the reader.\n\nA second paragraph follows. It too is sufficiently long, contains a period at the end, and is composed of normal prose.';
      final out = JinaReader.extractArticleText(md);
      expect(out, contains('The quick brown fox'));
      expect(out, contains('second paragraph'));
    });
  });
}
