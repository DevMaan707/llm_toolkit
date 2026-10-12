import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/asr/asr.dart';

import 'helpers.dart';

const _frames = MelSpectrogram.nFrames;
const _mels = MelSpectrogram.nMels;

/// Mean over [frames] of the given mel row.
double _rowMean(Float32List mel, int row, int frames) {
  var sum = 0.0;
  for (var t = 0; t < frames; t++) {
    sum += mel[row * _frames + t];
  }
  return sum / frames;
}

int _peakRow(Float32List mel, int frames) {
  var best = 0;
  for (var m = 1; m < _mels; m++) {
    if (_rowMean(mel, m, frames) > _rowMean(mel, best, frames)) best = m;
  }
  return best;
}

void main() {
  final extractor = MelSpectrogram();

  test('shape is 80 x 3000 regardless of input length', () {
    expect(extractor.compute(Float32List(0)).length, _mels * _frames);
    expect(extractor.compute(sine(440, 16000, 1)).length, _mels * _frames);
    expect(extractor.compute(sine(440, 16000, 40)).length, _mels * _frames);
  });

  test('values are finite and normalised into the Whisper range', () {
    final mel = extractor.compute(sine(440, 16000, 2));
    // (clamped log10 + 4) / 4 lies within 2 units of the maximum.
    var max = -double.infinity;
    for (final v in mel) {
      expect(v.isFinite, isTrue);
      if (v > max) max = v;
    }
    for (final v in mel) {
      expect(v, greaterThanOrEqualTo(max - 2 - 1e-5));
    }
  });

  test('a sine peaks in the mel band containing its frequency', () {
    final low = _peakRow(extractor.compute(sine(300, 16000, 2)), 190);
    final mid = _peakRow(extractor.compute(sine(1500, 16000, 2)), 190);
    final high = _peakRow(extractor.compute(sine(5000, 16000, 2)), 190);
    expect(low, lessThan(mid));
    expect(mid, lessThan(high));
    // Slaney mel of 1.5 kHz is ~ 22 -> band index in the mid-20s of 80.
    expect(mid, inInclusiveRange(20, 36));
  });

  test('frames past the audio are constant and below the active frames', () {
    final mel = extractor.compute(sine(440, 16000, 1));
    final active = _rowMean(mel, _peakRow(mel, 90), 90);
    final pad1 = mel[10 * _frames + 1000];
    final pad2 = mel[10 * _frames + 2999];
    expect(pad1, pad2);
    expect(pad1, lessThan(active));
  });

  test('silence is flat', () {
    final mel = extractor.compute(Float32List(16000));
    expect(mel.every((v) => v == mel.first), isTrue);
  });

  test('louder audio does not change the peak-relative floor', () {
    final quiet = extractor.compute(sine(440, 16000, 1, amp: 0.05));
    final loud = extractor.compute(sine(440, 16000, 1, amp: 0.9));
    // Log-mel is level dependent only up to the clamp: both end at the same max-8 floor offset.
    double spread(Float32List m) =>
        m.reduce((a, b) => a > b ? a : b) - m.reduce((a, b) => a < b ? a : b);
    expect(spread(quiet), closeTo(spread(loud), 1e-4));
  });

  test('computeMelSpectrogram matches the synchronous result', () async {
    final audio = sine(440, 16000, 0.5);
    final async = await computeMelSpectrogram(audio);
    final sync = extractor.compute(audio);
    expect(async, sync);
  });
}
