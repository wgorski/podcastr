import 'dart:io';
import 'dart:math' as math;

class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  const SubtitleCue(this.start, this.end, this.text);
}

class Subtitles {
  final List<SubtitleCue> cues;
  const Subtitles(this.cues);

  bool get isEmpty => cues.isEmpty;

  /// Index of the cue covering [position], or null when between cues.
  int? activeIndex(Duration position) {
    int lo = 0;
    int hi = cues.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final c = cues[mid];
      if (position < c.start) {
        hi = mid - 1;
      } else if (position >= c.end) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return null;
  }

  /// Index to anchor the lyrics window around when no cue is currently active.
  /// Returns the next upcoming cue, or the last cue when past the end.
  int anchorIndex(Duration position) {
    if (cues.isEmpty) return 0;
    if (position < cues.first.start) return 0;
    if (position >= cues.last.end) return cues.length - 1;
    int lo = 0;
    int hi = cues.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].start > position) {
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    return lo.clamp(0, cues.length - 1);
  }

  static Future<Subtitles?> loadFromFile(String path) async {
    try {
      final raw = await File(path).readAsString();
      return parseVtt(raw);
    } catch (_) {
      return null;
    }
  }
}

final _timingLine = RegExp(
  r'^(\d{1,2}:)?(\d{1,2}):(\d{2})\.(\d{3})\s*-->\s*(\d{1,2}:)?(\d{1,2}):(\d{2})\.(\d{3})',
);
final _inlineTag = RegExp(r'<[^>]+>');

Subtitles parseVtt(String input) {
  final lines = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final raw = <SubtitleCue>[];
  int i = 0;

  while (i < lines.length) {
    final line = lines[i];
    final match = _timingLine.firstMatch(line);
    if (match == null) {
      i++;
      continue;
    }
    final start = _parseTimestamp(match.group(1), match.group(2)!, match.group(3)!, match.group(4)!);
    final end = _parseTimestamp(match.group(5), match.group(6)!, match.group(7)!, match.group(8)!);
    i++;
    final buf = StringBuffer();
    while (i < lines.length && lines[i].trim().isNotEmpty) {
      final cleaned = lines[i].replaceAll(_inlineTag, '').trim();
      if (cleaned.isNotEmpty) {
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(cleaned);
      }
      i++;
    }
    final text = buf.toString().trim();
    if (text.isNotEmpty) {
      raw.add(SubtitleCue(start, end, text));
    }
  }
  return Subtitles(_dedupRollingCaptions(raw));
}

/// Collapse YouTube ASR's rolling-window cues into one cue per phrase.
///
/// Auto-captions repeat the same text across many overlapping cues, each
/// extending the previous by a word or trimming from the front: a phrase
/// like `"A B C D"` shows up as `"A"`, `"A B"`, `"A B C"`, `"A B C D"`,
/// `"B C D"`, `"C D"`, then the next phrase begins. Without dedup the
/// lyrics view looks like a stuck record.
List<SubtitleCue> _dedupRollingCaptions(List<SubtitleCue> raw) {
  final out = <SubtitleCue>[];
  for (final cue in raw) {
    if (out.isEmpty) {
      out.add(cue);
      continue;
    }
    final prev = out.last;
    // (1) The new cue extends the previous one — same prefix, more text.
    if (cue.text.startsWith(prev.text) && cue.text.length > prev.text.length) {
      out[out.length - 1] = SubtitleCue(prev.start, cue.end, cue.text);
      continue;
    }
    // (2) The new cue is a tail of the previous (the "scroll-back" view of an
    //     already-shown phrase) — drop it.
    if (prev.text.endsWith(cue.text)) {
      continue;
    }
    // (3) Suffix-of-prev = prefix-of-new overlap. Trim the duplicated head
    //     from the new cue so we keep only the genuinely new words.
    final overlap = _longestSuffixPrefixOverlap(prev.text, cue.text);
    if (overlap >= _minOverlapChars) {
      final trimmed = cue.text.substring(overlap).trim();
      if (trimmed.isEmpty) continue;
      out.add(SubtitleCue(cue.start, cue.end, trimmed));
      continue;
    }
    out.add(cue);
  }
  return out;
}

const int _minOverlapChars = 10;

int _longestSuffixPrefixOverlap(String a, String b) {
  final maxLen = math.min(a.length, b.length);
  for (int len = maxLen; len > 0; len--) {
    if (a.endsWith(b.substring(0, len))) return len;
  }
  return 0;
}

Duration _parseTimestamp(String? hourGroup, String mins, String secs, String ms) {
  final h = hourGroup == null ? 0 : int.parse(hourGroup.substring(0, hourGroup.length - 1));
  return Duration(
    hours: h,
    minutes: int.parse(mins),
    seconds: int.parse(secs),
    milliseconds: int.parse(ms),
  );
}
