import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_notifier.dart';
import '../services/youtube_downloader.dart';
import '../theme/aurora_theme.dart';
import '../widgets/thumbnail.dart';

enum _Phase { resolving, ready, downloading, done, error }

/// Bottom-sheet flow for downloading audio from a shared YouTube URL.
/// Resolving (NewPipe Extractor) → ready (size shown) → downloading → done.
class DownloadSheet extends StatefulWidget {
  final String url;
  final VoidCallback onClose;
  final void Function(Track) onComplete;
  const DownloadSheet({
    super.key,
    required this.url,
    required this.onClose,
    required this.onComplete,
  });

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet> {
  final _downloader = YoutubeDownloader();
  final _notifier = DownloadNotifier();
  _Phase _phase = _Phase.resolving;
  ResolvedVideo? _resolved;
  double _progress = 0.0;
  int _bytesReceived = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  StreamSubscription<DownloadProgress>? _sub;
  late final int _notificationId =
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 30);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _videoTitle() => _resolved?.title ?? 'Audio download';
  String _videoChannel() => _resolved?.channel ?? '';

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
        _errorMessage = e.toString();
      });
    }
  }

  void _startDownload() async {
    final v = _resolved;
    if (v == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _bytesReceived = 0;
      _totalBytes = 0;
    });
    // Indeterminate at first — we don't have content-length until headers arrive.
    _notifier.progress(
      id: _notificationId,
      title: _videoTitle(),
      channel: _videoChannel(),
      percent: null,
    );
    try {
      final path = await YoutubeDownloader.filePathFor(v);
      _sub = _downloader.download(v, filePath: path).listen((p) {
        if (!mounted) return;
        setState(() {
          _bytesReceived = p.bytesReceived;
          _totalBytes = p.totalBytes;
          _progress = p.fraction;
        });
        _notifier.progress(
          id: _notificationId,
          title: _videoTitle(),
          channel: _videoChannel(),
          percent: p.totalBytes > 0 ? (p.fraction * 100).round() : null,
        );
      }, onError: (e) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.error;
          _errorMessage = e.toString();
        });
        _notifier.cancel(_notificationId);
      }, onDone: () async {
        if (!mounted) return;
        // Sanity check: NewPipe sometimes hands back stream URLs that 200 OK
        // but stream zero bytes (expired tokens, region blocks, etc.). Don't
        // add a phantom track to the library.
        if (_bytesReceived <= 0) {
          setState(() {
            _phase = _Phase.error;
            _errorMessage = 'Download returned no audio bytes. The stream URL is likely invalid for this video.';
          });
          _notifier.cancel(_notificationId);
          return;
        }
        setState(() => _phase = _Phase.done);
        _notifier.complete(
          id: _notificationId,
          title: _videoTitle(),
          channel: _videoChannel(),
        );
        // Pull the thumbnail in the background. Track gets added either way.
        final thumb = await _downloader.downloadThumbnail(v);
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          widget.onComplete(
            YoutubeDownloader.buildTrack(v, path, _bytesReceived, thumbnailPath: thumb),
          );
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = e.toString();
      });
      _notifier.cancel(_notificationId);
    }
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
              progress: _progress,
              bytesReceived: _bytesReceived,
              totalBytes: _totalBytes,
              resolved: _resolved,
              errorMessage: _errorMessage,
              url: widget.url,
              onDownload: _startDownload,
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
  final double progress;
  final int bytesReceived;
  final int totalBytes;
  final ResolvedVideo? resolved;
  final String? errorMessage;
  final String url;
  final VoidCallback onDownload;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  const _Sheet({
    required this.phase,
    required this.progress,
    required this.bytesReceived,
    required this.totalBytes,
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
                    _Phase.done => 'Saved',
                    _Phase.error => 'Couldn\'t save',
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
          if (phase == _Phase.downloading)
            _Progress(progress: progress, bytesReceived: bytesReceived, totalBytes: totalBytes),
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
              _Phase.downloading => SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(color: AuroraTheme.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                    ),
                    child: Text(
                      'Cancel',
                      style: AuroraTheme.body(size: 13, weight: FontWeight.w600, color: AuroraTheme.muted),
                    ),
                  ),
                ),
              _Phase.done => Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AuroraTheme.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '✓ Added to your library',
                    style: AuroraTheme.body(size: 14, weight: FontWeight.w700, color: AuroraTheme.accent),
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
                if (phase == _Phase.done)
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: AuroraTheme.accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 16, color: AuroraTheme.onAccent),
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

class _Progress extends StatefulWidget {
  final double progress;
  final int bytesReceived;
  final int totalBytes;
  const _Progress({required this.progress, required this.bytesReceived, required this.totalBytes});

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final indeterminate = widget.totalBytes <= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                indeterminate ? '${_mb(widget.bytesReceived)} MB' : '${(widget.progress * 100).round()}%',
                style: AuroraTheme.mono(size: 12, weight: FontWeight.w700, color: AuroraTheme.accent),
              ),
              Text(
                indeterminate
                    ? 'Downloading…'
                    : '${_mb(widget.bytesReceived)} / ${_mb(widget.totalBytes)} MB',
                style: AuroraTheme.mono(size: 12, color: AuroraTheme.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: indeterminate
                  ? LinearProgressIndicator(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(AuroraTheme.accent),
                    )
                  : Stack(
                      children: [
                        Container(color: Colors.white.withValues(alpha: 0.08)),
                        FractionallySizedBox(
                          widthFactor: widget.progress,
                          child: const DecoratedBox(decoration: BoxDecoration(gradient: AuroraTheme.accentGradient)),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AuroraTheme.accent.withValues(alpha: 0.4 + _pulse.value * 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Downloading · continues in the background',
                style: AuroraTheme.body(size: 11, color: AuroraTheme.dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
