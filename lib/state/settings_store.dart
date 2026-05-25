import 'package:shared_preferences/shared_preferences.dart';

import '../services/elevenlabs_tts.dart';

/// User-configurable settings. Today: ElevenLabs API key + voice ID for
/// article→podcast TTS. SharedPreferences-backed; no encryption (good
/// enough for a personal tool, upgrade to EncryptedSharedPreferences if
/// you ever ship this).
class SettingsStore {
  static const _keyApiKey = 'elevenlabs.apiKey';
  static const _keyVoiceId = 'elevenlabs.voiceId';

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
}
