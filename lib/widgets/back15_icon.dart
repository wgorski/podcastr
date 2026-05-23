import 'package:flutter/material.dart';

/// Circular-arrow + "15" / "30" inset — Flutter's Material icons don't ship a
/// back-15, so we composite Icons.replay with a numeric overlay.
class SkipIcon extends StatelessWidget {
  final int seconds;
  final bool forward;
  final double size;
  final Color color;
  const SkipIcon({
    super.key,
    required this.seconds,
    required this.forward,
    this.size = 28,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(
            flipX: forward,
            child: Icon(Icons.replay_rounded, size: size, color: color),
          ),
          Padding(
            padding: EdgeInsets.only(top: size * 0.13),
            child: Text(
              '$seconds',
              style: TextStyle(
                fontSize: size * 0.30,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
