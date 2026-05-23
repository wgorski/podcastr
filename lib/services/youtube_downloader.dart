import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

const _channel = MethodChannel('com.example.podcastr/youtube');

/// What the Kotlin NewPipe Extractor bridge returns for a given YouTube URL.
class ResolvedVideo {
  final String videoId;
  final String title;
  final String channel;
  final int durationSeconds;
  final String audioUrl;
  final int averageBitrate;
  final String mimeType;
  final String extension;
  final String? thumbnailUrl;
  const ResolvedVideo({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.durationSeconds,
    required this.audioUrl,
    required this.averageBitrate,
    required this.mimeType,
    required this.extension,
    required this.thumbnailUrl,
  });

  factory ResolvedVideo.fromMap(Map<dynamic, dynamic> m) => ResolvedVideo(
        videoId: m['videoId'] as String,
        title: m['title'] as String,
        channel: m['channel'] as String,
        durationSeconds: (m['durationSeconds'] as num).toInt(),
        audioUrl: m['audioUrl'] as String,
        averageBitrate: (m['averageBitrate'] as num).toInt(),
        mimeType: m['mimeType'] as String,
        extension: m['extension'] as String,
        thumbnailUrl: m['thumbnailUrl'] as String?,
      );

  /// NewPipe doesn't always report content-length up front; we get it from the
  /// download response. Used for the "estimated size" line in the UI.
  String sizeLabelFromBytes(int bytes) {
    if (bytes <= 0) return '— MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class DownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  const DownloadProgress(this.bytesReceived, this.totalBytes);
  double get fraction => totalBytes <= 0 ? 0 : (bytesReceived / totalBytes).clamp(0.0, 1.0);
}

/// YouTube extraction lives in Kotlin (NewPipe Extractor); the actual byte
/// download happens here in Dart over `package:http` so we can drive a
/// progress UI without a separate event channel.
class YoutubeDownloader {
  Future<ResolvedVideo> resolve(String url) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('resolve', {'url': url});
    if (result == null) {
      throw const YoutubeException('Extractor returned no data.');
    }
    return ResolvedVideo.fromMap(result);
  }

  /// Streams the audio stream URL to a file under the app's documents dir.
  Stream<DownloadProgress> download(ResolvedVideo v, {required String filePath}) async* {
    final req = http.Request('GET', Uri.parse(v.audioUrl));
    final res = await req.send();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw YoutubeException('Audio stream returned HTTP ${res.statusCode}.');
    }
    final total = res.contentLength ?? -1;
    final file = File(filePath);
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// Computed destination path for a given video ID + container.
  static Future<String> filePathFor(ResolvedVideo v) async {
    final dir = await _tracksDir();
    return '${dir.path}/${v.videoId}.${v.extension}';
  }

  /// Destination path for the cached thumbnail.
  static Future<String> thumbnailPathFor(ResolvedVideo v) async {
    final dir = await _tracksDir();
    return '${dir.path}/${v.videoId}.jpg';
  }

  static Future<Directory> _tracksDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final tracksDir = Directory('${dir.path}/tracks');
    if (!await tracksDir.exists()) {
      await tracksDir.create(recursive: true);
    }
    return tracksDir;
  }

  /// Best-effort thumbnail download. Returns the path on success, or null if
  /// no URL was provided or the request failed — the procedural art still
  /// works as a fallback.
  Future<String?> downloadThumbnail(ResolvedVideo v) async {
    final url = v.thumbnailUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final path = await thumbnailPathFor(v);
      final f = File(path);
      await f.writeAsBytes(res.bodyBytes);
      return path;
    } catch (_) {
      return null;
    }
  }

  /// Build the persistent Track once the download finishes.
  static Track buildTrack(
    ResolvedVideo v,
    String filePath,
    int bytesReceived, {
    String? thumbnailPath,
  }) {
    final palette = paletteForId(v.videoId);
    return Track(
      id: v.videoId,
      title: v.title,
      channel: v.channel,
      duration: v.durationSeconds,
      size: v.sizeLabelFromBytes(bytesReceived),
      addedAt: 'Today',
      color1: palette.c1,
      color2: palette.c2,
      filePath: filePath,
      thumbnailPath: thumbnailPath,
    );
  }
}

class YoutubeException implements Exception {
  final String message;
  const YoutubeException(this.message);
  @override
  String toString() => message;
}
