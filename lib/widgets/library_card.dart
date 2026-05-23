import 'package:flutter/material.dart';
import '../models/track.dart';
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
  const LibraryCard({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onOpen,
    required this.onPlay,
    required this.onLongPress,
  });

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
                  if (isCurrent)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: EqualizerBadge(playing: isPlaying),
                    ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _PlayButton(isPlaying: isPlaying, onPlay: onPlay),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Row(
                  children: [
                    Text(
                      track.channel,
                      style: AuroraTheme.body(size: 12, weight: FontWeight.w600, color: AuroraTheme.text),
                    ),
                    const SizedBox(width: 8),
                    _Dot(),
                    const SizedBox(width: 8),
                    Text(track.size, style: AuroraTheme.body(size: 12, color: AuroraTheme.muted)),
                    const SizedBox(width: 8),
                    _Dot(),
                    const SizedBox(width: 8),
                    Text(track.addedAt, style: AuroraTheme.body(size: 12, color: AuroraTheme.muted)),
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
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(color: AuroraTheme.dim, shape: BoxShape.circle),
    );
  }
}
