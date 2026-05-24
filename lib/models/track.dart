import 'dart:math' as math;
import 'dart:ui';

enum TrackStatus { ready, downloading, queued, failed }

class Track {
  final String id;
  final String title;
  final String channel;
  final int duration;
  final String size;
  final String addedAt;
  final Color color1;
  final Color color2;
  /// Absolute filesystem path of the downloaded audio, or null if this is a
  /// design-time seed without backing file.
  final String? filePath;
  /// Absolute path of the downloaded thumbnail. Falls back to procedural art
  /// when missing or unreadable.
  final String? thumbnailPath;
  final TrackStatus status;
  /// Original YouTube URL — kept for retrying a failed download.
  final String? sourceUrl;
  /// Populated when [status] is [TrackStatus.failed].
  final String? errorMessage;

  const Track({
    required this.id,
    required this.title,
    required this.channel,
    required this.duration,
    required this.size,
    required this.addedAt,
    required this.color1,
    required this.color2,
    this.filePath,
    this.thumbnailPath,
    this.status = TrackStatus.ready,
    this.sourceUrl,
    this.errorMessage,
  });

  int get seed {
    final s = id.isEmpty ? 'x' : id;
    final first = s.codeUnitAt(0);
    final last = s.codeUnitAt(s.length - 1);
    return first * last;
  }

  Track copyWith({
    String? id,
    String? size,
    String? addedAt,
    String? filePath,
    String? thumbnailPath,
    TrackStatus? status,
    String? sourceUrl,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return Track(
      id: id ?? this.id,
      title: title,
      channel: channel,
      duration: duration,
      size: size ?? this.size,
      addedAt: addedAt ?? this.addedAt,
      color1: color1,
      color2: color2,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      status: status ?? this.status,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channel': channel,
        'duration': duration,
        'size': size,
        'addedAt': addedAt,
        'color1': color1.toARGB32(),
        'color2': color2.toARGB32(),
        'filePath': filePath,
        'thumbnailPath': thumbnailPath,
        'status': status.name,
        'sourceUrl': sourceUrl,
        'errorMessage': errorMessage,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String,
        channel: j['channel'] as String,
        duration: j['duration'] as int,
        size: j['size'] as String,
        addedAt: j['addedAt'] as String,
        color1: Color(j['color1'] as int),
        color2: Color(j['color2'] as int),
        filePath: j['filePath'] as String?,
        thumbnailPath: j['thumbnailPath'] as String?,
        status: _statusFromJson(j['status']),
        sourceUrl: j['sourceUrl'] as String?,
        errorMessage: j['errorMessage'] as String?,
      );
}

TrackStatus _statusFromJson(Object? raw) {
  if (raw is String) {
    for (final s in TrackStatus.values) {
      if (s.name == raw) return s;
    }
  }
  return TrackStatus.ready;
}

/// Deterministic palette derived from a video ID — so each downloaded track
/// gets a stable, distinctive thumbnail color.
({Color c1, Color c2}) paletteForId(String id) {
  int h = 0;
  for (int i = 0; i < id.length; i++) {
    h = ((h * 31) + id.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  const palettes = <(int, int)>[
    (0xFFF0A868, 0xFFC9622E),
    (0xFF6AB7FF, 0xFF2D6BB8),
    (0xFFB794FF, 0xFF7558C4),
    (0xFFFF6B5B, 0xFFC4382B),
    (0xFF5EE3D4, 0xFF2A9D8F),
    (0xFFF5D96C, 0xFFB89934),
    (0xFFFF8DB2, 0xFFC25288),
  ];
  final p = palettes[h % palettes.length];
  return (c1: Color(p.$1), c2: Color(p.$2));
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:$mm:$ss';
  return '$m:$ss';
}

String formatShort(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '$m min';
}

/// Deterministic pseudo-waveform — matches the JS implementation in data.jsx.
List<double> waveformBars(String seed, {int count = 64}) {
  int h = 0;
  for (int i = 0; i < seed.length; i++) {
    h = ((h * 31) + seed.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  final bars = <double>[];
  for (int i = 0; i < count; i++) {
    h = ((h * 1664525) + 1013904223) & 0xFFFFFFFF;
    final v = ((h >> 8) & 0xff) / 255.0;
    final t = i / count;
    final edge = math.sin(t * math.pi);
    final ripple = 0.1 * math.sin(i * 0.7);
    final value = 0.18 + v * 0.7 * edge + ripple;
    bars.add(value.clamp(0.08, 1.0).toDouble());
  }
  return bars;
}
