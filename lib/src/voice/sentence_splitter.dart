/// Cuts a token stream into speakable sentences and strips markdown that a
/// speech model would read aloud (`**`, backticks, headings, list markers).
class SentenceSplitter {
  /// Sentences shorter than this are merged with the next one, so "Ok." and
  /// "Dr." do not become separate (and choppy) utterances.
  final int minLength;

  final StringBuffer _buffer = StringBuffer();

  SentenceSplitter({this.minLength = 20});

  static final _end = RegExp(r'[.!?…]+["”)\]]*(\s+|$)|\n+');

  /// Adds [chunk] and returns the sentences that are now complete.
  List<String> add(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final out = <String>[];
    var start = 0;
    for (final m in _end.allMatches(text)) {
      // A terminator at the very end may still be followed by more of the
      // same word ("3." then "5"), so wait until whitespace confirms it.
      if (m.end == text.length && !text.endsWith('\n') && m.group(1) == '') {
        break;
      }
      final candidate = text.substring(start, m.end);
      if (clean(candidate).length < minLength) continue;
      out.add(clean(candidate));
      start = m.end;
    }
    _buffer
      ..clear()
      ..write(text.substring(start));
    return out;
  }

  /// The trailing text that never reached a sentence end.
  String? flush() {
    final rest = clean(_buffer.toString());
    _buffer.clear();
    return rest.isEmpty ? null : rest;
  }

  /// Removes markdown decoration and collapses whitespace.
  static String clean(String s) =>
      s
          .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
          .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1]!)
          .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
          .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
          .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
          .replaceAll(RegExp(r'[*_~]{1,3}'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
}
