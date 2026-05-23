import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../theme/aurora_theme.dart';

/// 16:9 "video still" placeholder — gradient + procedural shapes + duration pill.
class Thumbnail extends StatelessWidget {
  final Track track;
  final double radius;
  final bool showDuration;
  const Thumbnail({
    super.key,
    required this.track,
    required this.radius,
    this.showDuration = true,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = track.thumbnailPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              Image.file(
                File(thumb),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _ProceduralArt(
                  seed: track.seed,
                  color1: track.color1,
                  color2: track.color2,
                  square: false,
                ),
              )
            else
              _ProceduralArt(
                seed: track.seed,
                color1: track.color1,
                color2: track.color2,
                square: false,
              ),
            if (showDuration)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    formatDuration(track.duration),
                    style: AuroraTheme.mono(size: 11, weight: FontWeight.w600, color: Colors.white, letterSpacing: 0.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Square (1:1) art used for the player + mini player + lock screen + share sheet.
class SquareArt extends StatelessWidget {
  final Track track;
  final double size;
  final double radius;
  final bool showShadow;
  const SquareArt({
    super.key,
    required this.track,
    required this.size,
    required this.radius,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = track.thumbnailPath;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: showShadow
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: thumb != null
            ? Image.file(
                File(thumb),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _ProceduralArt(
                  seed: track.seed,
                  color1: track.color1,
                  color2: track.color2,
                  square: true,
                ),
              )
            : _ProceduralArt(
                seed: track.seed,
                color1: track.color1,
                color2: track.color2,
                square: true,
              ),
      ),
    );
  }
}

class _ProceduralArt extends StatelessWidget {
  final int seed;
  final Color color1;
  final Color color2;
  final bool square;
  const _ProceduralArt({
    required this.seed,
    required this.color1,
    required this.color2,
    required this.square,
  });

  @override
  Widget build(BuildContext context) {
    final degrees = ((seed * 31) % 360).toDouble();
    final rad = (degrees - 90) * math.pi / 180.0;
    final cosV = math.cos(rad);
    final sinV = math.sin(rad);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-cosV, -sinV),
              end: Alignment(cosV, sinV),
              colors: [color1, color2],
            ),
          ),
        ),
        CustomPaint(painter: _ShapesPainter(seed: seed, square: square)),
      ],
    );
  }
}

class _ShapesPainter extends CustomPainter {
  final int seed;
  final bool square;
  _ShapesPainter({required this.seed, required this.square});

  @override
  void paint(Canvas canvas, Size size) {
    final s = seed;
    final r1 = (s * 7) % 100, r2 = (s * 13) % 100;
    final r3 = (s * 19) % 100, r4 = (s * 23) % 100;
    final whitePaint = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.22);
    final blackPaint = Paint()..color = const Color(0xFF000000).withValues(alpha: 0.18);
    final silhouette = Paint()..color = const Color(0xFF000000).withValues(alpha: 0.18);

    if (square) {
      final scaleX = size.width / 100.0;
      final scaleY = size.height / 100.0;
      final scale = (scaleX + scaleY) / 2.0;
      canvas.drawCircle(Offset(r1 * scaleX, r2 * scaleY), (28 + (s % 16)) * scale, whitePaint);
      canvas.drawCircle(Offset(r3 * scaleX, r4 * scaleY), (14 + (s % 10)) * scale, blackPaint);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(50 * scaleX, 60 * scaleY), width: 36 * scaleX, height: 44 * scaleY),
        silhouette,
      );
      canvas.drawCircle(Offset(50 * scaleX, 38 * scaleY), 9 * scaleX, silhouette);
    } else {
      // 160 x 90 coord space
      final scaleX = size.width / 160.0;
      final scaleY = size.height / 90.0;
      final scale = (scaleX + scaleY) / 2.0;
      canvas.drawCircle(Offset(r1 * 1.6 * scaleX, r2 * 0.9 * scaleY), (20 + (s % 18)) * scale, whitePaint);
      canvas.drawCircle(Offset(r3 * 1.6 * scaleX, r4 * 0.9 * scaleY), (12 + (s % 14)) * scale, blackPaint);
      final silWeak = Paint()..color = const Color(0xFF000000).withValues(alpha: 0.18);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(80 * scaleX, 55 * scaleY), width: 44 * scaleX, height: 56 * scaleY),
        silWeak,
      );
      canvas.drawCircle(Offset(80 * scaleX, 32 * scaleY), 10 * scaleX, silWeak);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
