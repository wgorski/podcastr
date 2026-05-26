import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/article_extractor.dart';
import '../services/youtube_downloader.dart';
import '../state/settings_store.dart';
import '../theme/aurora_theme.dart';
import '../widgets/thumbnail.dart';

enum _Phase { resolving, ready, error, noKey }

/// Bottom-sheet that mirrors [DownloadSheet] but for arbitrary article URLs.
/// Resolves the URL into an [ExtractedArticle], previews title/byline/word
/// count, and on confirm hands a downloading [Track] back to the caller.
/// The actual TTS work runs inside [DownloadManager.startArticleGeneration].
class ArticleSheet extends StatefulWidget {
  final String url;
  final VoidCallback onClose;
  final void Function(Track downloadingTrack, ExtractedArticle article)
      onStartGeneration;
  final VoidCallback onOpenSettings;
  const ArticleSheet({
    super.key,
    required this.url,
    required this.onClose,
    required this.onStartGeneration,
    required this.onOpenSettings,
  });

  @override
  State<ArticleSheet> createState() => _ArticleSheetState();
}

class _ArticleSheetState extends State<ArticleSheet> {
  final _extractor = ArticleExtractor();
  final _settings = SettingsStore();
  _Phase _phase = _Phase.resolving;
  ExtractedArticle? _article;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _extractor.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() {
      _phase = _Phase.resolving;
      _errorMessage = null;
    });
    try {
      final mode = await _settings.extractionMode();
      final article = await _extractor.extract(widget.url, mode: mode);
      if (!mounted) return;
      // Surface the missing-key state up front — the user shouldn't have to
      // wait for ElevenLabs to reject the request to learn it's missing.
      final key = await _settings.apiKey();
      if (!mounted) return;
      setState(() {
        _article = article;
        _phase = (key == null) ? _Phase.noKey : _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _confirm() async {
    final article = _article;
    if (article == null) return;
    final palette = paletteForId(article.id);
    final tracksDir = await YoutubeDownloader.tracksDir();
    final filePath = '$tracksDir/${article.id}.mp3';
    if (!mounted) return;
    final track = Track(
      id: article.id,
      title: article.title,
      channel: article.byline,
      duration: article.estimatedDurationSeconds,
      size: '',
      addedAt: 'Today',
      color1: palette.c1,
      color2: palette.c2,
      filePath: filePath,
      status: TrackStatus.downloading,
      sourceUrl: article.sourceUrl,
    );
    widget.onStartGeneration(track, article);
  }

  Future<void> _openSettings() async {
    widget.onOpenSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withValues(alpha: 0.7)),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: _Sheet(
              phase: _phase,
              article: _article,
              errorMessage: _errorMessage,
              url: widget.url,
              onGenerate: _confirm,
              onClose: widget.onClose,
              onRetry: _resolve,
              onOpenSettings: _openSettings,
            ),
          ),
        ),
      ],
    );
  }
}

class _Sheet extends StatelessWidget {
  final _Phase phase;
  final ExtractedArticle? article;
  final String? errorMessage;
  final String url;
  final VoidCallback onGenerate;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  const _Sheet({
    required this.phase,
    required this.article,
    required this.errorMessage,
    required this.url,
    required this.onGenerate,
    required this.onClose,
    required this.onRetry,
    required this.onOpenSettings,
  });

