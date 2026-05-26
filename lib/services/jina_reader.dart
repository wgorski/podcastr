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
            // Ask the reader to skip its image-captioning pass — we don't
            // use it and it slows the response down noticeably.
            'X-Retain-Images': 'none',
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
    final text = _stripMarkdown(markdown);
    if (text.length < 80) {
      throw const JinaException('Jina Reader returned too little text.');
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

  /// Best-effort Markdown → plain text. The ElevenLabs voice handles
  /// regular prose well; we just need to strip syntactic noise that would
  /// otherwise be read aloud as "asterisk asterisk" / "open bracket".
  static String _stripMarkdown(String md) {
    var s = md;
    // Fenced code blocks
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    // Indented code blocks (4+ leading spaces on every line of a run)
    s = s.replaceAll(RegExp(r'(?:^|\n)(?: {4,}[^\n]*\n?)+'), '\n');
    // Inline code
    s = s.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    // Images
    s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    // Links [text](url) → text
    s = s.replaceAll(RegExp(r'\[([^\]]*)\]\(([^)]*)\)'), r'$1');
    // Reference-style links / image refs
    s = s.replaceAll(RegExp(r'\[([^\]]+)\]\[[^\]]*\]'), r'$1');
    // Setext + ATX headings — drop the markers, keep the text
    s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^(=+|-+)\s*$', multiLine: true), '');
    // Bold / italic / strike
    s = s.replaceAll(RegExp(r'(\*\*|__)(.+?)\1'), r'$2');
    s = s.replaceAll(RegExp(r'(?<!\w)([*_])(.+?)\1(?!\w)'), r'$2');
    s = s.replaceAll(RegExp(r'~~(.+?)~~'), r'$1');
    // Blockquotes
    s = s.replaceAll(RegExp(r'^>\s?', multiLine: true), '');
    // List bullets / numbering
    s = s.replaceAll(RegExp(r'^\s*[\*\-\+]\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
    // Tables — drop the alignment row and pipe characters
    s = s.replaceAll(RegExp(r'^\s*\|?[\s\-:|]+\|?\s*$', multiLine: true), '');
    s = s.replaceAll(RegExp(r'\s*\|\s*'), ' ');
    // Horizontal rules
    s = s.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), '');
    // Collapse runs of blank lines
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // Trim trailing whitespace on each line
    s = s.split('\n').map((l) => l.trimRight()).join('\n');
    return s.trim();
  }
}
