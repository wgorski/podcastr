import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The Podcastr sonar mark — corner-anchored source dot with three radiating
/// quarter-arcs. Matches `Podcastr-handoff/podcastr/project/logo.html`
/// (viewBox 200×200, arcs at radii 40/80/120 with opacities 1.0/0.75/0.45,
/// stroke width 18, round caps).
class SonarMark extends StatelessWidget {
  /// Brand cream from the handoff palette.
  static const brandCream = Color(0xFFF5F1EC);

  /// Brand coral from the handoff palette.
  static const brandCoral = Color(0xFFE8845A);

  /// Brand ink from the handoff palette.
  static const brandInk = Color(0xFF0E0B0A);

  final double size;
  final Color arcColor;
  final Color dotColor;

  const SonarMark({
    super.key,
    required this.size,
    this.arcColor = brandCream,
    this.dotColor = brandCoral,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SonarPainter(arcColor: arcColor, dotColor: dotColor),
      ),
    );
  }
}

class _SonarPainter extends CustomPainter {
  final Color arcColor;
  final Color dotColor;

  _SonarPainter({required this.arcColor, required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200);

    const center = Offset(40, 160);
    const strokeWidth = 18.0;
    const arcs = <(double radius, double opacity)>[
      (40, 1.0),
      (80, 0.75),
      (120, 0.45),
    ];

    for (final (radius, opacity) in arcs) {
      final paint = Paint()
        ..color = arcColor.withValues(alpha: arcColor.a * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi / 2,
        false,
        paint,
      );
    }

    canvas.drawCircle(center, 18, Paint()..color = dotColor);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SonarPainter old) =>
      old.arcColor != arcColor || old.dotColor != dotColor;
}
