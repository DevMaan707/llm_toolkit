/// Words of [text] with case and surrounding punctuation stripped, for
/// comparing transcripts of overlapping audio.
List<String> _words(String text) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

String _norm(String word) => word.toLowerCase().replaceAll(
  RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
  '',
);

/// Returns the part of [next] that is not already at the end of [previous].
///
/// Transcripts of overlapping audio repeat the words heard twice; this finds
/// the longest run (up to [maxOverlapWords]) where the tail of [previous]
/// equals the head of [next] and drops it from [next].
String removeOverlap(
  String previous,
  String next, {
  int maxOverlapWords = 16,
  int minOverlapWords = 1,
}) {
  final prev = _words(previous);
  final nxt = _words(next);
  final limit = [
    maxOverlapWords,
    prev.length,
    nxt.length,
  ].reduce((a, b) => a < b ? a : b);
  for (var k = limit; k >= minOverlapWords; k--) {
    var match = true;
    for (var i = 0; i < k; i++) {
      final a = _norm(prev[prev.length - k + i]);
      if (a.isEmpty || a != _norm(nxt[i])) {
        match = false;
        break;
      }
    }
    if (match) return nxt.sublist(k).join(' ');
  }
  return nxt.join(' ');
}

/// Joins successive transcripts of overlapping windows into one text.
class TranscriptAccumulator {
  final int maxOverlapWords;
  String _text = '';

  TranscriptAccumulator({this.maxOverlapWords = 16});

  /// Everything accumulated so far.
  String get text => _text;

  /// Appends [chunk] without its overlap with the existing text and returns
  /// the newly added part (empty if nothing new).
  String add(String chunk) {
    final fresh = removeOverlap(_text, chunk, maxOverlapWords: maxOverlapWords);
    if (fresh.isEmpty) return '';
    _text = _text.isEmpty ? fresh : '$_text $fresh';
    return fresh;
  }

  void clear() => _text = '';
}

/// False for empty output and for non-speech markers Whisper emits on
/// silence/noise, such as `[BLANK_AUDIO]`, `(music)` or lone punctuation.
bool isMeaningfulTranscript(String text) {
  final t = text.trim();
  if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(t)) return false;
  final withoutTags =
      t.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*'), '').trim();
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(withoutTags);
}
