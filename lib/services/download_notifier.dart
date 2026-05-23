import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Status-bar notification for in-progress downloads.
/// One notification per download (keyed by `id`); calling `progress` again
/// updates the existing one in place.
class DownloadNotifier {
  static const _channelId = 'podcastr.downloads';
  static const _channelName = 'Downloads';
  static const _channelDescription = 'Audio download progress';

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
    await _plugin.initialize(init);
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

  /// Show or update the progress notification for [id].
  /// [percent] is 0..100. If [percent] is null, an indeterminate bar is shown.
  Future<void> progress({
    required int id,
    required String title,
    required String channel,
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
      ),
    );
    await _plugin.show(id, title, channel, details);
  }

  /// Replace the progress notification with a final "Saved" line.
  Future<void> complete({
    required int id,
    required String title,
    required String channel,
  }) async {
    await _ensureInitialized();
    _lastPercent.remove(id);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        autoCancel: true,
        ongoing: false,
        category: AndroidNotificationCategory.progress,
        showWhen: true,
      ),
    );
    await _plugin.show(id, 'Saved · $title', channel, details);
  }

  /// Drop the notification on cancel / error.
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
    _lastPercent.remove(id);
  }
}
