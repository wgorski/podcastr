import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../services/youtube_downloader.dart';
import '../theme/aurora_theme.dart';
import '../widgets/thumbnail.dart';
import '../widgets/waveform_scrubber.dart';
import '../widgets/back15_icon.dart';

class NowPlayingScreen extends StatelessWidget {
  final Track track;
  final bool playing;
  final double progress;
  final double speed;
  final Duration? sleepRemaining;
  final VoidCallback onTogglePlay;
  final VoidCallback onClose;
  final ValueChanged<double> onSeek;
  final VoidCallback onCycleSpeed;
  final void Function(Duration?) onPickSleepTimer;
  final VoidCallback onDelete;
  /// Live progress for downloading tracks. Ignored when status is ready.
  final ValueListenable<DownloadProgress?>? downloadProgress;
  final VoidCallback? onCancelDownload;
  final VoidCallback? onRetryDownload;
  // Swipe-down on the artwork dismisses the player back to the library.
  final void Function(DragUpdateDetails)? onArtworkVerticalDragUpdate;
  final void Function(DragEndDetails)? onArtworkVerticalDragEnd;

  const NowPlayingScreen({
    super.key,
    required this.track,
    required this.playing,
    required this.progress,
    required this.speed,
    required this.sleepRemaining,
    required this.onTogglePlay,
    required this.onClose,
    required this.onSeek,
    required this.onCycleSpeed,
    required this.onPickSleepTimer,
    required this.onDelete,
    this.downloadProgress,
    this.onCancelDownload,
    this.onRetryDownload,
    this.onArtworkVerticalDragUpdate,
    this.onArtworkVerticalDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Glow from artwork color
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1),
                  radius: 1.0,
                  colors: [track.color1.withValues(alpha: 0.33), Colors.transparent],
                  stops: const [0.0, 0.70],
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 12),
            _Header(
              track: track,
              onClose: onClose,
              onDelete: () => _confirmDelete(context),
              onShare: () => Share.share(track.shareUrl, subject: track.title),
            ),
            _Artwork(
              track: track,
              onVerticalDragUpdate: onArtworkVerticalDragUpdate,
              onVerticalDragEnd: onArtworkVerticalDragEnd,
            ),
            _TitleBlock(track: track),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                physics: track.status == TrackStatus.failed
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: _BodyForStatus(
                  track: track,
                  playing: playing,
                  progress: progress,
                  speed: speed,
                  sleepRemaining: sleepRemaining,
                  onTogglePlay: onTogglePlay,
                  onSeek: onSeek,
                  onCycleSpeed: onCycleSpeed,
                  onPickSleepTimer: onPickSleepTimer,
                  downloadProgress: downloadProgress,
                  onCancelDownload: onCancelDownload,
                  onRetryDownload: onRetryDownload,
                  onDelete: onDelete,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DeleteConfirmSheet(track: track),
    );
    if (result == true) onDelete();
  }
}

