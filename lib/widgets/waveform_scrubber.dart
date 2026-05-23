import 'package:flutter/material.dart';
import '../theme/aurora_theme.dart';

/// Tap-and-drag waveform scrubber. Bars to the left of the playhead get the
/// accent color; bars to the right are dimmed.
class WaveformScrubber extends StatelessWidget {
  final List<double> bars;
  final double progress;
  final ValueChanged<double> onSeek;
  const WaveformScrubber({
    super.key,
    required this.bars,
    required this.progress,
    required this.onSeek,
  });

  void _handle(BuildContext context, Offset local, double width) {
    final p = (local.dx / width).clamp(0.0, 1.0);
    onSeek(p);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _handle(context, d.localPosition, width),
          onHorizontalDragUpdate: (d) => _handle(context, d.localPosition, width),
          child: SizedBox(
            height: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (int i = 0; i < bars.length; i++) ...[
                  Expanded(
                    child: Container(
                      height: (bars[i] * 44).clamp(3, 44).toDouble(),
                      decoration: BoxDecoration(
                        color: i / bars.length < progress
                            ? AuroraTheme.accent
                            : Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (i < bars.length - 1) const SizedBox(width: 2),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
