import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Status-bar notification for in-progress downloads.
/// One notification per download (keyed by `id`); calling `progress` again
/// updates the existing one in place.
class DownloadNotifier {
  static const _channelId = 'podcastr.downloads';
  static const _channelName = 'Downloads';
  static const _channelDescription = 'Audio download progress';
  static const cancelActionPrefix = 'cancel_';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initFuture;
  // Throttle updates: only push when the integer percent advances. Notification
  // updates above ~5/s can stutter the system shade on lower-end devices.
  final Map<int, int> _lastPercent = {};

  Future<void> _ensureInitialized() {
    // Memoize so concurrent calls share one in-flight permission prompt
    // (the permission_handler plugin throws if a second request races).
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: _backgroundOnResponse,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.low,
      showBadge: false,
      enableVibration: false,
      playSound: false,
    ));
    // Android 13+ requires runtime permission. Quietly request; fall back
    // to no-op if denied (download still works, just no system notification).
    try {
      await Permission.notification.request();
    } catch (_) {/* already running or denied — ignore */}
  }

  void _onResponse(NotificationResponse response) {
    final actionId = response.actionId;
    final payload = response.payload;
    if (actionId == null || payload == null) return;
    if (actionId.startsWith(cancelActionPrefix)) {
      DownloadActionRouter.deliver(payload);
    }
  }

  /// Show or update the progress notification for [id].
  /// [percent] is 0..100. If [percent] is null, an indeterminate bar is shown.
  /// [payload] is the track id used to route the Cancel action back.
  Future<void> progress({
    required int id,
    required String title,
    required String channel,
    required String payload,
    int? percent,
    String? subtext,
  }) async {
    await _ensureInitialized();
    if (percent != null) {
      final last = _lastPercent[id] ?? -1;
      if (percent == last) return;
      _lastPercent[id] = percent;
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: percent ?? 0,
        indeterminate: percent == null,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        category: AndroidNotificationCategory.progress,
        ticker: 'Downloading $title',
        subText: subtext ?? channel,
        showWhen: false,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            '$cancelActionPrefix$payload',
            'Cancel',
            showsUserInterface: false,
            cancelNotification: false,
          ),
        ],
      ),
    );
    await _plugin.show(id, title, channel, details, payload: payload);
  }

  /// Dismiss the progress notification once the download finishes.
  ///
  /// We don't post a "Saved · …" completion notification — keeping it
  /// around triggers Android's auto-group summary ("Podcastr is running"
  /// aggregate) the moment a second download starts. The in-app library
  /// row is the source of truth for completion; matches Spotify's
  /// notification flow where the media notification is the only one.
  Future<void> complete({
    required int id,
    required String title,
    required String channel,
  }) async {
    _lastPercent.remove(id);
    await _plugin.cancel(id);
  }

  /// Drop the notification on cancel / error.
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
    _lastPercent.remove(id);
  }
}

/// Routes notification-action callbacks (currently only "Cancel") back to a
/// single in-app handler.
///
/// On Android, action-button taps from `flutter_local_notifications` are
/// dispatched through a **background isolate** even if the app is in the
/// foreground. So we can't just call back into the UI directly — we send
/// the track id over an [IsolateNameServer]-registered SendPort, and the
/// main isolate listens. The owner of this router calls [bind] on startup
/// and [unbind] on dispose.
class DownloadActionRouter {
  DownloadActionRouter._();
  static final DownloadActionRouter instance = DownloadActionRouter._();

  static const String _portName = 'podcastr.download.cancel';

  void Function(String trackId)? onCancel;
  ReceivePort? _receivePort;

  /// Wire up the cross-isolate cancel channel. Safe to call multiple times.
  void bind() {
    if (_receivePort != null) return;
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    port.listen((dynamic msg) {
      if (msg is String) {
        onCancel?.call(msg);
      }
    });
    _receivePort = port;
  }

  void unbind() {
    IsolateNameServer.removePortNameMapping(_portName);
    _receivePort?.close();
    _receivePort = null;
    onCancel = null;
  }

  /// Called from either isolate. Tries the direct handler first; if it's
  /// missing (we're on the background isolate), routes via the port.
  static void deliver(String trackId) {
    final inst = instance;
    if (inst.onCancel != null) {
      inst.onCancel!(trackId);
      return;
    }
    final port = IsolateNameServer.lookupPortByName(_portName);
    port?.send(trackId);
  }
}

/// Top-level entry point so the Flutter engine can invoke this from a
/// background isolate (required by `flutter_local_notifications` for
/// notification-action callbacks).
@pragma('vm:entry-point')
void _backgroundOnResponse(NotificationResponse response) {
  final actionId = response.actionId;
  final payload = response.payload;
  if (actionId == null || payload == null) return;
  if (actionId.startsWith(DownloadNotifier.cancelActionPrefix)) {
    DownloadActionRouter.deliver(payload);
  }
}
