import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/asr/asr.dart';

Uint8List _pcm(int samples, [int fill = 1]) {
  final d = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    d.setInt16(i * 2, fill, Endian.little);
  }
  return d.buffer.asUint8List();
}

void main() {
  group('planChunks', () {
    test('short audio is a single window', () {
      expect(planChunks(100, 1000, 200), [(0, 100)]);
      expect(planChunks(0, 1000, 200), isEmpty);
    });

    test('windows overlap and the last ends at the total', () {
      expect(planChunks(2500, 1000, 200), [
        (0, 1000),
        (800, 1800),
        (1600, 2500),
      ]);
    });

    test('exact multiple does not add an empty tail window', () {
      expect(planChunks(1800, 1000, 200), [(0, 1000), (800, 1800)]);
    });

    test('every sample is covered', () {
      for (final total in [1, 999, 1000, 1001, 5000, 12345]) {
        final ranges = planChunks(total, 1000, 250);
        expect(ranges.first.$1, 0);
        expect(ranges.last.$2, total);
        for (var i = 1; i < ranges.length; i++) {
          expect(ranges[i].$1, lessThanOrEqualTo(ranges[i - 1].$2));
        }
      }
    });

    test('rejects invalid overlap', () {
      expect(() => planChunks(10, 5, 5), throwsArgumentError);
      expect(() => planChunks(10, 0, 0), throwsArgumentError);
    });
  });

  test('transcribeWindows feeds each window in order', () async {
    final samples = Float32List.fromList([
      for (var i = 0; i < 25; i++) i.toDouble(),
    ]);
    final seen = <List<double>>[];
    final texts = await transcribeWindows(
      samples,
      chunk: 10,
      overlap: 2,
      transcribe: (w) async {
        seen.add(w.toList());
        return 'w${w.first.toInt()}';
      },
    );
    expect(texts, ['w0', 'w8', 'w16']);
    expect(seen.last.last, 24);
  });

  group('PcmWindower', () {
    test('emits full windows and carries the overlap', () {
      final w = PcmWindower(windowSamples: 10, overlapSamples: 4);
      w.add(_pcm(6));
      expect(w.takeWindow(), isNull);
      w.add(_pcm(6, 2));
      final first = w.takeWindow()!;
      expect(first.length, 20);
      expect(w.takeWindow(), isNull); // only 6 carried samples
      w.add(_pcm(4, 3));
      final second = w.takeWindow()!;
      expect(second.length, 20);
      // starts with the last 4 samples of the previous window
      expect(ByteData.sublistView(second).getInt16(0, Endian.little), 2);
    });

    test('handles bytes split mid-sample', () {
      final w = PcmWindower(windowSamples: 4, overlapSamples: 0);
      final bytes = _pcm(4, 258); // 0x0102 per sample
      w.add(Uint8List.sublistView(bytes, 0, 3));
      expect(w.takeWindow(), isNull);
      w.add(Uint8List.sublistView(bytes, 3));
      final window = w.takeWindow()!;
      expect(window, bytes);
    });

    test('catches up through several windows from one big chunk', () {
      final w = PcmWindower(windowSamples: 10, overlapSamples: 2);
      w.add(_pcm(26));
      expect(w.takeWindow(), isNotNull); // samples 0..10
      expect(w.takeWindow(), isNotNull); // 8..18
      expect(w.takeWindow(), isNotNull); // 16..26
      expect(w.takeWindow(), isNull);
    });

    test('flush returns the tail only when enough new audio arrived', () {
      final w = PcmWindower(windowSamples: 10, overlapSamples: 4);
      w.add(_pcm(12));
      w.takeWindow();
      expect(w.flush(minNewSamples: 5), isNull);

      w.add(_pcm(12));
      w.takeWindow();
      w.add(_pcm(5));
      final tail = w.flush(minNewSamples: 5)!;
      expect(tail.length, (4 + 2 + 5) * 2); // carry + leftover + new
      expect(w.flush(), isNull);
    });
  });
}
