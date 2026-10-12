import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/asr/asr.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

import 'helpers.dart';

Uint8List _wav({
  required int channels,
  required int rate,
  required int bits,
  required Uint8List data,
  int format = 1,
  bool extraChunk = false,
  int? declaredDataSize,
}) {
  final b = BytesBuilder();
  void u32(int v) =>
      b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) =>
      b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  b.add('RIFF'.codeUnits);
  u32(0);
  b.add('WAVE'.codeUnits);
  if (extraChunk) {
    b.add('LIST'.codeUnits);
    u32(3);
    b.add([1, 2, 3, 0]); // odd size + pad byte
  }
  b.add('fmt '.codeUnits);
  u32(16);
  u16(format);
  u16(channels);
  u32(rate);
  u32(rate * channels * bits ~/ 8);
  u16(channels * bits ~/ 8);
  u16(bits);
  b.add('data'.codeUnits);
  u32(declaredDataSize ?? data.length);
  b.add(data);
  return b.toBytes();
}

Uint8List _i16(List<int> v) {
  final d = ByteData(v.length * 2);
  for (var i = 0; i < v.length; i++) {
    d.setInt16(i * 2, v[i], Endian.little);
  }
  return d.buffer.asUint8List();
}

void main() {
  group('parseWav', () {
    test('reads format fields and data bounds', () {
      final info = parseWav(
        _wav(channels: 2, rate: 44100, bits: 16, data: _i16([1, 2, 3, 4])),
      );
      expect(info.channels, 2);
      expect(info.sampleRate, 44100);
      expect(info.bitsPerSample, 16);
      expect(info.isFloat, isFalse);
      expect(info.dataOffset, 44);
      expect(info.dataLength, 8);
    });

    test('skips unknown chunks including odd-size padding', () {
      final info = parseWav(
        _wav(
          channels: 1,
          rate: 16000,
          bits: 16,
          data: _i16([5, 6]),
          extraChunk: true,
        ),
      );
      expect(info.dataOffset, 44 + 12);
      expect(info.dataLength, 4);
    });

    test('clamps an oversized or streaming data length', () {
      for (final declared in [0, 0xFFFFFFFF, 9999]) {
        final info = parseWav(
          _wav(
            channels: 1,
            rate: 16000,
            bits: 16,
            data: _i16([1, 2, 3]),
            declaredDataSize: declared,
          ),
        );
        expect(info.dataLength, 6, reason: 'declared $declared');
      }
    });

    test('rejects non-WAV, compressed and truncated input', () {
      expect(
        () => parseWav(Uint8List.fromList(List.filled(64, 1))),
        throwsA(isA<InferenceException>()),
      );
      expect(
        () => parseWav(
          _wav(channels: 1, rate: 8000, bits: 16, data: _i16([1]), format: 2),
        ),
        throwsA(isA<InferenceException>()),
      );
      final noData = Uint8List.sublistView(
        _wav(channels: 1, rate: 8000, bits: 16, data: _i16([1])),
        0,
        36,
      );
      expect(() => parseWav(noData), throwsA(isA<InferenceException>()));
    });
  });

  group('decodeAudio', () {
    test('PCM16 WAV normalises to -1..1', () {
      final audio = decodeAudio(
        _wav(
          channels: 1,
          rate: 16000,
          bits: 16,
          data: _i16([0, 16384, -32768, 32767]),
        ),
      );
      expect(audio.sampleRate, 16000);
      expect(audio.samples[1], closeTo(0.5, 1e-6));
      expect(audio.samples[2], -1.0);
      expect(audio.samples[3], closeTo(1.0, 1e-4));
    });

    test('stereo is averaged to mono', () {
      final audio = decodeAudio(
        _wav(
          channels: 2,
          rate: 16000,
          bits: 16,
          data: _i16([16384, 0, -16384, -16384]),
        ),
      );
      expect(audio.samples.length, 2);
      expect(audio.samples[0], closeTo(0.25, 1e-6));
      expect(audio.samples[1], closeTo(-0.5, 1e-6));
    });

    test('PCM32, float32 and 24-bit WAV', () {
      final p32 =
          ByteData(8)
            ..setInt32(0, 1 << 30, Endian.little)
            ..setInt32(4, -(1 << 30), Endian.little);
      expect(
        decodeAudio(
          p32.buffer.asUint8List(),
          format: AudioFormat.pcm32,
        ).samples,
        [0.5, -0.5],
      );
      final f32 =
          ByteData(8)
            ..setFloat32(0, 0.25, Endian.little)
            ..setFloat32(4, -0.75, Endian.little);
      expect(
        decodeAudio(
          f32.buffer.asUint8List(),
          format: AudioFormat.float32,
        ).samples,
        [0.25, -0.75],
      );
      final floatWav = _wav(
        channels: 1,
        rate: 16000,
        bits: 32,
        format: 3,
        data: f32.buffer.asUint8List(),
      );
      expect(decodeAudio(floatWav).samples, [0.25, -0.75]);
      final p24 = _wav(
        channels: 1,
        rate: 16000,
        bits: 24,
        data: Uint8List.fromList([0, 0, 0x40, 0, 0, 0xC0]),
      );
      expect(decodeAudio(p24).samples, [0.5, -0.5]);
    });

    test('raw PCM16 uses the given rate; sniff picks the right format', () {
      final raw = _i16([100, 200]);
      expect(AudioFormat.sniff(raw), AudioFormat.pcm16);
      expect(
        AudioFormat.sniff(_wav(channels: 1, rate: 8000, bits: 16, data: raw)),
        AudioFormat.wav,
      );
      expect(decodeAudio(raw, sampleRate: 8000).sampleRate, 8000);
    });

    test('encodeWav16 and wrapPcm16AsWav round-trip', () {
      final tone = sine(440, 16000, 0.1);
      final decoded = decodeAudio(encodeWav16(tone, 16000));
      expect(decoded.sampleRate, 16000);
      expect(decoded.samples.length, tone.length);
      for (var i = 0; i < tone.length; i++) {
        expect(decoded.samples[i], closeTo(tone[i], 1e-4));
      }
      final wrapped = decodeAudio(wrapPcm16AsWav(toPcm16(tone), 22050));
      expect(wrapped.sampleRate, 22050);
      expect(wrapped.samples.length, tone.length);
    });
  });

  group('resample', () {
    test('same rate returns the input unchanged', () {
      final x = sine(100, 16000, 0.1);
      expect(identical(resample(x, 16000, 16000), x), isTrue);
    });

    test('output length follows the rate ratio', () {
      final x = sine(100, 48000, 1);
      expect(resample(x, 48000, 16000).length, 16000);
      expect(resample(sine(100, 8000, 1), 8000, 16000).length, 16000);
    });

    test('downsampling keeps a 440 Hz tone intact', () {
      final out = resample(sine(440, 44100, 1), 44100, 16000);
      expect(out.length, 16000);
      // RMS of a 0.5-amplitude sine is 0.5/sqrt(2); box filtering costs a little.
      expect(rms(out), closeTo(0.5 / math.sqrt2, 0.02));
      // Zero crossings ~= 2 * frequency.
      var crossings = 0;
      for (var i = 1; i < out.length; i++) {
        if ((out[i - 1] < 0) != (out[i] < 0)) crossings++;
      }
      expect(crossings, inInclusiveRange(870, 890));
    });

    test('downsampling attenuates content above the new Nyquist', () {
      // 20 kHz at 48 kHz would alias to 4 kHz at 16 kHz without a filter.
      final out = resample(sine(20000, 48000, 0.5), 48000, 16000);
      expect(rms(out), lessThan(0.25));
    });

    test('upsampling interpolates linearly', () {
      final out = resample(Float32List.fromList([0, 1]), 1, 2);
      expect(out.toList(), [0.0, 0.5, 1.0, 1.0]);
    });
  });
}
