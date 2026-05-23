import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'models/track.dart';
import 'screens/download_sheet.dart';
import 'screens/library_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/search_screen.dart';
import 'services/download_notifier.dart';
import 'services/youtube_downloader.dart';
import 'state/audio_controller.dart';
import 'state/download_manager.dart';
import 'state/library_store.dart';
import 'theme/aurora_theme.dart';
import 'widgets/mini_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge with the OS status bar hidden; keep the gesture nav bar.
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: const [SystemUiOverlay.bottom],
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AuroraTheme.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // Hook the media-session foreground service. Each AudioPlayer in the app
  // will now surface a Spotify-style notification + lock-screen controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.podcastr.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationIcon: 'drawable/ic_stat_music',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    notificationColor: AuroraTheme.accent,
  );
  runApp(const PodcastrApp());
}

class PodcastrApp extends StatelessWidget {
  const PodcastrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Podcastr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AuroraTheme.bg,
        primaryColor: AuroraTheme.accent,
        colorScheme: const ColorScheme.dark(
          primary: AuroraTheme.accent,
          surface: AuroraTheme.surface,
          onPrimary: AuroraTheme.onAccent,
        ),
        splashFactory: InkRipple.splashFactory,
        textSelectionTheme: const TextSelectionThemeData(cursorColor: AuroraTheme.accent),
      ),
      home: const _PodcastrHome(),
    );
  }
}

enum _Screen { library, player, search, download, lock }

class _PodcastrHome extends StatefulWidget {
  const _PodcastrHome();

  @override
  State<_PodcastrHome> createState() => _PodcastrHomeState();
}

class _PodcastrHomeState extends State<_PodcastrHome> {
  final _store = LibraryStore();
  late final AudioController _audio = AudioController(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  late final DownloadManager _downloads = DownloadManager(
    onCompleted: _onDownloadCompleted,
    onFailed: _onDownloadFailed,
  );

  List<Track> _tracks = const [];
  _Screen _screen = _Screen.library;
  double _speed = 1.0;
  // The track currently rendered on the now-playing screen. Distinct from
  // [_audio.current] because the player screen also surfaces downloading /
  // failed tracks, which don't get loaded into the audio engine.
  Track? _viewedTrack;

  String? _pendingDownloadUrl; // URL captured from a SEND / VIEW intent
  StreamSubscription<List<SharedMediaFile>>? _intentSub;

  // Sleep timer: ticks down regardless of pause state; pauses playback at 0.
  Duration? _sleepRemaining;
  Timer? _sleepTicker;

  Track? get _current => _audio.current;
  bool get _playing => _audio.playing;
  double get _progress => _audio.progress;

  @override
  void initState() {
    super.initState();
    DownloadActionRouter.instance
      ..bind()
      ..onCancel = _cancelDownloadFromNotification;
    _load();
    _wireShareIntent();
  }

  Future<void> _load() async {
    final tracks = await _store.load();
    if (!mounted) return;
    setState(() => _tracks = tracks);
    // Auto-load the first *ready* track so the mini-player has something
    // to bind to.
    Track? firstReady;
    for (final t in tracks) {
      if (t.status == TrackStatus.ready) {
        firstReady = t;
        break;
      }
    }
    if (firstReady != null) {
      await _audio.load(firstReady);
    }
  }

  void _wireShareIntent() {
    // Cold start: app was launched from a share/view intent.
    ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedMedia);
    // While running: another share comes in.
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(_handleSharedMedia);
  }

  void _handleSharedMedia(List<SharedMediaFile> items) {
    final url = _extractYoutubeUrl(items);
    if (url == null) return;
    setState(() {
      _pendingDownloadUrl = url;
      _screen = _Screen.download;
    });
    ReceiveSharingIntent.instance.reset();
  }

  static final _urlRegex = RegExp(
    r'https?://(?:www\.|m\.)?(?:youtube\.com|youtu\.be)/\S+',
    caseSensitive: false,
  );

  String? _extractYoutubeUrl(List<SharedMediaFile> items) {
    for (final m in items) {
      // Most YouTube share intents land in `.path` (or `.message` on older
      // package versions) as plain text containing the URL.
      final candidate = m.path;
      final match = _urlRegex.firstMatch(candidate);
      if (match != null) return match.group(0);
    }
    return null;
  }

