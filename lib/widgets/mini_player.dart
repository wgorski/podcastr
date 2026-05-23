import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../theme/aurora_theme.dart';
import 'thumbnail.dart';

/// Docked mini-player. Tap to expand into the full Now Playing screen.
/// Caller is responsible for positioning (typically a `Positioned` in a Stack).
class MiniPlayer extends StatelessWidget {
  final Track track;
  final bool playing;
  final double progress;
  final VoidCallback onTogglePlay;
  final VoidCallback onExpand;
  final VoidCallback onNext;
  const MiniPlayer({
    super.key,
    required this.track,
    required this.playing,
    required this.progress,
    required this.onTogglePlay,
    required this.onExpand,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onExpand,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AuroraTheme.surface2.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AuroraTheme.border2, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.50),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(height: 2, color: AuroraTheme.accent),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      SquareArt(track: track, size: 42, radius: 8),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AuroraTheme.body(size: 13, weight: FontWeight.w600),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              track.channel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AuroraTheme.body(size: 11, color: AuroraTheme.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onTogglePlay,
                        icon: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 22,
                          color: AuroraTheme.text,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      ),
                      IconButton(
                        onPressed: onNext,
                        icon: const Icon(Icons.skip_next_rounded, size: 20, color: AuroraTheme.muted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
