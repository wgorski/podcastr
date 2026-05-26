import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'article_extractor.dart';

/// Thrown when Jina Reader can't return a usable article for the URL.
/// [ArticleExtractor] catches this and falls back to the on-device
/// Readability.js path.
class JinaException implements Exception {
  final String message;
  const JinaException(this.message);
  @override
  String toString() => message;
}

/// Thin client for the Jina Reader API (`r.jina.ai`).
///
/// We hit `GET https://r.jina.ai/<URL>` with `Accept: application/json` and
/// pull `title`, `description`, `url`, and the markdown `content` out of
/// the structured response. The markdown body is then stripped to plain
/// text before being handed to the TTS engine.
class JinaReader {
  static const _endpoint = 'https://r.jina.ai/';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  JinaReader({http.Client? client}) : _client = client ?? http.Client();

  Future<ExtractedArticle> extract(String url) async {
    final uri = Uri.parse('$_endpoint$url');
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: const {
            'Accept': 'application/json',
            'User-Agent': _userAgent,
            // Skip the image-captioning pass — we don't use it and it
            // slows the response down noticeably.
            'X-Retain-Images': 'none',
            // Drop the obvious site chrome before Jina renders to
            // markdown. We still post-process below because these
            // selectors don't catch every CMS' boilerplate.
            'X-Remove-Selector':
                'nav, header, footer, aside, form, [role="navigation"], '
                    '[role="banner"], [role="contentinfo"], '
                    '[role="complementary"], .nav, .navigation, .menu, '
                    '.sidebar, .footer, .related, .ads, .ad, .advert, '
                    '.advertisement',
          })
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const JinaException('Jina Reader timed out.');
    } catch (e) {
      throw JinaException('Jina Reader unreachable: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw JinaException('Jina Reader returned HTTP ${res.statusCode}.');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw JinaException('Jina Reader returned a malformed response.');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const JinaException('Jina Reader returned no article data.');
    }

    final markdown = (data['content'] as String?)?.trim() ?? '';
    if (markdown.isEmpty) {
      throw const JinaException('Jina Reader extracted no content.');
    }
    final text = extractArticleText(markdown);
    // News articles in our target band sit comfortably > 250 chars after
    // boilerplate stripping. If we're under that, Jina's heuristics most
    // likely got nav menus + a teaser; let Readability.js have a try.
    if (text.length < 250) {
      throw const JinaException('Jina Reader returned too little prose.');
    }

    final canonical = (data['url'] as String?)?.trim();
    final title = (data['title'] as String?)?.trim() ?? '';
    final description = (data['description'] as String?)?.trim() ?? '';
    final host = _hostOf(canonical?.isNotEmpty == true ? canonical! : url);

    return ExtractedArticle(
      id: ExtractedArticle.idFromUrl(url),
      sourceUrl: url,
      title: title.isNotEmpty ? title : host,
      byline: description.isNotEmpty ? description : host,
      text: text,
      wordCount: ExtractedArticle.countWords(text),
      thumbnailUrl: _firstImageFromMarkdown(markdown),
    );
  }

  void dispose() => _client.close();

  static String _hostOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    return u.host.replaceFirst('www.', '');
  }

  static String? _firstImageFromMarkdown(String md) {
    final m = RegExp(r'!\[[^\]]*\]\(([^)]+)\)').firstMatch(md);
    return m?.group(1);
  }

  /// Public so tests can exercise it against fixture markdown. Strips
  /// markdown syntax to plain text and then keeps only the longest
  /// contiguous run of prose paragraphs — a tight heuristic against the
  /// nav / footer / "related articles" cruft that Jina sometimes leaves
  /// inside the markdown body.
  static String extractArticleText(String markdown) {
    final stripped = stripMarkdownSyntax(markdown);
    return _longestProseRun(stripped);
  }

  /// Best-effort Markdown → plain text. The ElevenLabs voice handles
  /// regular prose well; we just need to strip syntactic noise that would
  /// otherwise be read aloud as "asterisk asterisk" / "open bracket".
  static String stripMarkdownSyntax(String md) {
    var s = md;
    // Fenced code blocks
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    // Indented code blocks (4+ leading spaces on every line of a run)
    s = s.replaceAll(RegExp(r'(?:^|\n)(?: {4,}[^\n]*\n?)+'), '\n');
    // Dart's replaceAll(RegExp, replacement) treats $1 as a literal — only
    // replaceAllMapped expands backreferences. The whole point of these
    // substitutions is to keep the visible text and drop the syntax, so we
    // have to use replaceAllMapped.
    // Inline code
    s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
    // Images
    s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    // Links [text](url) → text
    s = s.replaceAllMapped(RegExp(r'\[([^\]]*)\]\(([^)]*)\)'), (m) => m[1]!);
    // Reference-style links / image refs
    s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\[[^\]]*\]'), (m) => m[1]!);
    // Setext + ATX headings — drop the markers, keep the text
    s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^(=+|-+)\s*$', multiLine: true), '');
    // Bold / italic / strike
    s = s.replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m[2]!);
    s = s.replaceAllMapped(
        RegExp(r'(?<!\w)([*_])(.+?)\1(?!\w)'), (m) => m[2]!);
    s = s.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m[1]!);
    // Blockquotes
    s = s.replaceAll(RegExp(r'^>\s?', multiLine: true), '');
    // List bullets / numbering
    s = s.replaceAll(RegExp(r'^\s*[\*\-\+]\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
    // Tables — drop the alignment row and pipe characters
    s = s.replaceAll(RegExp(r'^\s*\|?[\s\-:|]+\|?\s*$', multiLine: true), '');
    s = s.replaceAll(RegExp(r'\s*\|\s*'), ' ');
    // Horizontal rules: ***, ---, ___ — also with spaces between the
    // chars like the BBC site's "* * *" separators.
    s = s.replaceAll(
        RegExp(r'^\s*(?:[-*_]\s*){3,}$', multiLine: true), '');
    // Collapse runs of blank lines
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // Trim trailing whitespace on each line
    s = s.split('\n').map((l) => l.trimRight()).join('\n');
    return s.trim();
  }

  /// Find the longest contiguous run of "prose-shaped" paragraphs in
  /// [stripped] and return them joined back together. Allows up to one
  /// non-prose paragraph (a section heading, an image caption) inside a
  /// run so longer articles with subheadings survive.
  static String _longestProseRun(String stripped) {
    final blocks = stripped
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((b) => b.isNotEmpty)
        .toList();
    if (blocks.isEmpty) return '';

    final isProse = blocks.map(_looksLikeProse).toList();

    // Greedy walk: track the best (start, endExclusive, prose count) that
    // accumulated while tolerating at most one consecutive non-prose gap.
    var bestStart = -1;
    var bestEndAfterLastProse = -1;
    var bestProse = 0;

    var curStart = -1;
    var curEndAfterLastProse = -1;
    var curProse = 0;
    var gapsSinceLastProse = 999;

    void flushIfBest() {
      if (curProse > bestProse) {
        bestProse = curProse;
        bestStart = curStart;
        bestEndAfterLastProse = curEndAfterLastProse;
      }
    }

    for (var i = 0; i < blocks.length; i++) {
      if (isProse[i]) {
        if (curStart < 0) curStart = i;
        curProse++;
        curEndAfterLastProse = i + 1;
        gapsSinceLastProse = 0;
      } else if (curStart >= 0 && gapsSinceLastProse == 0) {
        // One-block gap allowed (e.g. a "## Section" heading).
        gapsSinceLastProse = 1;
      } else {
        flushIfBest();
        curStart = -1;
        curEndAfterLastProse = -1;
        curProse = 0;
        gapsSinceLastProse = 999;
      }
    }
    flushIfBest();

    if (bestProse < 1 || bestStart < 0) return '';
    return blocks.sublist(bestStart, bestEndAfterLastProse).join('\n\n');
  }

  /// A paragraph "looks like prose" when it has enough length, real
  /// terminal punctuation, and isn't dominated by short capitalised words
  /// (a near-perfect signature of nav menus / topic tag clouds).
  static bool _looksLikeProse(String s) {
    if (s.length < 80) return false;
    if (!RegExp(r'[.!?]').hasMatch(s)) return false;
    final words = s.split(RegExp(r'\s+'));
    if (words.length < 14) return false;
    final shortCapWords = words.where((w) =>
        w.length <= 6 && RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(w)).length;
    if (shortCapWords / words.length > 0.6) return false;
    return true;
  }
}