  @override
  void dispose() {
    _sleepTicker?.cancel();
    _intentSub?.cancel();
    DownloadActionRouter.instance.unbind();
    _downloads.dispose();
    _audio.dispose();
    super.dispose();
  }

  void _setSleepTimer(Duration? d) {
    _sleepTicker?.cancel();
    setState(() => _sleepRemaining = d);
    if (d == null) return;
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = (_sleepRemaining ?? Duration.zero) - const Duration(seconds: 1);
      if (next.inSeconds <= 0) {
        _sleepTicker?.cancel();
        setState(() => _sleepRemaining = null);
        _audio.pause();
      } else {
        setState(() => _sleepRemaining = next);
      }
    });
  }

  Future<void> _persist() => _store.save(_tracks);

  Future<void> _selectTrack(Track t, {bool startPlaying = false}) async {
    if (t.status != TrackStatus.ready) return;
    await _audio.load(t, andPlay: startPlaying);
  }

  void _openTrack(Track t) {
    setState(() {
      _viewedTrack = t;
      _screen = _Screen.player;
    });
    if (t.status == TrackStatus.ready) {
      _selectTrack(t);
    }
  }

  Future<void> _playTapped(Track t) async {
    if (t.status != TrackStatus.ready) return;
    if (_current?.id == t.id) {
      await _audio.toggle();
    } else {
      await _selectTrack(t, startPlaying: true);
    }
  }

  Future<void> _cycleSpeed() async {
    const opts = [1.0, 1.25, 1.5, 1.75, 2.0];
    final i = opts.indexOf(_speed);
    final next = opts[(i + 1) % opts.length];
    setState(() => _speed = next);
    await _audio.setSpeed(next);
  }

  Future<void> _nextTrack() async {
    final ready = _tracks.where((t) => t.status == TrackStatus.ready).toList();
    if (ready.isEmpty) return;
    final i = ready.indexWhere((t) => t.id == _current?.id);
    final next = ready[(i + 1) % ready.length];
    await _selectTrack(next, startPlaying: true);
  }

  Future<void> _deleteTrack(Track t) async {
    // Stop any in-flight download for this id; abort doesn't fire onFailed.
    if (_downloads.isActive(t.id)) {
      await _downloads.abort(t.id);
    }
    final remaining = _tracks.where((x) => x.id != t.id).toList();
    final wasCurrent = _current?.id == t.id;
    setState(() {
      _tracks = remaining;
      if (_viewedTrack?.id == t.id) _viewedTrack = null;
    });
    if (wasCurrent) {
      await _audio.stop();
      Track? nextReady;
      for (final x in remaining) {
        if (x.status == TrackStatus.ready) {
          nextReady = x;
          break;
        }
      }
      if (nextReady != null) {
        await _audio.load(nextReady);
      }
    }
    await _audio.forget(t.id);
    await _store.deleteFileFor(t);
    await _persist();
  }

  Future<void> _onStartDownload(Track downloading, ResolvedVideo resolved) async {
    // Kick off the download FIRST. start()'s synchronous prefix inserts the
    // per-track ValueNotifier into DownloadManager._active before any await,
    // which means the library card subscribes to a live notifier on its
    // first build rather than the static empty one.
    final downloadFuture = _downloads.start(downloading, resolved);
    setState(() {
      _tracks = [downloading, ..._tracks];
      _screen = _Screen.library;
      _pendingDownloadUrl = null;
    });
    await _persist();
    await downloadFuture;
  }

  Future<void> _onDownloadCompleted(Track ready) async {
    if (!mounted) return;
    setState(() {
      _tracks = [
        for (final t in _tracks) t.id == ready.id ? ready : t,
      ];
      if (_viewedTrack?.id == ready.id) {
        _viewedTrack = ready;
      }
    });
    // If nothing is currently loaded in the player, bind this fresh track.
    if (_current == null) {
      await _audio.load(ready);
    }
    await _persist();
  }

  Future<void> _onDownloadFailed(String trackId, String message) async {
    if (!mounted) return;
    setState(() {
      _tracks = [
        for (final t in _tracks)
          t.id == trackId
              ? t.copyWith(status: TrackStatus.failed, errorMessage: message)
              : t,
      ];
      if (_viewedTrack?.id == trackId) {
        _viewedTrack = _viewedTrack!
            .copyWith(status: TrackStatus.failed, errorMessage: message);
      }
    });
    await _persist();
  }

  Future<void> _cancelDownload(String trackId) async {
    await _downloads.cancel(trackId);
  }

  void _cancelDownloadFromNotification(String trackId) {
    // Routed from the notification action; bounce to the manager.
    _downloads.cancel(trackId);
  }

  Future<void> _retryDownload(Track failed) async {
    if (failed.sourceUrl == null) return;
    final downloading = failed.copyWith(
      status: TrackStatus.downloading,
      clearErrorMessage: true,
    );
    // See _onStartDownload re: ordering.
    final retryFuture = _downloads.resolveAndStart(downloading);
    setState(() {
      _tracks = [
        for (final t in _tracks) t.id == failed.id ? downloading : t,
      ];
      if (_viewedTrack?.id == failed.id) _viewedTrack = downloading;
    });
    await _persist();
    await retryFuture;
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrent = _current != null;
    final viewed = _viewedTrack;
    return Scaffold(
      backgroundColor: AuroraTheme.bg,
      body: DecoratedBox(
        decoration: AuroraTheme.backgroundDecoration,
        child: Stack(
          children: [
            // Library is always the base layer.
            Positioned.fill(
              child: LibraryScreen(
                tracks: _tracks,
                currentId: _current?.id,
                playing: _playing,
                onOpenTrack: _openTrack,
                onPlay: _playTapped,
                onDelete: _deleteTrack,
                onSearch: () => setState(() => _screen = _Screen.search),
                downloadProgressFor: _downloads.progressFor,
              ),
            ),
            // Mini player — only when there's a current ready track and the
            // library is foreground.
            if (hasCurrent && _screen == _Screen.library)
              Positioned(
                left: 10,
                right: 10,
                bottom: 12 + MediaQuery.of(context).padding.bottom,
                child: MiniPlayer(
                  track: _current!,
                  playing: _playing,
                  progress: _progress,
                  onTogglePlay: _audio.toggle,
                  onExpand: () {
                    setState(() {
                      _viewedTrack = _current;
                      _screen = _Screen.player;
                    });
                  },
                  onNext: _nextTrack,
                ),
              ),
            if (viewed != null && _screen == _Screen.player)
              _DismissibleSheet(
                onDismissed: () => setState(() => _screen = _Screen.library),
                builder: (context, dismiss, onDragUpdate, onDragEnd) {
                  // Pull the freshest copy of the viewed track from the
                  // library list (status / errorMessage may have updated
                  // since the user opened the screen).
                  final fresh = _tracks.firstWhere(
                    (t) => t.id == viewed.id,
                    orElse: () => viewed,
                  );
                  final isReady = fresh.status == TrackStatus.ready;
                  return PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) dismiss();
                    },
                    child: Container(
                      color: AuroraTheme.bg,
                      child: SafeArea(
                        top: false,
                        child: NowPlayingScreen(
                          track: fresh,
                          playing: isReady ? _playing : false,
                          progress: isReady ? _progress : 0.0,
                          speed: _speed,
                          sleepRemaining: _sleepRemaining,
                          onTogglePlay: _audio.toggle,
                          onClose: dismiss,
                          onSeek: _audio.seekFraction,
                          onCycleSpeed: _cycleSpeed,
                          onPickSleepTimer: _setSleepTimer,
                          downloadProgress: _downloads.progressFor(fresh.id),
                          onCancelDownload: () => _cancelDownload(fresh.id),
                          onRetryDownload: () => _retryDownload(fresh),
                          onArtworkVerticalDragUpdate: onDragUpdate,
                          onArtworkVerticalDragEnd: onDragEnd,
                          onDelete: () async {
                            setState(() => _screen = _Screen.library);
                            await _deleteTrack(fresh);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (_screen == _Screen.search)
              _FadeIn(
                child: SafeArea(
                  top: false,
                  child: SearchScreen(
                    tracks: _tracks,
                    onClose: () => setState(() => _screen = _Screen.library),
                    onSelect: (t) {
                      if (t.status == TrackStatus.ready) {
                        _selectTrack(t, startPlaying: true);
                      }
                      setState(() {
                        _viewedTrack = t;
                        _screen = _Screen.player;
                      });
                    },
                  ),
                ),
              ),
            if (_screen == _Screen.download && _pendingDownloadUrl != null)
              DownloadSheet(
                url: _pendingDownloadUrl!,
                onClose: () => setState(() {
                  _screen = _Screen.library;
                  _pendingDownloadUrl = null;
                }),
                onStartDownload: _onStartDownload,
              ),
            if (hasCurrent && _screen == _Screen.lock)
              _FadeIn(
                child: LockScreen(
                  track: _current!,
                  playing: _playing,
                  progress: _progress,
                  onTogglePlay: _audio.toggle,
                  onDismiss: () => setState(() => _screen = _Screen.player),
                ),
              ),
            // FAB: "Add via URL" — opens a tiny dialog to paste a YouTube link,
            // mirroring the share-intent flow.
            if (_screen == _Screen.library)
              Positioned(
                right: 18,
                bottom: 24 + (hasCurrent ? 70 : 0) + MediaQuery.of(context).padding.bottom,
                child: _AddButton(onTap: _promptForUrl),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptForUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => _PasteUrlDialog(controller: controller),
    );
    if (url == null) return;
    setState(() {
      _pendingDownloadUrl = url;
      _screen = _Screen.download;
    });
  }
}

class _PasteUrlDialog extends StatelessWidget {
  final TextEditingController controller;
  const _PasteUrlDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AuroraTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add audio from URL',
                style: AuroraTheme.display(size: 18, weight: FontWeight.w700, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text(
              'Paste a YouTube link to extract its audio.',
              style: AuroraTheme.body(size: 12, color: AuroraTheme.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              cursorColor: AuroraTheme.accent,
              style: AuroraTheme.body(size: 14),
              decoration: InputDecoration(
                hintText: 'https://youtu.be/…',
                hintStyle: AuroraTheme.body(size: 14, color: AuroraTheme.dim),
                filled: true,
                fillColor: AuroraTheme.surface2,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AuroraTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AuroraTheme.accent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AuroraTheme.border),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel',
                      style: AuroraTheme.body(size: 13, weight: FontWeight.w600, color: AuroraTheme.muted)),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    final v = controller.text.trim();
                    if (v.isEmpty) return;
                    Navigator.of(context).pop(v);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AuroraTheme.accent,
                    foregroundColor: AuroraTheme.onAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Download',
                      style: AuroraTheme.body(size: 13, weight: FontWeight.w700, color: AuroraTheme.onAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AuroraTheme.accentGradient,
            boxShadow: [
              BoxShadow(color: AuroraTheme.accent.withValues(alpha: 0.40), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: AuroraTheme.onAccent, size: 28),
        ),
      ),
    );
  }
}

/// Slides up on mount, slides down on dismiss. Supports an external drag
/// (used on the Now Playing artwork) that follows the finger and commits
/// the dismissal past a threshold or with enough downward velocity.
typedef _SheetBuilder = Widget Function(
  BuildContext context,
  VoidCallback dismiss,
  void Function(DragUpdateDetails) onDragUpdate,
  void Function(DragEndDetails) onDragEnd,
);

class _DismissibleSheet extends StatefulWidget {
  final _SheetBuilder builder;
  final VoidCallback onDismissed;
  const _DismissibleSheet({required this.builder, required this.onDismissed});

  @override
  State<_DismissibleSheet> createState() => _DismissibleSheetState();
}

class _DismissibleSheetState extends State<_DismissibleSheet>
    with SingleTickerProviderStateMixin {
  // 0.0 = fully shown, 1.0 = translated off-screen (one screen height down).
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1.0,
  );
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _c.animateTo(0.0, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_settling) return;
    final h = MediaQuery.of(context).size.height;
    if (h <= 0) return;
    _c.value = (_c.value + d.delta.dy / h).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_settling) return;
    final h = MediaQuery.of(context).size.height;
    final velocityFraction = h <= 0 ? 0.0 : (d.primaryVelocity ?? 0) / h;
    if (_c.value > 0.25 || velocityFraction > 1.5) {
      _animateOut();
    } else {
      _c.animateTo(0.0,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  Future<void> _animateOut() async {
    if (_settling) return;
    _settling = true;
    await _c.animateTo(1.0,
        duration: const Duration(milliseconds: 240), curve: Curves.easeIn);
    if (mounted) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final h = MediaQuery.of(context).size.height;
        return Transform.translate(
          offset: Offset(0, _c.value * h),
          child: child,
        );
      },
      child: widget.builder(context, _animateOut, _onDragUpdate, _onDragEnd),
    );
  }
}

class _FadeIn extends StatefulWidget {
  final Widget child;
  const _FadeIn({required this.child});
  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _c, child: widget.child);
  }
}
