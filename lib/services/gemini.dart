import 'package:flutter/services.dart';

/// Shares to the standalone Google Gemini app via the native bridge.
/// Reuses the app's single MethodChannel (named after the YouTube bridge,
/// but it carries all native calls).
const _channel = MethodChannel('com.wgorski.podcastr/youtube');

class Gemini {
  /// Whether the Gemini app is installed. The "Summarize via Gemini" action
  /// is only offered when this is true.
  static Future<bool> isInstalled() async {
    final installed = await _channel.invokeMethod<bool>('isGeminiInstalled');
    return installed ?? false;
  }

  /// Fires an ACTION_SEND text intent targeted at the Gemini app with the
  /// prompt `summarize <url>`.
  static Future<void> summarize(String url) => _channel.invokeMethod(
        'summarizeViaGemini',
        {'text': 'summarize $url'},
      );
}
