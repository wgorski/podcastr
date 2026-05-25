import 'package:flutter/material.dart';

import '../services/elevenlabs_tts.dart';
import '../state/settings_store.dart';
import '../theme/aurora_theme.dart';

/// Full-screen settings UI for the ElevenLabs API key + voice id.
///
/// Returns `true` from [Navigator.pop] if the user saved a non-empty API
/// key during this visit — callers use that to immediately retry the
/// article-generation flow that brought the user here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _store = SettingsStore();
  final _apiKeyCtrl = TextEditingController();
  final _voiceCtrl = TextEditingController();
  bool _obscure = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await _store.apiKey();
    final voice = await _store.voiceId();
    if (!mounted) return;
    setState(() {
      _apiKeyCtrl.text = key ?? '';
      _voiceCtrl.text = voice;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final key = _apiKeyCtrl.text.trim();
    final voice = _voiceCtrl.text.trim();
    await _store.setApiKey(key.isEmpty ? null : key);
    await _store.setVoiceId(voice.isEmpty ? null : voice);
    if (!mounted) return;
    Navigator.of(context).pop(key.isNotEmpty);
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _voiceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuroraTheme.bg,
      body: DecoratedBox(
        decoration: AuroraTheme.backgroundDecoration,
        child: SafeArea(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator(color: AuroraTheme.accent))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: AuroraTheme.text, size: 22),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Settings',
                            style: AuroraTheme.display(
                                size: 20,
                                weight: FontWeight.w700,
                                letterSpacing: -0.4),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          _SectionLabel('Article → podcast (ElevenLabs)'),
                          const SizedBox(height: 8),
                          Text(
                            'Paste your ElevenLabs API key to convert shared article URLs into spoken-word audio. '
                            'YouTube links keep using direct extraction and don\'t need a key.',
                            style: AuroraTheme.body(
                                size: 12, color: AuroraTheme.muted, height: 1.45),
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel('API key'),
                          const SizedBox(height: 6),
                          _ApiKeyField(
                            controller: _apiKeyCtrl,
                            obscure: _obscure,
                            onToggle: () => setState(() => _obscure = !_obscure),
                          ),
                          const SizedBox(height: 16),
                          _FieldLabel('Voice ID'),
                          const SizedBox(height: 6),
                          _PlainField(
                            controller: _voiceCtrl,
                            hint: ElevenLabsTts.defaultVoiceId,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Default is "Rachel". Find more in your ElevenLabs voice library and paste the ID here.',
                            style: AuroraTheme.body(
                                size: 11, color: AuroraTheme.dim, height: 1.4),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AuroraTheme.accent,
                                foregroundColor: AuroraTheme.onAccent,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              child: Text(
                                'Save',
                                style: AuroraTheme.body(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: AuroraTheme.onAccent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AuroraTheme.body(
        size: 13,
        weight: FontWeight.w700,
        color: AuroraTheme.text,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AuroraTheme.body(
        size: 11,
        weight: FontWeight.w600,
        color: AuroraTheme.muted,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _ApiKeyField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  const _ApiKeyField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      cursorColor: AuroraTheme.accent,
      style: AuroraTheme.mono(size: 12),
      decoration: InputDecoration(
        hintText: 'sk_…',
        hintStyle: AuroraTheme.mono(size: 12, color: AuroraTheme.dim),
        filled: true,
        fillColor: AuroraTheme.surface2,
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
            color: AuroraTheme.muted,
          ),
          onPressed: onToggle,
        ),
        border: _border(),
        focusedBorder: _border(color: AuroraTheme.accent),
        enabledBorder: _border(),
      ),
    );
  }

  OutlineInputBorder _border({Color? color}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color ?? AuroraTheme.border),
      );
}

class _PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _PlainField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      cursorColor: AuroraTheme.accent,
      style: AuroraTheme.mono(size: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AuroraTheme.mono(size: 12, color: AuroraTheme.dim),
        filled: true,
        fillColor: AuroraTheme.surface2,
        isDense: true,
        border: _border(),
        focusedBorder: _border(color: AuroraTheme.accent),
        enabledBorder: _border(),
      ),
    );
  }

  OutlineInputBorder _border({Color? color}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color ?? AuroraTheme.border),
      );
}
