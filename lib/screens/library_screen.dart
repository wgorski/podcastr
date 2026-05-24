import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../services/youtube_downloader.dart';
import '../theme/aurora_theme.dart';
import '../widgets/library_card.dart';

class LibraryScreen extends StatefulWidget {
  final List<Track> tracks;
  final String? currentId;
  final bool playing;
  final void Function(Track) onOpenTrack;
  final void Function(Track) onPlay;
  final void Function(Track) onDelete;
  final Future<void> Function() onClearFinished;
  final VoidCallback onSearch;
  /// Returns the live progress listenable for a downloading track.
  /// Called only for `TrackStatus.downloading` rows.
  final ValueListenable<DownloadProgress?> Function(String trackId)?
      downloadProgressFor;

  const LibraryScreen({
    super.key,
    required this.tracks,
    required this.currentId,
    required this.playing,
    required this.onOpenTrack,
    required this.onPlay,
    required this.onDelete,
    required this.onClearFinished,
    required this.onSearch,
    this.downloadProgressFor,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Future<void> _showActions(Track t) async {
    final result = await showModalBottomSheet<_TrackAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TrackActionsSheet(track: t),
    );
    switch (result) {
      case _TrackAction.share:
        await Share.share(t.shareUrl, subject: t.title);
        break;
      case _TrackAction.delete:
        widget.onDelete(t);
        break;
      case null:
        break;
    }
  }

  Future<void> _confirmClearFinished(int count) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuroraTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear finished podcasts?',
          style: AuroraTheme.display(size: 18, weight: FontWeight.w700, letterSpacing: -0.3),
        ),
        content: Text(
          count == 1
              ? 'This will permanently delete 1 finished podcast.'
              : 'This will permanently delete $count finished podcasts.',
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
              'Delete',
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
    if (result == true) await widget.onClearFinished();
  }

  @override
  Widget build(BuildContext context) {
    final hasTracks = widget.tracks.isNotEmpty;
    final finishedCount = widget.tracks.where((t) => t.finished).length;
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8),
      child: Column(
        children: [
          // Wordmark + actions
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: AuroraTheme.accentGradient,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'P',
                    style: AuroraTheme.display(
                      size: 15,
                      weight: FontWeight.w700,
                      color: AuroraTheme.onAccent,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Text('Podcastr', style: AuroraTheme.body(size: 17, weight: FontWeight.w700, letterSpacing: -0.3)),
                const Spacer(),
                IconButton(
                  onPressed: widget.onSearch,
                  icon: const Icon(Icons.search_rounded, color: AuroraTheme.text, size: 21),
                ),
                if (finishedCount > 0)
                  IconButton(
                    onPressed: () => _confirmClearFinished(finishedCount),
                    tooltip: 'Clear finished',
                    icon: const Icon(Icons.delete_sweep_outlined, color: AuroraTheme.text, size: 21),
                  ),
              ],
            ),
          ),
          if (hasTracks) ...[
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                itemCount: widget.tracks.length,
                itemBuilder: (context, i) {
                  final t = widget.tracks[i];
                  return LibraryCard(
                    track: t,
                    isCurrent: widget.currentId == t.id,
                    isPlaying: widget.currentId == t.id && widget.playing,
                    onOpen: () => widget.onOpenTrack(t),
                    onPlay: () => widget.onPlay(t),
                    onLongPress: () => _showActions(t),
                    downloadProgress: t.status == TrackStatus.downloading
                        ? widget.downloadProgressFor?.call(t.id)
                        : null,
                  );
                },
              ),
            ),
          ] else ...[
            const Expanded(child: _EmptyState()),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              child: const Icon(Icons.share_outlined, size: 30, color: AuroraTheme.accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Your library is empty',
              style: AuroraTheme.display(size: 22, weight: FontWeight.w700, letterSpacing: -0.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Share a YouTube link to this app from the Android share sheet and the audio will appear here.',
              style: AuroraTheme.body(size: 13, color: AuroraTheme.muted, height: 1.45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _TrackAction { share, delete }

class _TrackActionsSheet extends StatelessWidget {
  final Track track;
  const _TrackActionsSheet({required this.track});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AuroraTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AuroraTheme.border, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AuroraTheme.body(size: 15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(track.channel, style: AuroraTheme.body(size: 12, color: AuroraTheme.muted)),
            const SizedBox(height: 16),
            _ActionRow(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              onTap: () => Navigator.of(context).pop(_TrackAction.share),
            ),
            const SizedBox(height: 4),
            _ActionRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete from library',
              destructive: true,
              onTap: () => Navigator.of(context).pop(_TrackAction.delete),
            ),
            const SizedBox(height: 4),
            _ActionRow(
              icon: Icons.close_rounded,
              label: 'Cancel',
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFFF6E80) : AuroraTheme.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Text(label, style: AuroraTheme.body(size: 14, weight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

