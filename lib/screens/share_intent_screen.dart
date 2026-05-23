import 'package:flutter/material.dart';
import '../theme/aurora_theme.dart';
import '../widgets/status_bar.dart';

class ShareIntentScreen extends StatelessWidget {
  final VoidCallback onPickPodcastr;
  final VoidCallback onDismiss;
  const ShareIntentScreen({super.key, required this.onPickPodcastr, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Faux video host page
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StatusBar(color: Colors.white),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFF2A3344), Color(0xFF131722)],
                                ),
                              ),
                            ),
                            // Faint silhouette
                            CustomPaint(painter: _VideoSilhouette()),
                            Center(
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                                child: const Icon(Icons.play_arrow_rounded, size: 30, color: Colors.black),
                              ),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '41:10',
                                  style: AuroraTheme.mono(size: 11, weight: FontWeight.w600, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The Hidden Logic of Cities',
                      style: AuroraTheme.body(size: 16, weight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Wrong Turn · 124K views',
                      style: AuroraTheme.body(size: 12, color: const Color(0xFF888888)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Backdrop
          Positioned.fill(
            child: GestureDetector(
              onTap: onDismiss,
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          // Share sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: _ShareSheet(onPickPodcastr: onPickPodcastr),
          ),
        ],
      ),
    );
  }
}

class _VideoSilhouette extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: 0.40);
    final scaleX = size.width / 160;
    final scaleY = size.height / 90;
    canvas.drawOval(Rect.fromCenter(center: Offset(80 * scaleX, 55 * scaleY), width: 44 * scaleX, height: 56 * scaleY), p);
    canvas.drawCircle(Offset(80 * scaleX, 32 * scaleY), 10 * scaleX, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ShareSheet extends StatelessWidget {
  final VoidCallback onPickPodcastr;
  const _ShareSheet({required this.onPickPodcastr});

  @override
  Widget build(BuildContext context) {
    const recents = [
      ('Messages', Color(0xFF1F7C4D), Icons.message_rounded),
      ('Mail', Color(0xFF3B78D8), Icons.mail_outline_rounded),
      ('Notes', Color(0xFFBF9B3A), Icons.sticky_note_2_outlined),
      ('Drive', Color(0xFF5A5A5A), Icons.cloud_outlined),
    ];
    const apps = [
      ('Maps', Color(0xFF1C8D62)),
      ('Photos', Color(0xFFD24E4E)),
      ('Slack', Color(0xFF4A154B)),
      ('Reddit', Color(0xFFFF4500)),
      ('Files', Color(0xFF3A72C5)),
      ('Calendar', Color(0xFFE2533C)),
      ('More', Color(0xFF444444)),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AuroraTheme.surface,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        border: Border.all(color: AuroraTheme.border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Share via',
              style: AuroraTheme.body(size: 13, weight: FontWeight.w600, color: AuroraTheme.muted),
            ),
          ),
          // Recent row
          SizedBox(
            height: 86,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final r in recents)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: _AppTile(name: r.$1, bg: r.$2, icon: r.$3),
                  ),
              ],
            ),
          ),
          // App grid
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.82,
              children: [
                _PodcastrTile(onTap: onPickPodcastr),
                for (final a in apps) _AppTile(name: a.$1, bg: a.$2),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Tap Podcastr to save the audio',
              style: AuroraTheme.body(size: 12, color: AuroraTheme.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  final String name;
  final Color bg;
  final IconData? icon;
  const _AppTile({required this.name, required this.bg, this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 22)
                : Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(name, style: AuroraTheme.body(size: 11, color: AuroraTheme.muted)),
      ],
    );
  }
}

class _PodcastrTile extends StatelessWidget {
  final VoidCallback onTap;
  const _PodcastrTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AuroraTheme.accentGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AuroraTheme.accent.withValues(alpha: 0.33), blurRadius: 18, offset: const Offset(0, 8)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'P',
                  style: AuroraTheme.display(
                    size: 24,
                    weight: FontWeight.w700,
                    color: AuroraTheme.onAccent,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Podcastr',
                style: AuroraTheme.body(size: 11, weight: FontWeight.w600, color: AuroraTheme.text),
              ),
            ],
          ),
          Positioned(
            top: -2,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AuroraTheme.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'SAVE',
                style: AuroraTheme.body(size: 9, weight: FontWeight.w700, color: AuroraTheme.onAccent, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
