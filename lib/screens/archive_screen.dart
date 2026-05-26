import 'package:flutter/material.dart';
import '../models/track.dart';
import '../theme/aurora_theme.dart';
import '../widgets/thumbnail.dart';

/// Read-only list of archived tracks, sorted by download time (newest first).
/// The only mutating action is "Remove permanently" — that's the spec.
class ArchiveScreen extends StatelessWidget {
  final List<Track> tracks;
  final VoidCallback onClose;
  final Future<void> Function(Track) onDeletePermanently;

  const ArchiveScreen({
    super.key,
    required this.tracks,
    required this.onClose,
    required this.onDeletePermanently,
  });

  List<Track> get _sorted {
    final list = [...tracks];
    list.sort((a, b) {
      final av = a.downloadedAtMs ?? 0;
      final bv = b.downloadedAtMs ?? 0;
      return bv.compareTo(av);
    });
    return list;
  }

  Future<void> _confirmDelete(BuildContext context, Track t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuroraTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove from archive?',
          style: AuroraTheme.display(size: 18, weight: FontWeight.w700, letterSpacing: -0.3),
        ),
        content: Text(
          'This permanently deletes "${t.title}" and its audio file.',
          style: AuroraTheme.body(size: 13, color: AuroraTheme.muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AuroraTheme.body(size: 13, weight: FontWeight.w600, color: AuroraTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: AuroraTheme.body(
                size: 13,
                weight: FontWeight.w700,
                color: const Color(0xFFFF6E80),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await onDeletePermanently(t);
  }

  @override
  Widget build(BuildContext context) {
    final list = _sorted;
    return Container(
      color: AuroraTheme.bg,
      child: DecoratedBox(
        decoration: AuroraTheme.backgroundDecoration,
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: AuroraTheme.text, size: 20),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Archive',
                    style: AuroraTheme.display(
                        size: 18, weight: FontWeight.w700, letterSpacing: -0.3),
                  ),
                  const Spacer(),
                  if (list.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${list.length}',
                        style: AuroraTheme.mono(
                            size: 12, weight: FontWeight.w700, color: AuroraTheme.muted),
                      ),
                    ),
                ],
              ),
            ),
            if (list.isEmpty)
              const Expanded(child: _EmptyArchive())
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final t = list[i];
                    return _ArchiveRow(
                      track: t,
                      onDelete: () => _confirmDelete(context, t),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  final Track track;
  final VoidCallback onDelete;
  const _ArchiveRow({required this.track, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AuroraTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuroraTheme.border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      child: Row(
        children: [
          SquareArt(track: track, size: 56, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AuroraTheme.body(size: 14, weight: FontWeight.w700, height: 1.25),
                ),
                const SizedBox(height: 4),
                Text(
                  track.channel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuroraTheme.body(size: 12, color: AuroraTheme.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitleFor(track),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuroraTheme.mono(size: 10, color: AuroraTheme.dim),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove permanently',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFFF6E80), size: 22),
          ),
        ],
      ),
    );
  }

  String _subtitleFor(Track t) {
    final dur = formatShort(t.duration);
    final ms = t.downloadedAtMs;
    if (ms == null) return dur;
    final downloaded = _relativeTime(DateTime.fromMillisecondsSinceEpoch(ms));
    return '$dur · downloaded $downloaded';
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inDays >= 365) {
      final y = diff.inDays ~/ 365;
      return '${y}y ago';
    }
    if (diff.inDays >= 30) {
      final m = diff.inDays ~/ 30;
      return '${m}mo ago';
    }
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AuroraTheme.accentSoft,
                shape: BoxShape.circle,
                border: Border.all(color: AuroraTheme.border2, width: 1),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 28, color: AuroraTheme.accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Nothing archived yet',
              style: AuroraTheme.display(size: 20, weight: FontWeight.w700, letterSpacing: -0.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Long-press a track and choose "Archive" to move it out of the library without deleting the file.',
              style: AuroraTheme.body(size: 13, color: AuroraTheme.muted, height: 1.45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
