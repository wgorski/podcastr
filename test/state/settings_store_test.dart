import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/services/article_extractor.dart';
import 'package:podcastr/services/elevenlabs_tts.dart';
import 'package:podcastr/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = SettingsStore();
  });

  group('SettingsStore.apiKey', () {
    test('returns null when nothing is stored', () async {
      expect(await store.apiKey(), isNull);
    });

    test('round-trips a saved key', () async {
      await store.setApiKey('sk_secret_value');
      expect(await store.apiKey(), 'sk_secret_value');
    });

    test('treats blank strings as a removal', () async {
      await store.setApiKey('sk_secret_value');
      await store.setApiKey('   ');
      expect(await store.apiKey(), isNull);
    });

    test('treats null as a removal', () async {
      await store.setApiKey('sk_secret_value');
      await store.setApiKey(null);
      expect(await store.apiKey(), isNull);
    });
  });

  group('SettingsStore.voiceId', () {
    test('falls back to the ElevenLabs default voice when nothing is stored',
        () async {
      expect(await store.voiceId(), ElevenLabsTts.defaultVoiceId);
    });

    test('returns the saved voice ID', () async {
      await store.setVoiceId('abc123');
      expect(await store.voiceId(), 'abc123');
    });

    test('falls back to the default when the stored value is blank',
        () async {
      await store.setVoiceId('   ');
      expect(await store.voiceId(), ElevenLabsTts.defaultVoiceId);
    });
  });

  group('SettingsStore.extractionMode', () {
    test('defaults to jinaWithLocalFallback when nothing is stored',
        () async {
      expect(await store.extractionMode(),
          ExtractionMode.jinaWithLocalFallback);
    });

    test('round-trips localOnly', () async {
      await store.setExtractionMode(ExtractionMode.localOnly);
      expect(await store.extractionMode(), ExtractionMode.localOnly);
    });

    test('round-trips jinaWithLocalFallback', () async {
      await store.setExtractionMode(ExtractionMode.localOnly);
      await store.setExtractionMode(ExtractionMode.jinaWithLocalFallback);
      expect(await store.extractionMode(),
          ExtractionMode.jinaWithLocalFallback);
    });

    test('falls back to the default for an unknown stored value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'article.extractionMode': 'bogus-mode',
      });
      final fresh = SettingsStore();
      expect(await fresh.extractionMode(),
          ExtractionMode.jinaWithLocalFallback);
    });
  });
}
