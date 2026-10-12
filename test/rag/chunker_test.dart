import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/rag/rag.dart';

void checkOffsets(String source, List<Chunk> chunks, int size) {
  for (final c in chunks) {
    expect(source.substring(c.start, c.end), c.text);
    expect(c.text.length, lessThanOrEqualTo(size));
    expect(c.text.trim(), c.text);
  }
}

void main() {
  group('FixedSizeChunker', () {
    test('empty and whitespace input yields nothing', () {
      expect(FixedSizeChunker(chunkSize: 10).chunk(''), isEmpty);
      expect(FixedSizeChunker(chunkSize: 10).chunk('   \n '), isEmpty);
    });

    test('text shorter than size is one chunk', () {
      final c = FixedSizeChunker(chunkSize: 100).chunk('hello', sourceId: 'a');
      expect(c, hasLength(1));
      expect((c.single.start, c.single.end, c.single.sourceId), (0, 5, 'a'));
    });

    test('overlap repeats exactly overlap characters', () {
      const text = 'abcdefghijklmnopqrstuvwxyz';
      final c = FixedSizeChunker(chunkSize: 10, overlap: 4).chunk(text);
      expect(c.first.text, 'abcdefghij');
      expect(c[1].text, 'ghijklmnop');
      expect(c[1].start, c[0].end - 4);
      expect(c.last.end, text.length);
      checkOffsets(text, c, 10);
    });

    test('rejects invalid overlap and size', () {
      expect(() => FixedSizeChunker(chunkSize: 0), throwsArgumentError);
      expect(
        () => FixedSizeChunker(chunkSize: 5, overlap: 5),
        throwsArgumentError,
      );
      expect(
        () => FixedSizeChunker(chunkSize: 5, overlap: -1),
        throwsArgumentError,
      );
    });
  });

  group('SentenceChunker', () {
    const text =
        'First sentence here. Second one follows! Is a third? Yes it is. '
        'And a fourth sentence ends it.';

    test('never splits mid-sentence when sentences fit', () {
      final c = SentenceChunker(chunkSize: 45).chunk(text);
      checkOffsets(text, c, 45);
      for (final chunk in c) {
        expect(RegExp(r'[.!?]$').hasMatch(chunk.text), isTrue);
      }
    });

    test('overlap carries whole trailing sentences', () {
      final c = SentenceChunker(chunkSize: 45, overlap: 25).chunk(text);
      checkOffsets(text, c, 45);
      expect(c.length, greaterThan(1));
      for (var i = 1; i < c.length; i++) {
        expect(c[i].start, lessThan(c[i - 1].end));
        expect(c[i].start, greaterThan(c[i - 1].start));
      }
    });

    test('oversize sentence is split on words', () {
      final long = List.filled(30, 'word').join(' ');
      final c = SentenceChunker(chunkSize: 40).chunk(long);
      checkOffsets(long, c, 40);
      expect(c.length, greaterThan(2));
      expect(c.map((e) => e.text).join(' '), long);
    });
  });

  group('ParagraphChunker / Recursive', () {
    const text = 'Para one line.\n\nPara two is here.\n\nPara three.';

    test('merges small paragraphs and keeps order', () {
      final c = ParagraphChunker(chunkSize: 40).chunk(text);
      checkOffsets(text, c, 40);
      expect(c.first.text, contains('Para one'));
      expect(c.last.text, contains('Para three'));
    });

    test('recursive handles text without separators', () {
      final blob = 'x' * 95;
      final c = RecursiveCharacterChunker(chunkSize: 30).chunk(blob);
      checkOffsets(blob, c, 30);
      expect(c.map((e) => e.text).join(), blob);
    });

    test('recursive overlap with words', () {
      final words = List.generate(40, (i) => 'w$i').join(' ');
      final c = RecursiveCharacterChunker(
        chunkSize: 50,
        overlap: 12,
      ).chunk(words);
      checkOffsets(words, c, 50);
      for (var i = 1; i < c.length; i++) {
        final shared = c[i - 1].end - c[i].start;
        expect(shared, inInclusiveRange(0, 12));
      }
    });

    test('indices are sequential', () {
      final c = RecursiveCharacterChunker(chunkSize: 20).chunk('a b ' * 30);
      expect([for (final x in c) x.index], List.generate(c.length, (i) => i));
    });
  });

  group('MarkdownChunker', () {
    const md = '''
Intro text.

# Guide

## Install

Run the installer.

```
# not a heading
```

## Usage

Call the thing.

### Advanced

Fine tuning.
''';

    test('chunks by heading with breadcrumbs and valid offsets', () {
      final c = MarkdownChunker(chunkSize: 200).chunk(md);
      checkOffsets(md, c, 200);
      final headings = c.map((e) => e.metadata['heading']).toList();
      expect(headings, [
        null,
        'Guide > Install',
        'Guide > Usage',
        'Guide > Usage > Advanced',
      ]);
      expect(c[1].text, contains('# not a heading'));
    });

    test('splits large sections', () {
      final big = '# T\n\n${List.filled(100, 'word').join(' ')}';
      final c = MarkdownChunker(chunkSize: 80).chunk(big);
      checkOffsets(big, c, 80);
      expect(c.length, greaterThan(3));
      expect(c.every((e) => e.metadata['heading'] == 'T'), isTrue);
    });
  });
}
