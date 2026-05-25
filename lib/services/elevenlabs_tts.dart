import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class TtsException implements Exception {
  final String message;
  const TtsException(this.message);
  @override
  String toString() => message;
}

class TtsResult {
  final String filePath;
  final int bytesWritten;
  final int chunkCount;
  const TtsResult({
    required this.filePath,
    required this.bytesWritten,
    required this.chunkCount,
  });
}

/// ElevenLabs Text-to-Speech.
///
/// Splits arbitrarily long text into ≤[chunkLimit]-char chunks at paragraph
/// / sentence boundaries, sends each as a separate `audio/mpeg` request, and
/// writes the raw bytes back-to-back into one .mp3 file. MP3 streams are
/// concatenable at frame boundaries — every Android-side player we use
/// (just_audio → ExoPlayer/Media3) decodes the result fine.
class ElevenLabsTts {
  /// The free / starter tier caps text input at 5,000 chars per request. We
  /// stay safely under that so we don't burn a request when a paragraph runs
  /// long.
  static const int chunkLimit = 3000;
  static const String _baseUrl = 'https://api.elevenlabs.io/v1/text-to-speech';
  static const String defaultVoiceId = '21m00Tcm4TlvDq8ikWAM'; // "Rachel"
  static const String defaultModelId = 'eleven_multilingual_v2';

  final http.Client _client;
  ElevenLabsTts({http.Client? client}) : _client = client ?? http.Client();

  /// Synthesize [text] to [outputPath]. Reports progress as
  /// (charsSynthesized, totalChars) via [onProgress].
  Future<TtsResult> synthesize({
    required String text,
    required String apiKey,
    required String outputPath,
    String voiceId = defaultVoiceId,
    String modelId = defaultModelId,
    void Function(int charsDone, int totalChars)? onProgress,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const TtsException(
        'No ElevenLabs API key. Add one in Settings to generate article audio.',
      );
    }
    final clean = text.trim();
    if (clean.isEmpty) {
      throw const TtsException('Article text is empty.');
    }

    final chunks = _chunkText(clean, chunkLimit);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    if (await file.exists()) await file.delete();

    final sink = file.openWrite();
    var totalBytes = 0;
    var charsDone = 0;
    final totalChars = clean.length;
    try {
      onProgress?.call(0, totalChars);
      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final bytes = await _synthesizeChunk(
          text: chunk,
          apiKey: apiKey,
          voiceId: voiceId,
          modelId: modelId,
        );
        sink.add(bytes);
        totalBytes += bytes.length;
        charsDone += chunk.length;
        onProgress?.call(charsDone.clamp(0, totalChars), totalChars);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await file.exists()) await file.delete();
      rethrow;
    }

    return TtsResult(
      filePath: outputPath,
      bytesWritten: totalBytes,
      chunkCount: chunks.length,
    );
  }

  Future<List<int>> _synthesizeChunk({
    required String text,
    required String apiKey,
    required String voiceId,
    required String modelId,
  }) async {
    final uri = Uri.parse('$_baseUrl/$voiceId');
    final body = jsonEncode({
      'text': text,
      'model_id': modelId,
      'voice_settings': {
        'stability': 0.5,
        'similarity_boost': 0.75,
      },
    });
    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: {
              'xi-api-key': apiKey,
              'Accept': 'audio/mpeg',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const TtsException('ElevenLabs request timed out.');
    } catch (e) {
      throw TtsException('ElevenLabs request failed: $e');
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const TtsException(
        'ElevenLabs rejected the API key (check it in Settings).',
      );
    }
    if (res.statusCode == 429) {
      throw const TtsException(
        'ElevenLabs rate limit / quota hit — try again later.',
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TtsException(_extractError(res));
    }
    if (res.bodyBytes.isEmpty) {
      throw const TtsException('ElevenLabs returned no audio.');
    }
    return res.bodyBytes;
  }

  String _extractError(http.Response res) {
    try {
      final j = jsonDecode(res.body);
      if (j is Map) {
        final detail = j['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (detail is Map) {
          final msg = detail['message'];
          if (msg is String && msg.isNotEmpty) return msg;
        }
        final msg = j['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {/* fall through */}
    return 'ElevenLabs returned HTTP ${res.statusCode}.';
  }

  void dispose() {
    _client.close();
  }

  /// Split [text] into chunks of at most [limit] characters, preferring
  /// paragraph then sentence boundaries. Greedy packer: we keep appending
  /// segments to the current chunk until the next one would overflow.
  static List<String> _chunkText(String text, int limit) {
    if (text.length <= limit) return [text];

    final segments = <String>[];
    for (final para in text.split(RegExp(r'\n\s*\n'))) {
      final p = para.trim();
      if (p.isEmpty) continue;
      if (p.length <= limit) {
        segments.add(p);
      } else {
        // Long paragraph — split into sentences. Keep terminator on each.
        final sentences = RegExp(r'[^.!?]+[.!?]+(?:\s|$)|[^.!?]+$')
            .allMatches(p)
            .map((m) => m.group(0)!.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (sentences.isEmpty) {
          // No terminators at all — fall back to a hard slice.
          for (var i = 0; i < p.length; i += limit) {
            segments.add(p.substring(i, (i + limit).clamp(0, p.length)));
          }
        } else {
          for (final s in sentences) {
            if (s.length <= limit) {
              segments.add(s);
            } else {
              for (var i = 0; i < s.length; i += limit) {
                segments.add(s.substring(i, (i + limit).clamp(0, s.length)));
              }
            }
          }
        }
      }
    }

    final chunks = <String>[];
    final buf = StringBuffer();
    for (final s in segments) {
      if (buf.isEmpty) {
        buf.write(s);
      } else if (buf.length + 2 + s.length <= limit) {
        buf.write('\n\n');
        buf.write(s);
      } else {
        chunks.add(buf.toString());
        buf
          ..clear()
          ..write(s);
      }
    }
    if (buf.isNotEmpty) chunks.add(buf.toString());
    return chunks;
  }
}
