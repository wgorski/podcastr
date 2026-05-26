import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../services/youtube_downloader.dart';
import '../theme/aurora_theme.dart';
import '../widgets/library_card.dart';
import '../widgets/sonar_mark.dart';

class LibraryScreen extends StatefulWidget {
  final List<Track> tracks;
  final int archivedCount;
  final String? currentId;
  final bool playing;
  final void Function(Track) onOpenTrack;
  final void Function(Track) onPlay;
  final void Function(Track) onArchive;
  final Future<void> Function() onArchiveFinished;
  final VoidCallback onSearch;
  final VoidCallback onOpenArchive;
  final VoidCallback onOpenSettings;
  /// Returns the live progress listenable for a downloading track.
  /// Called only for `TrackStatus.downloading` rows.
  final ValueListenable<DownloadProgress?> Function(String trackId)?
      downloadProgressFor;

  const LibraryScreen({
    super.key,
    required this.tracks,
    required this.archivedCount,
    required this.currentId,
    required this.playing,
    required this.onOpenTrack,
    required this.onPlay,
    required this.onArchive,
    required this.onArchiveFinished,
    required this.onSearch,
    required this.onOpenArchive,
    required this.onOpenSettings,
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
      case _TrackAction.archive:
        widget.onArchive(t);
        break;
      case null:
        break;
    }
  }

  Future<void> _confirmArchiveFinished(int count) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuroraTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Archive finished podcasts?',
          style: AuroraTheme.display(size: 18, weight: FontWeight.w700, letterSpacing: -0.3),
        ),
        content: Text(
          count == 1
              ? 'This moves 1 finished podcast to the archive.'
              : 'This moves $count finished podcasts to the archive.',
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
              'Archive',
              style: AuroraTheme.body(
                size: 13,
                weight: FontWeight.w700,
                color: AuroraTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
    if (result == true) await widget.onArchiveFinished();
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
                const SonarMark(size: 26),
                const SizedBox(width: 10),
                Text('Podcastr', style: AuroraTheme.body(size: 17, weight: FontWeight.w700, letterSpacing: -0.3)),
                const Spacer(),
                IconButton(
                  onPressed: widget.onSearch,
                  icon: const Icon(Icons.search_rounded, color: AuroraTheme.text, size: 21),
                ),
                if (finishedCount > 0)
                  IconButton(
                    onPressed: () => _confirmArchiveFinished(finishedCount),
                    tooltip: 'Archive finished',
                    icon: const Icon(Icons.archive_outlined, color: AuroraTheme.text, size: 21),
                  ),
                if (widget.archivedCount > 0)
                  IconButton(
                    onPressed: widget.onOpenArchive,
                    tooltip: 'View archive',
                    icon: const Icon(Icons.inventory_2_outlined, color: AuroraTheme.text, size: 21),
                  ),
                IconButton(
                  onPressed: widget.onOpenSettings,
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined, color: AuroraTheme.text, size: 21),
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
              'Share a YouTube link or any article URL to this app and it\'ll appear here as audio. Articles use ElevenLabs TTS — add your key in Settings.',
              style: AuroraTheme.body(size: 13, color: AuroraTheme.muted, height: 1.45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _TrackAction { share, archive }

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
              icon: Icons.archive_outlined,
              label: 'Archive',
              onTap: () => Navigator.of(context).pop(_TrackAction.archive),
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
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const color = AuroraTheme.text;
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

