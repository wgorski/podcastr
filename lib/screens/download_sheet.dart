import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';
import '../services/youtube_downloader.dart';
import '../theme/aurora_theme.dart';
import '../widgets/thumbnail.dart';

enum _Phase { resolving, ready, error }

/// Bottom-sheet flow for resolving a YouTube URL.
///
/// After this refactor the sheet only handles the resolve → ready → error
/// transitions. Once the user confirms (Save audio) the sheet emits a
/// freshly-built [Track] with [TrackStatus.downloading] and dismisses; the
/// actual byte download then lives in [DownloadManager], with the row
/// already visible in the library.
class DownloadSheet extends StatefulWidget {
  final String url;
  final VoidCallback onClose;
  final void Function(Track downloadingTrack) onStartDownload;
  const DownloadSheet({
    super.key,
    required this.url,
    required this.onClose,
    required this.onStartDownload,
  });

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet> {
  final _downloader = YoutubeDownloader();
  _Phase _phase = _Phase.resolving;
  ResolvedVideo? _resolved;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final v = await _downloader.resolve(widget.url);
      if (!mounted) return;
      setState(() {
        _resolved = v;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _friendlyResolveError(e);
      });
    }
  }

  Future<void> _confirm() async {
    final v = _resolved;
    if (v == null) return;
    final filePath = await YoutubeDownloader.predictedFilePath(v);
    if (!mounted) return;
    final palette = paletteForId(v.videoId);
    final track = Track(
      id: v.videoId,
      title: v.title,
      channel: v.channel,
      duration: v.durationSeconds,
      size: '',
      addedAt: 'Today',
      color1: palette.c1,
      color2: palette.c2,
      filePath: filePath,
      status: TrackStatus.downloading,
      sourceUrl: widget.url,
    );
    widget.onStartDownload(track);
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
              resolved: _resolved,
              errorMessage: _errorMessage,
              url: widget.url,
              onDownload: _confirm,
              onClose: widget.onClose,
              onRetry: () {
                setState(() {
                  _phase = _Phase.resolving;
                  _errorMessage = null;
                });
                _resolve();
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Sheet extends StatelessWidget {
  final _Phase phase;
  final ResolvedVideo? resolved;
  final String? errorMessage;
  final String url;
  final VoidCallback onDownload;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  const _Sheet({
    required this.phase,
    required this.resolved,
    required this.errorMessage,
    required this.url,
    required this.onDownload,
    required this.onClose,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AuroraTheme.surface,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
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
                  switch (phase) {
                    _Phase.error => 'Couldn\'t read this link',
                    _ => 'Save audio',
                  },
                  style: AuroraTheme.display(size: 18, weight: FontWeight.w700, letterSpacing: -0.3),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 20, color: AuroraTheme.muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
            child: _MetadataCard(phase: phase, resolved: resolved, url: url),
          ),
          if (phase == _Phase.error)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Text(
                errorMessage ?? 'Unknown error',
                style: AuroraTheme.body(size: 12, color: AuroraTheme.muted, height: 1.4),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: switch (phase) {
              _Phase.resolving => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Reading video metadata…',
                      style: AuroraTheme.body(size: 12, color: AuroraTheme.muted),
                    ),
                  ),
                ),
              _Phase.ready => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded, size: 18, color: AuroraTheme.onAccent),
                    label: Text(
                      'Save audio',
                      style: AuroraTheme.body(size: 14, weight: FontWeight.w700, color: AuroraTheme.onAccent),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AuroraTheme.accent,
                      foregroundColor: AuroraTheme.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          'Close',
                          style: AuroraTheme.body(size: 13, weight: FontWeight.w600, color: AuroraTheme.muted),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Retry',
                          style: AuroraTheme.body(size: 13, weight: FontWeight.w700, color: AuroraTheme.onAccent),
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

/// Translate a raw resolve failure into a short, human-readable line.
///
/// The native bridge wraps every NewPipe / extractor throwable as a
/// `PlatformException("EXTRACT", <message>)`, so the raw text is
/// developer-facing ("URL not accepted: https://…", parser internals). The
/// sheet title already says "Couldn't read this link" — this fills in the
/// *why* in plain language. Falls back to a generic retry prompt for
/// anything we don't recognise.
String _friendlyResolveError(Object e) {
  final raw = (e is PlatformException ? e.message : null) ?? e.toString();
  final m = raw.toLowerCase();

  if (m.contains('url not accepted') ||
      m.contains('not a valid') ||
      m.contains('unsupported url')) {
    return "That doesn't look like a valid YouTube video link.";
  }
  if (m.contains('unable to resolve host') ||
      m.contains('unknownhost') ||
      m.contains('failed to connect') ||
      m.contains('timeout') ||
      m.contains('timed out') ||
      m.contains('network is unreachable')) {
    return 'No internet connection. Check your network and try again.';
  }
  if ((m.contains('age') && m.contains('restrict')) ||
      m.contains('login') ||
      m.contains('sign in') ||
      m.contains('private') ||
      m.contains('drm') ||
      m.contains('protected')) {
    return "This video can't be downloaded — it may be private, age-restricted, or DRM-protected.";
  }
  if (m.contains('country') || m.contains('region') || m.contains('geo')) {
    return "This video isn't available in your region.";
  }
  if (m.contains('not available') ||
      m.contains('unavailable') ||
      m.contains('removed') ||
      m.contains('terminated') ||
      m.contains('deleted')) {
    return 'This video is no longer available.';
  }
  // Parser / "page needs to be reloaded" style failures — usually transient
  // or a sign the extractor needs a bump. Either way, suggest a retry.
  return 'Something went wrong reading this video. Tap Retry to try again.';
}

class _MetadataCard extends StatelessWidget {
  final _Phase phase;
  final ResolvedVideo? resolved;
  final String url;
  const _MetadataCard({required this.phase, required this.resolved, required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AuroraTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AuroraTheme.border, width: 1),
      ),
      child: (phase == _Phase.resolving || resolved == null)
          ? Row(
              children: [
                const _Shimmer(width: 44, height: 44, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Shimmer(width: MediaQuery.of(context).size.width * 0.55, height: 11, radius: 4),
                      const SizedBox(height: 6),
                      Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuroraTheme.mono(size: 10, color: AuroraTheme.dim),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                _PreviewArt(videoId: resolved!.videoId),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resolved!.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AuroraTheme.body(size: 14, weight: FontWeight.w600, height: 1.25),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${resolved!.channel} · ${formatShort(resolved!.durationSeconds)}',
                        style: AuroraTheme.body(size: 12, color: AuroraTheme.muted),
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
  final String videoId;
  const _PreviewArt({required this.videoId});

  @override
  Widget build(BuildContext context) {
    final palette = paletteForId(videoId);
    final pseudoTrack = Track(
      id: videoId,
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

class _Shimmer extends StatefulWidget {
  final double width, height, radius;
  const _Shimmer({required this.width, required this.height, required this.radius});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _c.value, 0),
              end: Alignment(1 + 2 * _c.value, 0),
              colors: [
                Colors.white.withValues(alpha: 0.04),
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
          ),
        );
      },
    );
  }
}
