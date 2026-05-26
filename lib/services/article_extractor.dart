import 'jina_reader.dart';
import 'readability_extractor.dart';

/// User-selectable extraction strategy. Stored in [SettingsStore] and
/// passed into [ArticleExtractor.extract] per call.
enum ExtractionMode {
  /// Try Jina Reader first (fast hosted service); on failure, run the
  /// bundled Readability.js inside a HeadlessInAppWebView.
  jinaWithLocalFallback,

  /// Skip Jina entirely and always run the on-device Readability.js
  /// path. Useful when the user doesn't want to send article URLs to a
  /// third-party reader service.
  localOnly,
}

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

  /// True when the primary extractor (Jina Reader) was unreachable and we
  /// fell back to running Readability.js inside a hidden WebView. Surfaced
  /// to the user as a small notice on the article sheet.
  final bool usedFallback;

  /// When [usedFallback] is true, this is the short reason the primary
  /// extractor was abandoned (e.g. "Jina Reader timed out.").
  final String? fallbackReason;

  const ExtractedArticle({
    required this.id,
    required this.sourceUrl,
    required this.title,
    required this.byline,
    required this.text,
    required this.wordCount,
    required this.thumbnailUrl,
    this.usedFallback = false,
    this.fallbackReason,
  });

  /// Very rough estimate: ElevenLabs voices average ~150 words/min in English.
  int get estimatedDurationSeconds => (wordCount * 60 / 150).round();

  ExtractedArticle copyWith({
    bool? usedFallback,
    String? fallbackReason,
  }) {
    return ExtractedArticle(
      id: id,
      sourceUrl: sourceUrl,
      title: title,
      byline: byline,
      text: text,
      wordCount: wordCount,
      thumbnailUrl: thumbnailUrl,
      usedFallback: usedFallback ?? this.usedFallback,
      fallbackReason: fallbackReason ?? this.fallbackReason,
    );
  }

  static int countWords(String s) {
    final t = s.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).length;
  }

  static String idFromUrl(String url) {
    int h = 0;
    for (int i = 0; i < url.length; i++) {
      h = ((h * 31) + url.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return 'art-${h.toRadixString(16).padLeft(8, '0')}';
  }
}

class ArticleException implements Exception {
  final String message;
  const ArticleException(this.message);
  @override
  String toString() => message;
}

/// Orchestrates the two-tier article extraction:
///
/// 1. **Jina Reader** (`r.jina.ai`) — a hosted reader-mode service that
///    returns clean markdown. Fast, robust on most sites, no API key.
/// 2. **Readability.js in a headless WebView** — bundled fallback for when
///    Jina is unreachable / blocked / fails the page. Slower (we boot a
///    hidden browser) but works offline of Jina.
class ArticleExtractor {
  final JinaReader _jina;
  final ReadabilityExtractor _readability;

  /// Mode used when [extract] is called without an explicit override.
  final ExtractionMode defaultMode;

  ArticleExtractor({
    JinaReader? jina,
    ReadabilityExtractor? readability,
    this.defaultMode = ExtractionMode.jinaWithLocalFallback,
  })  : _jina = jina ?? JinaReader(),
        _readability = readability ?? ReadabilityExtractor();

  Future<ExtractedArticle> extract(String url, {ExtractionMode? mode}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const ArticleException('Not a valid URL.');
    }
    final useMode = mode ?? defaultMode;

    if (useMode == ExtractionMode.localOnly) {
      try {
        return await _readability.extract(url);
      } catch (e) {
        throw ArticleException('Couldn\'t read this page: $e');
      }
    }

    // jinaWithLocalFallback: try Jina, fall back to Readability on a
    // recognised JinaException. Other errors propagate as-is.
    try {
      return await _jina.extract(url);
    } on JinaException catch (jinaErr) {
      try {
        final result = await _readability.extract(url);
        return result.copyWith(
          usedFallback: true,
          fallbackReason: jinaErr.message,
        );
      } catch (fallbackErr) {
        throw ArticleException(
          'Couldn\'t read this page. Jina: ${jinaErr.message} '
          'Local reader: $fallbackErr',
        );
      }
    }
  }

  void dispose() {
    _jina.dispose();
  }
}
