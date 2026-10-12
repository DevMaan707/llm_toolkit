import 'chunk.dart';

/// Half-open character range `[start, end)` of a source string.
typedef Span = (int start, int end);

/// Shrinks `[start, end)` so it neither begins nor ends with whitespace.
Span trimSpan(String text, int start, int end) {
  var s = start;
  var e = end;
  while (s < e && _isSpace(text.codeUnitAt(s))) {
    s++;
  }
  while (e > s && _isSpace(text.codeUnitAt(e - 1))) {
    e--;
  }
  return (s, e);
}

bool _isSpace(int c) => c == 0x20 || (c >= 0x09 && c <= 0x0D) || c == 0xA0;

/// Fixed-size windows over `[start, end)` advancing by `size - overlap`.
/// With [snapToWords] a window ends at the last whitespace in its second half
/// when one exists. Windows are trimmed; empty ones are dropped.
List<Span> windowSpans(
  String text,
  int start,
  int end,
  int size,
  int overlap, {
  bool snapToWords = false,
}) {
  final out = <Span>[];
  var s = start;
  while (s < end) {
    var e = s + size < end ? s + size : end;
    if (snapToWords && e < end) {
      for (var i = e; i > s + size ~/ 2; i--) {
        if (_isSpace(text.codeUnitAt(i - 1))) {
          e = i;
          break;
        }
      }
    }
    final t = trimSpan(text, s, e);
    if (t.$1 < t.$2) out.add(t);
    if (e >= end) break;
    final next = e - overlap;
    s = next > s ? next : e;
  }
  return out;
}

/// Greedily packs ordered [spans] (each at most [size] long) into chunks whose
/// extent never exceeds [size]. When a chunk closes, the longest tail of whole
/// spans no longer than [overlap] is repeated at the start of the next one.
List<Chunk> packSpans(
  String text,
  List<Span> spans, {
  required int size,
  required int overlap,
  required String sourceId,
}) {
  final out = <Chunk>[];
  if (spans.isEmpty) return out;

  void emit(int first, int last) {
    final s = spans[first].$1;
    final e = spans[last].$2;
    out.add(
      Chunk(
        text: text.substring(s, e),
        index: out.length,
        start: s,
        end: e,
        sourceId: sourceId,
      ),
    );
  }

  var first = 0;
  for (var i = 1; i < spans.length; i++) {
    if (spans[i].$2 - spans[first].$1 <= size) continue;
    emit(first, i - 1);
    var k = first + 1;
    while (k < i &&
        (spans[i - 1].$2 - spans[k].$1 > overlap ||
            spans[i].$2 - spans[k].$1 > size)) {
      k++;
    }
    first = k;
  }
  emit(first, spans.length - 1);
  return out;
}
