import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/services/youtube_downloader.dart';

void main() {
  group('ResolvedVideo.fromMap', () {
    test('parses all fields from a typical bridge response', () {
      final v = ResolvedVideo.fromMap({
        'videoId': 'dQw4w9WgXcQ',
        'title': 'Never Gonna',
        'channel': 'Rick',
        'durationSeconds': 213,
        'audioUrl': 'https://example.com/audio',
        'averageBitrate': 128000,
        'mimeType': 'audio/mp4',
        'extension': 'm4a',
        'thumbnailUrl': 'https://example.com/thumb.jpg',
      });

      expect(v.videoId, 'dQw4w9WgXcQ');
      expect(v.title, 'Never Gonna');
      expect(v.channel, 'Rick');
      expect(v.durationSeconds, 213);
      expect(v.audioUrl, 'https://example.com/audio');
      expect(v.averageBitrate, 128000);
      expect(v.mimeType, 'audio/mp4');
      expect(v.extension, 'm4a');
      expect(v.thumbnailUrl, 'https://example.com/thumb.jpg');
    });

    test('accepts null thumbnailUrl', () {
      final v = ResolvedVideo.fromMap({
        'videoId': 'id',
        'title': 't',
        'channel': 'c',
        'durationSeconds': 1,
        'audioUrl': 'u',
        'averageBitrate': 1,
        'mimeType': 'm',
        'extension': 'e',
        'thumbnailUrl': null,
      });
      expect(v.thumbnailUrl, isNull);
    });

    test('coerces numeric fields from any num subtype', () {
      // Kotlin sometimes sends Long, which on the Dart side may arrive as an
      // int or a double depending on the codec. `(x as num).toInt()` handles
      // both — verify the contract.
      final v = ResolvedVideo.fromMap({
        'videoId': 'id',
        'title': 't',
        'channel': 'c',
        'durationSeconds': 60.0,
        'audioUrl': 'u',
        'averageBitrate': 96000.0,
        'mimeType': 'm',
        'extension': 'e',
        'thumbnailUrl': null,
      });
      expect(v.durationSeconds, 60);
      expect(v.averageBitrate, 96000);
    });
  });

  group('ResolvedVideo.sizeLabelFromBytes', () {
    final v = ResolvedVideo.fromMap({
      'videoId': 'id',
      'title': 't',
      'channel': 'c',
      'durationSeconds': 1,
      'audioUrl': 'u',
      'averageBitrate': 1,
      'mimeType': 'm',
      'extension': 'e',
      'thumbnailUrl': null,
    });

    test('returns the em-dash placeholder for zero or negative byte counts', () {
      expect(v.sizeLabelFromBytes(0), '— MB');
      expect(v.sizeLabelFromBytes(-5), '— MB');
    });

    test('formats megabytes with one decimal', () {
      expect(v.sizeLabelFromBytes(1024 * 1024), '1.0 MB');
      expect(v.sizeLabelFromBytes(5 * 1024 * 1024 + 512 * 1024), '5.5 MB');
    });

    test('sub-megabyte byte counts round down to 0.x MB', () {
      // 100 KiB = ~0.1 MB
      expect(v.sizeLabelFromBytes(100 * 1024), '0.1 MB');
    });
  });

  group('DownloadProgress', () {
    test('fraction is bytesReceived / totalBytes', () {
      expect(const DownloadProgress(50, 100).fraction, 0.5);
      expect(const DownloadProgress(0, 100).fraction, 0.0);
      expect(const DownloadProgress(100, 100).fraction, 1.0);
    });

    test('fraction is clamped to [0, 1] when overshooting', () {
      expect(const DownloadProgress(150, 100).fraction, 1.0);
    });

    test('fraction returns 0 when totalBytes is unknown (<=0)', () {
      expect(const DownloadProgress(123, 0).fraction, 0);
      expect(const DownloadProgress(123, -1).fraction, 0);
    });
  });

  group('YoutubeException', () {
    test('toString returns the configured message', () {
      const e = YoutubeException('boom');
      expect(e.toString(), 'boom');
      expect(e.message, 'boom');
    });

    test('is throwable as an Exception', () {
      expect(
        () => throw const YoutubeException('nope'),
        throwsA(isA<YoutubeException>()),
      );
    });
  });
}