  String get _title => switch (phase) {
        _Phase.error => 'Couldn\'t read this article',
        _Phase.noKey => 'Add your ElevenLabs key',
        _ => 'Read article aloud',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AuroraTheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
        border: Border.all(color: AuroraTheme.border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 4, bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Text(
                  _title,
                  style: AuroraTheme.display(
                      size: 18,
                      weight: FontWeight.w700,
                      letterSpacing: -0.3),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AuroraTheme.muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
            child: _MetadataCard(phase: phase, article: article, url: url),
          ),
          if (article != null && article!.usedFallback)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: _FallbackNotice(reason: article!.fallbackReason),
            ),
          if (phase == _Phase.error)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Text(
                errorMessage ?? 'Unknown error',
                style: AuroraTheme.body(
                    size: 12, color: AuroraTheme.muted, height: 1.4),
              ),
            ),
          if (phase == _Phase.noKey)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Text(
                'Article-to-podcast uses the ElevenLabs API. Paste your key in Settings, then come back to this sheet.',
                style: AuroraTheme.body(
                    size: 12, color: AuroraTheme.muted, height: 1.45),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: switch (phase) {
              _Phase.resolving => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Reading article…',
                      style: AuroraTheme.body(
                          size: 12, color: AuroraTheme.muted),
                    ),
                  ),
                ),
              _Phase.ready => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onGenerate,
                    icon: const Icon(Icons.graphic_eq_rounded,
                        size: 18, color: AuroraTheme.onAccent),
                    label: Text(
                      'Generate audio',
                      style: AuroraTheme.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AuroraTheme.onAccent),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AuroraTheme.accent,
                      foregroundColor: AuroraTheme.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              _Phase.noKey => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.key_rounded,
                        size: 18, color: AuroraTheme.onAccent),
                    label: Text(
                      'Open Settings',
                      style: AuroraTheme.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AuroraTheme.onAccent),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AuroraTheme.accent,
                      foregroundColor: AuroraTheme.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              _Phase.error => Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onClose,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: const BorderSide(color: AuroraTheme.border),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          'Close',
                          style: AuroraTheme.body(
                              size: 13,
                              weight: FontWeight.w600,
                              color: AuroraTheme.muted),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AuroraTheme.accent,
                          foregroundColor: AuroraTheme.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Retry',
                          style: AuroraTheme.body(
                              size: 13,
                              weight: FontWeight.w700,
                              color: AuroraTheme.onAccent),
                        ),
                      ),
                    ),
                  ],
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final _Phase phase;
  final ExtractedArticle? article;
  final String url;
  const _MetadataCard({
    required this.phase,
    required this.article,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final showShimmer = phase == _Phase.resolving || article == null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AuroraTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AuroraTheme.border, width: 1),
      ),
      child: showShimmer
          ? Row(
              children: [
                _PreviewArt(seedId: url),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resolving article…',
                        style: AuroraTheme.body(
                            size: 13,
                            weight: FontWeight.w600,
                            color: AuroraTheme.muted,
                            height: 1.25),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuroraTheme.mono(
                            size: 10, color: AuroraTheme.dim),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PreviewArt(seedId: article!.id),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article!.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AuroraTheme.body(
                            size: 14,
                            weight: FontWeight.w600,
                            height: 1.25),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${article!.byline} · ${article!.wordCount} words · ~${formatShort(article!.estimatedDurationSeconds)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuroraTheme.body(
                            size: 12, color: AuroraTheme.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PreviewArt extends StatelessWidget {
  final String seedId;
  const _PreviewArt({required this.seedId});

  @override
  Widget build(BuildContext context) {
    final palette = paletteForId(seedId);
    final pseudoTrack = Track(
      id: seedId,
      title: '',
      channel: '',
      duration: 0,
      size: '',
      addedAt: '',
      color1: palette.c1,
      color2: palette.c2,
    );
    return SquareArt(track: pseudoTrack, size: 48, radius: 10);
  }
}

/// Light banner shown when Jina Reader was unreachable and we fell back to
/// the on-device Readability.js path. The user might still want to know
/// because the local reader can pick up slightly different boilerplate.
class _FallbackNotice extends StatelessWidget {
  final String? reason;
  const _FallbackNotice({required this.reason});

  @override
  Widget build(BuildContext context) {
    final r = reason?.trim();
    final tail = (r == null || r.isEmpty) ? '' : ' · $r';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AuroraTheme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AuroraTheme.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.offline_bolt_outlined,
              size: 14, color: AuroraTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Parsed with on-device reader (Jina unreachable$tail).',
              style: AuroraTheme.body(
                  size: 11, color: AuroraTheme.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
