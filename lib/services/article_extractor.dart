import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// What we extract from an article URL — enough to render the preview card
/// in the article sheet and to feed the TTS engine.
class ExtractedArticle {
  /// Stable ID derived from the source URL. Lives in the same namespace as
  /// YouTube video IDs but prefixed with "art-" to avoid collisions.
  final String id;
  final String sourceUrl;
  final String title;
  final String byline;
  final String text;
  final int wordCount;
  final String? thumbnailUrl;

  const ExtractedArticle({
    required this.id,
    required this.sourceUrl,
    required this.title,
    required this.byline,
    required this.text,
    required this.wordCount,
    required this.thumbnailUrl,
  });

  /// Very rough estimate: ElevenLabs voices average ~150 words/min in English.
  int get estimatedDurationSeconds => (wordCount * 60 / 150).round();
}

class ArticleException implements Exception {
  final String message;
  const ArticleException(this.message);
  @override
  String toString() => message;
}

class ArticleExtractor {
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  Future<ExtractedArticle> extract(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const ArticleException('Not a valid URL.');
    }

    final http.Response res;
    try {
      res = await http
          .get(uri, headers: {
            'User-Agent': _userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          })
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const ArticleException('Article fetch timed out.');
    } catch (e) {
      throw ArticleException('Couldn\'t reach the page: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ArticleException('Page returned HTTP ${res.statusCode}.');
    }

    final body = _decodeBody(res);
    final document = html_parser.parse(body);

    final title = _pickTitle(document, uri);
    final byline = _pickByline(document, uri);
    final thumbnailUrl = _pickThumbnail(document, uri);
    final text = _pickArticleText(document);

    if (text.trim().length < 80) {
      throw const ArticleException(
        'Couldn\'t find readable text on this page.',
      );
    }

    return ExtractedArticle(
      id: _idFromUrl(url),
      sourceUrl: url,
      title: title,
      byline: byline,
      text: text,
      wordCount: _countWords(text),
      thumbnailUrl: thumbnailUrl,
    );
  }

  String _decodeBody(http.Response res) {
    // `http` defaults to latin-1 when no charset is set on the response. Most
    // article pages are UTF-8 even if the header omits charset — try UTF-8
    // first and fall back to whatever the package picked.
    try {
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } catch (_) {
      return res.body;
    }
  }

  String _pickTitle(dom.Document doc, Uri uri) {
    final ogTitle = doc
        .querySelector('meta[property="og:title"]')
        ?.attributes['content']
        ?.trim();
    if (ogTitle != null && ogTitle.isNotEmpty) return ogTitle;

    final twTitle = doc
        .querySelector('meta[name="twitter:title"]')
        ?.attributes['content']
        ?.trim();
    if (twTitle != null && twTitle.isNotEmpty) return twTitle;

    final h1 = doc.querySelector('article h1')?.text.trim() ??
        doc.querySelector('h1')?.text.trim();
    if (h1 != null && h1.isNotEmpty) return h1;

    final headTitle = doc.querySelector('title')?.text.trim();
    if (headTitle != null && headTitle.isNotEmpty) return headTitle;

    return uri.host;
  }

  String _pickByline(dom.Document doc, Uri uri) {
    final candidates = <String?>[
      doc.querySelector('meta[name="author"]')?.attributes['content'],
      doc.querySelector('meta[property="article:author"]')?.attributes['content'],
      doc.querySelector('meta[property="og:site_name"]')?.attributes['content'],
      doc.querySelector('[rel="author"]')?.text,
    ];
    for (final c in candidates) {
      final v = c?.trim();
      if (v != null && v.isNotEmpty && v.length < 80) return v;
    }
    return uri.host.replaceFirst('www.', '');
  }

  String? _pickThumbnail(dom.Document doc, Uri base) {
    final candidates = <String?>[
      doc.querySelector('meta[property="og:image"]')?.attributes['content'],
      doc.querySelector('meta[name="twitter:image"]')?.attributes['content'],
    ];
    for (final c in candidates) {
      final v = c?.trim();
      if (v == null || v.isEmpty) continue;
      final abs = Uri.tryParse(v);
      if (abs == null) continue;
      if (abs.hasScheme) return abs.toString();
      return base.resolveUri(abs).toString();
    }
    return null;
  }

  /// Heuristic main-text extraction. We score every <p>-containing block by
  /// its visible text length, pick the heaviest one, then concatenate its
  /// paragraphs. This is intentionally simpler than a full readability
  /// algorithm — most modern news sites mark the body with <article> or a
  /// `role="main"` container that wins by sheer text mass.
  String _pickArticleText(dom.Document doc) {
    // Strip elements that never carry article body content.
    const dropSelectors = [
      'script',
      'style',
      'noscript',
      'header',
      'footer',
      'nav',
      'aside',
      'form',
      'iframe',
      'figure figcaption',
      '[role="navigation"]',
      '[role="banner"]',
      '[role="complementary"]',
      '[aria-hidden="true"]',
    ];
    for (final sel in dropSelectors) {
      for (final el in doc.querySelectorAll(sel)) {
        el.remove();
      }
    }

    final candidates = <dom.Element>[
      ...doc.querySelectorAll('article'),
      ...doc.querySelectorAll('main'),
      ...doc.querySelectorAll('[role="main"]'),
      ...doc.querySelectorAll('.post-content, .article-content, .entry-content, .story-body, .post-body'),
    ];
    if (candidates.isEmpty && doc.body != null) {
      candidates.add(doc.body!);
    }

    dom.Element? bestContainer;
    int bestScore = 0;
    for (final el in candidates) {
      final score = _scoreContainer(el);
      if (score > bestScore) {
        bestScore = score;
        bestContainer = el;
      }
    }

    final root = bestContainer ?? doc.body;
    if (root == null) return '';

    final paragraphs = <String>[];
    for (final p in root.querySelectorAll('p, h2, h3, li, blockquote')) {
      final txt = _normalize(p.text);
      if (txt.length < 24) continue;
      paragraphs.add(txt);
    }

    if (paragraphs.isEmpty) {
      return _normalize(root.text);
    }
    return paragraphs.join('\n\n');
  }

  int _scoreContainer(dom.Element el) {
    var score = 0;
    for (final p in el.querySelectorAll('p')) {
      score += p.text.trim().length;
    }
    return score;
  }

  String _normalize(String s) {
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _countWords(String s) {
    if (s.trim().isEmpty) return 0;
    return s.trim().split(RegExp(r'\s+')).length;
  }

  static String _idFromUrl(String url) {
    int h = 0;
    for (int i = 0; i < url.length; i++) {
      h = ((h * 31) + url.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return 'art-${h.toRadixString(16).padLeft(8, '0')}';
  }
}
