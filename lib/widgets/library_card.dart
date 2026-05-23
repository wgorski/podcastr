import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/youtube_downloader.dart';
import '../theme/aurora_theme.dart';
import 'thumbnail.dart';
import 'equalizer.dart';

/// Aurora variant: title overlaid on the thumbnail, channel + meta line below.
class LibraryCard extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final VoidCallback onLongPress;
  /// Live progress for downloads. Only consulted when
  /// `track.status == TrackStatus.downloading`. Pass null otherwise.
  final ValueListenable<DownloadProgress?>? downloadProgress;
  const LibraryCard({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onOpen,
    required this.onPlay,
    required this.onLongPress,
    this.downloadProgress,
  });

  bool get _isDownloading => track.status == TrackStatus.downloading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AuroraTheme.cardRadius),
          color: AuroraTheme.surface,
          border: Border.all(color: AuroraTheme.border, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AuroraTheme.cardRadius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Thumbnail(track: track, radius: AuroraTheme.artRadius),
                  // Gradient + title overlay (Aurora variant)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.transparent, Color(0xD9000000)],
                            stops: [0.0, 0.40, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 70,
                    bottom: 14,
                    child: Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AuroraTheme.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.25,
                        letterSpacing: -0.2,
                      ).copyWith(
                        shadows: const [Shadow(color: Color(0x80000000), offset: Offset(0, 2), blurRadius: 8)],
                      ),
                    ),
                  ),
                  if (isCurrent && track.status == TrackStatus.ready)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: EqualizerBadge(playing: isPlaying),
                    ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _StatusBadge(
                      track: track,
                      isPlaying: isPlaying,
                      onPlay: onPlay,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: _MetaRow(
                  track: track,
                  downloadProgress: _isDownloading ? downloadProgress : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final Track track;
  final ValueListenable<DownloadProgress?>? downloadProgress;
  const _MetaRow({required this.track, required this.downloadProgress});

  @override
  Widget build(BuildContext context) {
    if (track.status == TrackStatus.downloading) {
      return ValueListenableBuilder<DownloadProgress?>(
        valueListenable: downloadProgress ?? const _NullProgress(),
        builder: (context, p, _) => _DownloadingMeta(progress: p),
      );
    }
    if (track.status == TrackStatus.failed) {
      return Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 14, color: Color(0xFFFF6E80)),
          const SizedBox(width: 6),
          Text(
            'Failed · tap to retry',
            style: AuroraTheme.body(
              size: 12,
              weight: FontWeight.w600,
              color: const Color(0xFFFF6E80),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Text(
          track.channel,
          style: AuroraTheme.body(size: 12, weight: FontWeight.w600, color: AuroraTheme.text),
        ),
        const SizedBox(width: 8),
        const _Dot(),
        const SizedBox(width: 8),
        Text(track.size, style: AuroraTheme.body(size: 12, color: AuroraTheme.muted)),
        const SizedBox(width: 8),
        const _Dot(),
        const SizedBox(width: 8),
        Text(track.addedAt, style: AuroraTheme.body(size: 12, color: AuroraTheme.muted)),
      ],
    );
  }
}

class _DownloadingMeta extends StatelessWidget {
  final DownloadProgress? progress;
  const _DownloadingMeta({required this.progress});

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final received = progress?.bytesReceived ?? 0;
    final total = progress?.totalBytes ?? 0;
    final indeterminate = total <= 0;
    final pct = indeterminate ? null : (progress!.fraction * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              indeterminate ? 'Downloading…' : '$pct%',
              style: AuroraTheme.mono(
                size: 11,
                weight: FontWeight.w700,
                color: AuroraTheme.accent,
              ),
            ),
            Text(
              indeterminate
                  ? '${_mb(received)} MB'
                  : '${_mb(received)} / ${_mb(total)} MB',
              style: AuroraTheme.mono(size: 11, color: AuroraTheme.muted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            child: indeterminate
                ? LinearProgressIndicator(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor:
                        const AlwaysStoppedAnimation(AuroraTheme.accent),
                  )
                : Stack(
                    children: [
                      Container(color: Colors.white.withValues(alpha: 0.08)),
                      FractionallySizedBox(
                        widthFactor: progress!.fraction,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(gradient: AuroraTheme.accentGradient),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onPlay;
  const _StatusBadge({
    required this.track,
    required this.isPlaying,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    switch (track.status) {
      case TrackStatus.downloading:
        return _DownloadingIndicator();
      case TrackStatus.failed:
        return _FailedBadge();
      case TrackStatus.ready:
        return _PlayButton(isPlaying: isPlaying, onPlay: onPlay);
    }
  }
}

class _DownloadingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.6),
        border: Border.all(
          color: AuroraTheme.accent.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(AuroraTheme.accent),
        ),
      ),
    );
  }
}

class _FailedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x33FF6E80),
        border: Border.all(color: const Color(0xFFFF6E80), width: 1),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.refresh_rounded,
        size: 22,
        color: Color(0xFFFF6E80),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlay;
  const _PlayButton({required this.isPlaying, required this.onPlay});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPlay,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPlaying ? AuroraTheme.accent : Colors.black.withValues(alpha: 0.6),
            border: Border.all(
              color: isPlaying ? AuroraTheme.accent : Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: isPlaying ? AuroraTheme.onAccent : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(color: AuroraTheme.dim, shape: BoxShape.circle),
    );
  }
}

class _NullProgress extends ValueListenable<DownloadProgress?> {
  const _NullProgress();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  DownloadProgress? get value => null;
}