class _Header extends StatelessWidget {
  final Track track;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  const _Header({
    required this.track,
    required this.onClose,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (track.status) {
      TrackStatus.downloading => 'DOWNLOADING',
      TrackStatus.queued => 'QUEUED',
      TrackStatus.failed => 'DOWNLOAD FAILED',
      TrackStatus.ready => 'NOW PLAYING',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AuroraTheme.text, size: 28),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  style: AuroraTheme.body(
                    size: 10,
                    weight: FontWeight.w700,
                    color: track.status == TrackStatus.failed
                        ? const Color(0xFFFF6E80)
                        : AuroraTheme.muted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(track.channel, style: AuroraTheme.body(size: 12, weight: FontWeight.w600)),
              ],
            ),
          ),
          _MoreMenu(onDelete: onDelete, onShare: onShare),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final Track track;
  final void Function(DragUpdateDetails)? onVerticalDragUpdate;
  final void Function(DragEndDetails)? onVerticalDragEnd;
  const _Artwork({
    required this.track,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 14, 32, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: AspectRatio(
            aspectRatio: 1,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: onVerticalDragUpdate,
              onVerticalDragEnd: onVerticalDragEnd,
              child: LayoutBuilder(
                builder: (context, c) => Stack(
                  children: [
                    SquareArt(track: track, size: c.maxWidth, radius: 22),
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: track.color2.withValues(alpha: 0.33),
                              blurRadius: 80,
                              offset: const Offset(0, 30),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  final Track track;
  const _TitleBlock({required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 10, 26, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.title,
            style: AuroraTheme.display(size: 20, weight: FontWeight.w700, letterSpacing: -0.4)
                .copyWith(height: 1.15),
          ),
          const SizedBox(height: 6),
          Text(
            track.channel,
            style: AuroraTheme.body(size: 13, weight: FontWeight.w600, color: AuroraTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _BodyForStatus extends StatelessWidget {
  final Track track;
  final bool playing;
  final double progress;
  final double speed;
  final Duration? sleepRemaining;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeek;
  final VoidCallback onCycleSpeed;
  final void Function(Duration?) onPickSleepTimer;
  final ValueListenable<DownloadProgress?>? downloadProgress;
  final VoidCallback? onCancelDownload;
  final VoidCallback? onRetryDownload;
  final VoidCallback onDelete;

  const _BodyForStatus({
    required this.track,
    required this.playing,
    required this.progress,
    required this.speed,
    required this.sleepRemaining,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onCycleSpeed,
    required this.onPickSleepTimer,
    required this.downloadProgress,
    required this.onCancelDownload,
    required this.onRetryDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    switch (track.status) {
      case TrackStatus.downloading:
        return _DownloadingBody(
          progress: downloadProgress ?? const _NullProgress(),
          onCancel: onCancelDownload,
        );
      case TrackStatus.queued:
        return _QueuedBody(onCancel: onCancelDownload);
      case TrackStatus.failed:
        return _FailedBody(
          errorMessage: track.errorMessage ?? 'Unknown error',
          onRetry: onRetryDownload,
          onDelete: onDelete,
        );
      case TrackStatus.ready:
        return _ReadyBody(
          track: track,
          playing: playing,
          progress: progress,
          speed: speed,
          sleepRemaining: sleepRemaining,
          onTogglePlay: onTogglePlay,
          onSeek: onSeek,
          onCycleSpeed: onCycleSpeed,
          onPickSleepTimer: onPickSleepTimer,
        );
    }
  }
}

class _ReadyBody extends StatelessWidget {
  final Track track;
  final bool playing;
  final double progress;
  final double speed;
  final Duration? sleepRemaining;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeek;
  final VoidCallback onCycleSpeed;
  final void Function(Duration?) onPickSleepTimer;
  const _ReadyBody({
    required this.track,
    required this.playing,
    required this.progress,
    required this.speed,
    required this.sleepRemaining,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onCycleSpeed,
    required this.onPickSleepTimer,
  });

  @override
  Widget build(BuildContext context) {
    final bars = waveformBars(track.id, count: 56);
    final elapsed = (progress * track.duration).floor();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 6, 26, 0),
          child: Column(
            children: [
              WaveformScrubber(bars: bars, progress: progress, onSeek: onSeek),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(elapsed),
                    style: AuroraTheme.mono(
                      size: 11,
                      weight: FontWeight.w500,
                      color: AuroraTheme.muted,
                    ),
                  ),
                  Text(
                    '-${formatDuration(track.duration - elapsed)}',
                    style: AuroraTheme.mono(
                      size: 11,
                      weight: FontWeight.w500,
                      color: AuroraTheme.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _SpeedPill(speed: speed, onTap: onCycleSpeed),
              IconButton(
                onPressed: () => onSeek((progress - 15 / track.duration).clamp(0.0, 1.0)),
                icon: const SkipIcon(seconds: 15, forward: false, color: AuroraTheme.text),
                iconSize: 28,
              ),
              _PlayButton(playing: playing, onTap: onTogglePlay),
              IconButton(
                onPressed: () => onSeek((progress + 30 / track.duration).clamp(0.0, 1.0)),
                icon: const SkipIcon(seconds: 30, forward: true, color: AuroraTheme.text),
                iconSize: 28,
              ),
              _SleepControl(
                remaining: sleepRemaining,
                onTap: () => _openSleepSheet(context, sleepRemaining != null, onPickSleepTimer, track, progress),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QueuedBody extends StatelessWidget {
  final VoidCallback? onCancel;
  const _QueuedBody({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 18, color: AuroraTheme.muted),
              const SizedBox(width: 8),
              Text(
                'Waiting for another download to finish.',
                style: AuroraTheme.body(size: 13, color: AuroraTheme.muted, height: 1.4),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.stop_circle_outlined,
                  size: 18, color: Color(0xFFFF6E80)),
              label: Text(
                'Cancel',
                style: AuroraTheme.body(
                  size: 14,
                  weight: FontWeight.w700,
                  color: const Color(0xFFFF6E80),
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0x66FF6E80)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                backgroundColor: const Color(0x14FF6E80),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadingBody extends StatelessWidget {
  final ValueListenable<DownloadProgress?> progress;
  final VoidCallback? onCancel;
  const _DownloadingBody({required this.progress, required this.onCancel});

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<DownloadProgress?>(
            valueListenable: progress,
            builder: (context, p, _) {
              final received = p?.bytesReceived ?? 0;
              final total = p?.totalBytes ?? 0;
              final indeterminate = total <= 0;
              final pct = indeterminate ? null : (p!.fraction * 100).round();
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        indeterminate ? 'Downloading…' : '$pct%',
                        style: AuroraTheme.mono(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AuroraTheme.accent,
                        ),
                      ),
                      Text(
                        indeterminate
                            ? '${_mb(received)} MB'
                            : '${_mb(received)} / ${_mb(total)} MB',
                        style: AuroraTheme.mono(size: 12, color: AuroraTheme.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: indeterminate
                          ? LinearProgressIndicator(
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              valueColor:
                                  const AlwaysStoppedAnimation(AuroraTheme.accent),
                            )
                          : LayoutBuilder(
                              builder: (context, c) => Stack(
                                children: [
                                  SizedBox(
                                    width: c.maxWidth,
                                    height: c.maxHeight,
                                    child: ColoredBox(
                                      color: Colors.white.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  SizedBox(
                                    width: c.maxWidth * p!.fraction,
                                    height: c.maxHeight,
                                    child: const DecoratedBox(
                                      decoration:
                                          BoxDecoration(gradient: AuroraTheme.accentGradient),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.stop_circle_outlined,
                  size: 18, color: Color(0xFFFF6E80)),
              label: Text(
                'Cancel download',
                style: AuroraTheme.body(
                  size: 14,
                  weight: FontWeight.w700,
                  color: const Color(0xFFFF6E80),
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0x66FF6E80)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                backgroundColor: const Color(0x14FF6E80),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedBody extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback onDelete;
  const _FailedBody({
    required this.errorMessage,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x14FF6E80),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x33FF6E80), width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 18, color: Color(0xFFFF6E80)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: AuroraTheme.body(
                      size: 12,
                      color: const Color(0xFFFFB9C2),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded,
                  size: 18, color: AuroraTheme.onAccent),
              label: Text(
                'Retry download',
                style: AuroraTheme.body(
                  size: 14,
                  weight: FontWeight.w700,
                  color: AuroraTheme.onAccent,
                ),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: AuroraTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'Delete',
                style: AuroraTheme.body(
                  size: 13,
                  weight: FontWeight.w600,
                  color: AuroraTheme.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openSleepSheet(
  BuildContext context,
  bool active,
  void Function(Duration?) onPick,
  Track track,
  double progress,
) async {
  final selection = await showModalBottomSheet<_SleepChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SleepTimerSheet(active: active),
  );
  if (selection == null) return;
  switch (selection.kind) {
    case _SleepKind.off:
      onPick(null);
      break;
    case _SleepKind.duration:
      onPick(selection.duration);
      break;
    case _SleepKind.endOfClip:
      final remainingSec = (track.duration - track.duration * progress).round();
      onPick(Duration(seconds: remainingSec.clamp(1, 24 * 3600)));
      break;
  }
}

class _PlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayButton({required this.playing, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AuroraTheme.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AuroraTheme.accent.withValues(alpha: 0.27), blurRadius: 24, offset: const Offset(0, 10)),
            ],
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 32,
            color: AuroraTheme.onAccent,
          ),
        ),
      ),
    );
  }
}

class _SpeedPill extends StatelessWidget {
  final double speed;
  final VoidCallback onTap;
  const _SpeedPill({required this.speed, required this.onTap});

  String _fmt() => speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : speed.toString();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minWidth: 50),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AuroraTheme.accentSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          '${_fmt()}×',
          style: AuroraTheme.mono(size: 13, weight: FontWeight.w700, color: AuroraTheme.accent),
        ),
      ),
    );
  }
}

class _SleepControl extends StatelessWidget {
  final Duration? remaining;
  final VoidCallback onTap;
  const _SleepControl({required this.remaining, required this.onTap});

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final active = remaining != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bedtime_rounded,
              color: active ? AuroraTheme.accent : AuroraTheme.muted,
              size: 22,
            ),
            if (active) ...[
              const SizedBox(height: 2),
              Text(
                _fmt(remaining!),
                style: AuroraTheme.mono(size: 10, weight: FontWeight.w700, color: AuroraTheme.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _SleepKind { off, duration, endOfClip }

class _SleepChoice {
  final _SleepKind kind;
  final Duration? duration;
  const _SleepChoice.off()
      : kind = _SleepKind.off,
        duration = null;
  const _SleepChoice.duration(Duration d)
      : kind = _SleepKind.duration,
        duration = d;
  const _SleepChoice.endOfClip()
      : kind = _SleepKind.endOfClip,
        duration = null;
}

class _SleepTimerSheet extends StatelessWidget {
  final bool active;
  const _SleepTimerSheet({required this.active});

  @override
  Widget build(BuildContext context) {
    final items = <(_SleepChoice, String, String?)>[
      (const _SleepChoice.duration(Duration(minutes: 5)), '5 minutes', null),
      (const _SleepChoice.duration(Duration(minutes: 15)), '15 minutes', null),
      (const _SleepChoice.duration(Duration(minutes: 30)), '30 minutes', null),
      (const _SleepChoice.duration(Duration(minutes: 45)), '45 minutes', null),
      (const _SleepChoice.duration(Duration(hours: 1)), '1 hour', null),
      (const _SleepChoice.endOfClip(), 'End of clip', 'Pauses when this track finishes'),
    ];
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AuroraTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AuroraTheme.border, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bedtime_rounded, color: AuroraTheme.accent, size: 18),
                const SizedBox(width: 8),
                Text('Sleep timer',
                    style: AuroraTheme.display(size: 16, weight: FontWeight.w700, letterSpacing: -0.2)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Pause playback after the chosen interval.',
              style: AuroraTheme.body(size: 12, color: AuroraTheme.muted),
            ),
            const SizedBox(height: 8),
            for (final item in items)
              _SleepOption(
                label: item.$2,
                subtitle: item.$3,
                onTap: () => Navigator.of(context).pop(item.$1),
              ),
            if (active) ...[
              const Divider(height: 24, color: AuroraTheme.border),
              _SleepOption(
                label: 'Turn off',
                destructive: true,
                onTap: () => Navigator.of(context).pop(const _SleepChoice.off()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final VoidCallback onDelete;
  final VoidCallback onShare;
  const _MoreMenu({required this.onDelete, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AuroraTheme.text, size: 22),
      color: AuroraTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AuroraTheme.border, width: 1),
      ),
      offset: const Offset(0, 40),
      onSelected: (v) {
        if (v == 'share') onShare();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              const Icon(Icons.ios_share_rounded, size: 18, color: AuroraTheme.text),
              const SizedBox(width: 10),
              Text('Share',
                  style: AuroraTheme.body(size: 14, weight: FontWeight.w600)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFFF6E80)),
              const SizedBox(width: 10),
              Text('Delete',
                  style: AuroraTheme.body(size: 14, weight: FontWeight.w600, color: const Color(0xFFFF6E80))),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeleteConfirmSheet extends StatelessWidget {
  final Track track;
  const _DeleteConfirmSheet({required this.track});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AuroraTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AuroraTheme.border, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AuroraTheme.body(size: 15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(track.channel, style: AuroraTheme.body(size: 12, color: AuroraTheme.muted)),
            const SizedBox(height: 16),
            _ConfirmRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete from library',
              destructive: true,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            _ConfirmRow(
              icon: Icons.close_rounded,
              label: 'Cancel',
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _ConfirmRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFFF6E80) : AuroraTheme.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Text(label, style: AuroraTheme.body(size: 14, weight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _SleepOption extends StatelessWidget {
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  const _SleepOption({
    required this.label,
    this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFFF6E80) : AuroraTheme.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AuroraTheme.body(size: 14, weight: FontWeight.w600, color: color)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AuroraTheme.body(size: 11, color: AuroraTheme.muted)),
                  ],
                ],
              ),
            ),
            if (!destructive)
              const Icon(Icons.chevron_right_rounded, color: AuroraTheme.muted, size: 18),
          ],
        ),
      ),
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
