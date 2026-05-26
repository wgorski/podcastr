import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'article_extractor.dart';

class ReadabilityException implements Exception {
  final String message;
  const ReadabilityException(this.message);
  @override
  String toString() => message;
}

/// On-device fallback: open the article in an invisible WebView, inject
/// Mozilla's Readability.js, and pull `article.textContent` out of the
/// live DOM.
///
/// We use this when [JinaReader] is unreachable / returns nothing
/// usable. The WebView runs the page's real JavaScript, so it handles
/// most modern SPAs / hydration that a pure HTML fetch would miss.
class ReadabilityExtractor {
  static const _assetPath = 'assets/readability.js';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  static const _timeout = Duration(seconds: 40);

  String? _cachedJs;

  Future<String> _readabilityJs() async {
    final cached = _cachedJs;
    if (cached != null) return cached;
    final js = await rootBundle.loadString(_assetPath);
    _cachedJs = js;
    return js;
  }

  Future<ExtractedArticle> extract(String url) async {
    final readabilityJs = await _readabilityJs();
    final completer = Completer<Map<String, dynamic>>();
    HeadlessInAppWebView? headless;

    void fail(Object e) {
      if (completer.isCompleted) return;
      completer.completeError(
        e is ReadabilityException ? e : ReadabilityException(e.toString()),
      );
    }

    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _userAgent,
        transparentBackground: true,
        // Block media/plugins — we only need the DOM + scripts.
        mediaPlaybackRequiresUserGesture: true,
        useShouldInterceptRequest: false,
      ),
      onLoadStop: (controller, _) async {
        try {
          await controller.evaluateJavascript(source: readabilityJs);
          final raw = await controller.evaluateJavascript(source: _runnerJs);
          // evaluateJavascript returns whatever JS returned — for a
          // JSON.stringify result it comes back as a String.
          if (raw is! String) {
            fail(const ReadabilityException(
                'Readability returned an unexpected type.'));
            return;
          }
          final Map<String, dynamic> parsed;
          try {
            parsed = jsonDecode(raw) as Map<String, dynamic>;
          } catch (_) {
            fail(const ReadabilityException(
                'Readability returned a malformed payload.'));
            return;
          }
          final err = parsed['error'];
          if (err is String && err.isNotEmpty) {
            fail(ReadabilityException(err));
            return;
          }
          if (!completer.isCompleted) completer.complete(parsed);
        } catch (e) {
          fail(e);
        }
      },
      onReceivedError: (controller, request, error) {
        // Only fail on main-frame errors — subresource failures (ads, fonts)
        // shouldn't tank the whole extraction.
        if (request.isForMainFrame ?? false) {
          fail(ReadabilityException('Page failed to load: ${error.description}'));
        }
      },
      onReceivedHttpError: (controller, request, response) {
        if ((request.isForMainFrame ?? false) &&
            (response.statusCode ?? 0) >= 400) {
          fail(ReadabilityException(
              'Page returned HTTP ${response.statusCode}.'));
        }
      },
    );

    try {
      await headless.run();
      final result = await completer.future.timeout(
        _timeout,
        onTimeout: () => throw const ReadabilityException(
            'Readability extraction timed out.'),
      );
      return _buildArticle(url, result);
    } finally {
      try {
        await headless.dispose();
      } catch (_) {/* swallow — best-effort cleanup */}
    }
  }

  ExtractedArticle _buildArticle(String url, Map<String, dynamic> r) {
    final text = ((r['content'] as String?) ?? '').trim();
    if (text.length < 80) {
      throw const ReadabilityException(
          'Readability extracted too little text.');
    }
    final title = ((r['title'] as String?) ?? '').trim();
    final byline = ((r['byline'] as String?) ?? '').trim();
    final siteName = ((r['siteName'] as String?) ?? '').trim();
    final thumb = (r['thumbnailUrl'] as String?)?.trim();
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
    return ExtractedArticle(
      id: ExtractedArticle.idFromUrl(url),
      sourceUrl: url,
      title: title.isNotEmpty ? title : host,
      byline: byline.isNotEmpty
          ? byline
          : (siteName.isNotEmpty ? siteName : host),
      text: text,
      wordCount: ExtractedArticle.countWords(text),
      thumbnailUrl: (thumb != null && thumb.isNotEmpty) ? thumb : null,
    );
  }

  /// JS that runs inside the headless WebView after Readability.js is
  /// injected. Returns a JSON string so we can shuttle the structured
  /// result back across the platform channel without dealing with type
  /// coercion quirks.
  static const _runnerJs = r'''
    (function() {
      try {
        if (typeof Readability !== "function") {
          return JSON.stringify({ error: "Readability not defined" });
        }
        var docClone = document.cloneNode(true);
        var article = new Readability(docClone).parse();
        if (!article) {
          return JSON.stringify({ error: "Readability returned null" });
        }
        function metaContent(selector) {
          var el = document.querySelector(selector);
          return (el && el.getAttribute("content")) || null;
        }
        var ogImage = metaContent('meta[property="og:image"]')
                   || metaContent('meta[name="twitter:image"]');
        var ogSite = metaContent('meta[property="og:site_name"]');
        return JSON.stringify({
          title: article.title || "",
          byline: article.byline || "",
          siteName: article.siteName || ogSite || "",
          content: article.textContent || "",
          length: article.length || 0,
          thumbnailUrl: ogImage
        });
      } catch (e) {
        return JSON.stringify({ error: String(e && e.message ? e.message : e) });
      }
    })();
  ''';
}
