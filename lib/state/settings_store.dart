import 'package:shared_preferences/shared_preferences.dart';

import '../services/article_extractor.dart';
import '../services/elevenlabs_tts.dart';

/// User-configurable settings. Today: ElevenLabs API key + voice ID for
/// article→podcast TTS, plus the preferred article-extraction strategy.
/// SharedPreferences-backed; no encryption (good enough for a personal
/// tool, upgrade to EncryptedSharedPreferences if you ever ship this).
class SettingsStore {
  static const _keyApiKey = 'elevenlabs.apiKey';
  static const _keyVoiceId = 'elevenlabs.voiceId';
  static const _keyExtractionMode = 'article.extractionMode';

  Future<String?> apiKey() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_keyApiKey)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<String> voiceId() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_keyVoiceId)?.trim();
    return (v == null || v.isEmpty) ? ElevenLabsTts.defaultVoiceId : v;
  }

  Future<ExtractionMode> extractionMode() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_keyExtractionMode);
    if (raw == null) return ExtractionMode.jinaWithLocalFallback;
    for (final mode in ExtractionMode.values) {
      if (mode.name == raw) return mode;
    }
    return ExtractionMode.jinaWithLocalFallback;
  }

  Future<void> setApiKey(String? value) async {
    final p = await SharedPreferences.getInstance();
    final v = value?.trim();
    if (v == null || v.isEmpty) {
      await p.remove(_keyApiKey);
    } else {
      await p.setString(_keyApiKey, v);
    }
  }

  Future<void> setVoiceId(String? value) async {
    final p = await SharedPreferences.getInstance();
    final v = value?.trim();
    if (v == null || v.isEmpty) {
      await p.remove(_keyVoiceId);
    } else {
      await p.setString(_keyVoiceId, v);
    }
  }

  Future<void> setExtractionMode(ExtractionMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyExtractionMode, mode.name);
  }
}
