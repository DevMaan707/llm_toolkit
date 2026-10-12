import 'chunk.dart';
import 'span_utils.dart';

/// Plain character windows advancing by `chunkSize - overlap`.
class FixedSizeChunker extends Chunker {
  FixedSizeChunker({super.chunkSize = 800, super.overlap = 0});

  @override
  List<Chunk> chunk(String text, {String sourceId = ''}) {
    final spans = windowSpans(text, 0, text.length, chunkSize, overlap);
    return [
      for (var i = 0; i < spans.length; i++)
        Chunk(
          text: text.substring(spans[i].$1, spans[i].$2),
          index: i,
          start: spans[i].$1,
          end: spans[i].$2,
          sourceId: sourceId,
        ),
    ];
  }
}

/// Packs whole sentences; sentences longer than `chunkSize` are split on words.
class SentenceChunker extends Chunker {
  static final _boundary = RegExp(r'[.!?]+["”’)\]]*\s+|\n\s*\n');

  SentenceChunker({super.chunkSize = 800, super.overlap = 0});

  @override
  List<Chunk> chunk(String text, {String sourceId = ''}) {
    final raw = <Span>[];
    var start = 0;
    for (final m in _boundary.allMatches(text)) {
      raw.add((start, m.end));
      start = m.end;
    }
    raw.add((start, text.length));
    return packSpans(
      text,
      fitSpans(text, raw, chunkSize),
      size: chunkSize,
      overlap: overlap,
      sourceId: sourceId,
    );
  }
}

/// Packs whole paragraphs (blank-line separated); oversize ones split on words.
class ParagraphChunker extends Chunker {
  static final _blankLine = RegExp(r'\n[ \t]*\n');

  ParagraphChunker({super.chunkSize = 1000, super.overlap = 0});

  @override
  List<Chunk> chunk(String text, {String sourceId = ''}) {
    final raw = <Span>[];
    var start = 0;
    for (final m in _blankLine.allMatches(text)) {
      raw.add((start, m.start));
      start = m.end;
    }
    raw.add((start, text.length));
    return packSpans(
      text,
      fitSpans(text, raw, chunkSize),
      size: chunkSize,
      overlap: overlap,
      sourceId: sourceId,
    );
  }
}

/// Splits on the first separator that yields pieces small enough, falling
/// back to finer ones (paragraph, line, sentence, word, character), then
/// merges pieces back up to `chunkSize`.
class RecursiveCharacterChunker extends Chunker {
  final List<String> separators;

  RecursiveCharacterChunker({
    super.chunkSize = 800,
    super.overlap = 0,
    this.separators = const ['\n\n', '\n', '. ', ' '],
  });

  @override
  List<Chunk> chunk(String text, {String sourceId = ''}) => packSpans(
    text,
    _split(text, 0, text.length, 0),
    size: chunkSize,
    overlap: overlap,
    sourceId: sourceId,
  );

  List<Span> _split(String text, int s, int e, int level) {
    final t = trimSpan(text, s, e);
    if (t.$1 >= t.$2) return const [];
    if (t.$2 - t.$1 <= chunkSize) return [t];
    if (level >= separators.length) {
      return windowSpans(text, t.$1, t.$2, chunkSize, 0, snapToWords: true);
    }
    final sep = separators[level];
    final out = <Span>[];
    var pos = t.$1;
    while (true) {
      final i = text.indexOf(sep, pos);
      if (i < 0 || i + sep.length > t.$2) break;
      // Keep the separator's non-space head (e.g. the period in ". ").
      out.addAll(_split(text, pos, i + sep.trimRight().length, level + 1));
      pos = i + sep.length;
    }
    out.addAll(_split(text, pos, t.$2, level + 1));
    return out;
  }
}

/// Makes every span at most [size] long, splitting oversize ones on words.
List<Span> fitSpans(String text, List<Span> spans, int size) {
  final out = <Span>[];
  for (final (s, e) in spans) {
    final t = trimSpan(text, s, e);
    if (t.$1 >= t.$2) continue;
    if (t.$2 - t.$1 <= size) {
      out.add(t);
    } else {
      out.addAll(windowSpans(text, t.$1, t.$2, size, 0, snapToWords: true));
    }
  }
  return out;
}
