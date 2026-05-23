import 'package:flutter/material.dart';
import '../theme/aurora_theme.dart';

class StatusBar extends StatelessWidget {
  final Color color;
  const StatusBar({super.key, this.color = AuroraTheme.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('9:41', style: AuroraTheme.body(size: 13, weight: FontWeight.w600, color: color, letterSpacing: 0.2)),
            Row(
              children: [
                Icon(Icons.wifi_rounded, size: 14, color: color),
                const SizedBox(width: 6),
                CustomPaint(size: const Size(22, 11), painter: _BatteryPainter(color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final Color color;
  _BatteryPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fill = Paint()..color = color;
    final tipFill = Paint()..color = color.withValues(alpha: 0.6);
    final body = RRect.fromLTRBR(0.5, 0.5, 18.5, 10.5, const Radius.circular(2));
    canvas.drawRRect(body, stroke);
    final inner = RRect.fromLTRBR(2, 2, 15, 9, const Radius.circular(1));
    canvas.drawRRect(inner, fill);
    final tip = RRect.fromLTRBR(19.5, 3.5, 21.5, 7.5, const Radius.circular(0.5));
    canvas.drawRRect(tip, tipFill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
