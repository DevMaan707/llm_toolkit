import 'chunk.dart';
import 'chunkers.dart';

/// Splits Markdown by heading sections (fenced code blocks are not scanned for
/// headings). Each section is split with a [RecursiveCharacterChunker] when it
/// exceeds `chunkSize`. Chunks carry a `heading` metadata entry with the
/// breadcrumb, e.g. `Guide > Install`.
class MarkdownChunker extends Chunker {
  static final _heading = RegExp(r'^(#{1,6})[ \t]+(.+?)[ \t#]*$');

  MarkdownChunker({super.chunkSize = 1000, super.overlap = 0});

  @override
  List<Chunk> chunk(String text, {String sourceId = ''}) {
    final inner = RecursiveCharacterChunker(
      chunkSize: chunkSize,
      overlap: overlap,
    );
    final out = <Chunk>[];
    for (final sec in _sections(text)) {
      final body = text.substring(sec.start, sec.end);
      final content =
          sec.hasHeading
              ? body.substring(
                body.contains('\n') ? body.indexOf('\n') : body.length,
              )
              : body;
      if (content.trim().isEmpty) continue;
      final meta = <String, Object?>{
        if (sec.path.isNotEmpty) 'heading': sec.path.join(' > '),
      };
      for (final c in inner.chunk(body, sourceId: sourceId)) {
        out.add(
          c.copyWith(
            index: out.length,
            start: c.start + sec.start,
            end: c.end + sec.start,
            metadata: meta,
          ),
        );
      }
    }
    return out;
  }

  List<_Section> _sections(String text) {
    final sections = <_Section>[];
    final stack = <(int level, String title)>[];
    var current = _Section(0, const [], hasHeading: false);
    var inFence = false;
    var offset = 0;
    for (final line in text.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
      } else if (!inFence) {
        final m = _heading.firstMatch(line);
        if (m != null) {
          current.end = offset;
          sections.add(current);
          final level = m.group(1)!.length;
          stack.removeWhere((h) => h.$1 >= level);
          stack.add((level, m.group(2)!));
          current = _Section(offset, [for (final h in stack) h.$2]);
        }
      }
      offset += line.length + 1;
    }
    current.end = text.length;
    sections.add(current);
    return sections;
  }
}

class _Section {
  final int start;
  int end = 0;
  final List<String> path;
  final bool hasHeading;

  _Section(this.start, this.path, {this.hasHeading = true});
}
