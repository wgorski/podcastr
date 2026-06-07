import 'dart:async';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/aurora_theme.dart';
import 'waveform_scrubber.dart';

/// Wraps [WaveformScrubber] and shows a transient "back to where I was" pill in
/// the top-right corner after the user seeks *via the waveform*. Tapping the
/// pill returns playback to the position the user was listening at before the
/// (possibly accidental) scrub. The pill appears for 5 seconds, then fades.
///
/// The pill is armed only by waveform interaction — the now-playing screen's
/// skip buttons call `onSeek` directly and bypass this widget, so they never
/// trigger it. Repeated taps/drags within the 5 s window keep the *original*
/// listening spot and only refresh the timer.
class UndoableWaveform extends StatefulWidget {
  final List<double> bars;
  final double progress;

  /// Track length in seconds, used to format the destination time label.
  final int duration;
  final ValueChanged<double> onSeek;

  const UndoableWaveform({
    super.key,
    required this.bars,
    required this.progress,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<UndoableWaveform> createState() => _UndoableWaveformState();
}

class _UndoableWaveformState extends State<UndoableWaveform> {
  static const _window = Duration(seconds: 5);

  /// Progress fraction to return to. Null means "not armed".
  double? _undoFraction;
  String _undoLabel = '';
  bool _showUndo = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleSeek(double p) {
    // Capture the pre-scrub spot only when not already armed. A continuous drag
    // fires this many times; capturing once preserves the original listening
    // spot (the same holds for a second tap within the window).
    if (_undoFraction == null) {
      final frac = widget.progress.clamp(0.0, 1.0).toDouble();
      _undoFraction = frac;
      _undoLabel = formatDuration((frac * widget.duration).floor());
    }
    widget.onSeek(p);
    setState(() => _showUndo = true);
    _timer?.cancel();
    _timer = Timer(_window, () {
      if (!mounted) return;
      setState(() => _showUndo = false);
    });
  }

  void _undo() {
    final target = _undoFraction;
    if (target == null) return;
    _timer?.cancel();
    widget.onSeek(target);
    setState(() {
      _showUndo = false;
      _undoFraction = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        WaveformScrubber(
          bars: widget.bars,
          progress: widget.progress,
          onSeek: _handleSeek,
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_showUndo,
            child: AnimatedOpacity(
              opacity: _showUndo ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              onEnd: () {
                // After the fade-out completes, drop the anchor so the next
                // scrub captures a fresh listening spot.
                if (!_showUndo && _undoFraction != null) {
                  setState(() => _undoFraction = null);
                }
              },
              child: _UndoPill(label: _undoLabel, onTap: _undo),
            ),
          ),
        ),
      ],
    );
  }
}

class _UndoPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _UndoPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
          decoration: BoxDecoration(
            color: AuroraTheme.accentSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AuroraTheme.border2, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.undo_rounded, size: 15, color: AuroraTheme.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: AuroraTheme.mono(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AuroraTheme.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
