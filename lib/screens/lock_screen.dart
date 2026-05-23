import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../theme/aurora_theme.dart';
import '../widgets/status_bar.dart';
import '../widgets/thumbnail.dart';
import '../widgets/back15_icon.dart';

class LockScreen extends StatelessWidget {
  final Track track;
  final bool playing;
  final double progress;
  final VoidCallback onTogglePlay;
  final VoidCallback onDismiss;

  const LockScreen({
    super.key,
    required this.track,
    required this.playing,
    required this.progress,
    required this.onTogglePlay,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final elapsed = (progress * track.duration).floor();
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF050507), Color(0xFF0C0A14)],
            ),
          ),
        ),
        // Blurred color halo
        Positioned.fill(
          child: IgnorePointer(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Opacity(
                opacity: 0.45,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.4),
                      radius: 0.7,
                      colors: [track.color1, Colors.transparent],
                      stops: const [0.0, 0.60],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StatusBar(color: Colors.white),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
              child: Column(
                children: [
                  Text(
                    'Saturday, May 23',
                    style: AuroraTheme.body(size: 13, weight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '9:41',
                    style: AuroraTheme.body(size: 82, weight: FontWeight.w200, color: Colors.white, letterSpacing: -3, height: 1.0),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 20, 10, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C22).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                gradient: AuroraTheme.accentGradient,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'P',
                                style: AuroraTheme.display(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: AuroraTheme.onAccent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'PODCASTR · NOW',
                              style: AuroraTheme.body(
                                size: 11,
                                weight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.55),
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            SquareArt(track: track, size: 58, radius: 10),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AuroraTheme.body(size: 14, weight: FontWeight.w600, color: Colors.white),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.channel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AuroraTheme.body(size: 12, color: Colors.white.withValues(alpha: 0.55)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 3,
                            child: Stack(
                              children: [
                                Container(color: Colors.white.withValues(alpha: 0.14)),
                                FractionallySizedBox(
                                  widthFactor: progress,
                                  child: Container(color: AuroraTheme.accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(elapsed),
                              style: AuroraTheme.mono(size: 10, color: Colors.white.withValues(alpha: 0.55)),
                            ),
                            Text(
                              '-${formatDuration(track.duration - elapsed)}',
                              style: AuroraTheme.mono(size: 10, color: Colors.white.withValues(alpha: 0.55)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            IconButton(
                              onPressed: () {},
                              icon: const SkipIcon(seconds: 15, forward: false, size: 30, color: Colors.white),
                              iconSize: 30,
                            ),
                            IconButton(
                              onPressed: onTogglePlay,
                              icon: Icon(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 38,
                                color: Colors.white,
                              ),
                              iconSize: 38,
                            ),
                            IconButton(
                              onPressed: () {},
                              icon: const SkipIcon(seconds: 30, forward: true, size: 30, color: Colors.white),
                              iconSize: 30,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Center(
                child: TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: 0.6)),
                  child: Text(
                    '↑ Swipe to open Podcastr',
                    style: AuroraTheme.body(size: 13, color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
