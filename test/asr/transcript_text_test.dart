import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/asr/asr.dart';

void main() {
  group('removeOverlap', () {
    test('drops the words repeated at the boundary', () {
      expect(
        removeOverlap('the quick brown fox', 'brown fox jumps over'),
        'jumps over',
      );
    });

    test('ignores case and punctuation when matching', () {
      expect(removeOverlap('Hello, world.', 'hello world again'), 'again');
      expect(removeOverlap('it works', 'It works!'), '');
    });

    test('prefers the longest overlap', () {
      expect(removeOverlap('a b a b', 'a b a b c'), 'c');
    });

    test('keeps words that merely appeared earlier', () {
      expect(removeOverlap('the cat sat', 'the dog ran'), 'the dog ran');
    });

    test('no overlap leaves text untouched; empty inputs are safe', () {
      expect(removeOverlap('one two', 'three four'), 'three four');
      expect(removeOverlap('', 'start here'), 'start here');
      expect(removeOverlap('something', ''), '');
    });

    test('minOverlapWords stops single-word matches', () {
      expect(removeOverlap('say no', 'no way', minOverlapWords: 2), 'no way');
    });
  });

  test('TranscriptAccumulator builds one text from overlapping windows', () {
    final acc = TranscriptAccumulator();
    expect(
      acc.add('good morning everyone welcome'),
      'good morning everyone welcome',
    );
    expect(acc.add('everyone welcome to the show'), 'to the show');
    expect(acc.add('the show is about to start'), 'is about to start');
    expect(acc.add('about to start'), '');
    expect(
      acc.text,
      'good morning everyone welcome to the show is about to start',
    );
    acc.clear();
    expect(acc.text, isEmpty);
  });

  test('isMeaningfulTranscript', () {
    expect(isMeaningfulTranscript('hello'), isTrue);
    expect(isMeaningfulTranscript('error code 5'), isTrue);
    expect(isMeaningfulTranscript('  '), isFalse);
    expect(isMeaningfulTranscript('...'), isFalse);
    expect(isMeaningfulTranscript('[BLANK_AUDIO]'), isFalse);
    expect(isMeaningfulTranscript('(music)'), isFalse);
    expect(isMeaningfulTranscript('[MUSIC] okay'), isTrue);
  });
}
