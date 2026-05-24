import 'package:flutter/material.dart';
import '../theme/aurora_theme.dart';

/// Three bars rising/falling out of phase + a "PLAYING / FINISHED / PAUSED"
/// label. Mirrors the equalizer1/2/3 keyframes in index.html.
class EqualizerBadge extends StatefulWidget {
  final bool playing;
  final bool finished;
  const EqualizerBadge({
    super.key,
    required this.playing,
    this.finished = false,
  });

  @override
  State<EqualizerBadge> createState() => _EqualizerBadgeState();
}

class _EqualizerBadgeState extends State<EqualizerBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Bar(c: _c, kind: 1, playing: widget.playing),
          const SizedBox(width: 3),
          _Bar(c: _c, kind: 2, playing: widget.playing),
          const SizedBox(width: 3),
          _Bar(c: _c, kind: 3, playing: widget.playing),
          const SizedBox(width: 5),
          Text(
            widget.playing
                ? 'PLAYING'
                : (widget.finished ? 'FINISHED' : 'PAUSED'),
            style: AuroraTheme.body(size: 10, weight: FontWeight.w700, color: AuroraTheme.accent, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final AnimationController c;
  final int kind;
  final bool playing;
  const _Bar({required this.c, required this.kind, required this.playing});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final t = c.value;
        // Each kind oscillates between low/high values like equalizer1/2/3.
        final low = switch (kind) { 1 => 0.30, 2 => 0.80, _ => 0.50 };
        final high = switch (kind) { 1 => 0.90, 2 => 0.40, _ => 1.00 };
        // 0→0.5→1 mapping for low→high→low
        final phase = (t < 0.5) ? t * 2 : (1 - t) * 2;
        final h = playing ? (low + (high - low) * phase) : low;
        // Convert fraction to actual pixel height in a 12-px slot.
        return Container(
          width: 2,
          height: 12 * h,
          color: AuroraTheme.accent,
        );
      },
    );
  }
}
