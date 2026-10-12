import 'dart:typed_data';

import '../../../exceptions/llm_toolkit_exceptions.dart';
import 'resampler.dart';
import 'wav_format.dart';

/// Mono float samples in -1..1 together with their sample rate.
class DecodedAudio {
  final Float32List samples;
  final int sampleRate;

  const DecodedAudio(this.samples, this.sampleRate);

  Duration get duration =>
      Duration(microseconds: samples.length * 1000000 ~/ sampleRate);

  /// This audio converted to [rate] Hz.
  DecodedAudio resampledTo(int rate) =>
      sampleRate == rate
          ? this
          : DecodedAudio(resample(samples, sampleRate, rate), rate);
}

/// Decodes [bytes] to mono float samples.
///
/// A WAV container carries its own rate and channel layout; for the raw
/// formats pass [sampleRate] (and [channels] if interleaved).
DecodedAudio decodeAudio(
  Uint8List bytes, {
  AudioFormat? format,
  int sampleRate = 16000,
  int channels = 1,
}) {
  final fmt = format ?? AudioFormat.sniff(bytes);
  if (fmt == AudioFormat.wav) {
    final info = parseWav(bytes);
    final data = Uint8List.sublistView(
      bytes,
      info.dataOffset,
      info.dataOffset + info.dataLength,
    );
    final samples = _toMono(
      data,
      info.channels,
      info.isFloat ? _Encoding.float32 : _pcmEncoding(info.bitsPerSample),
    );
    return DecodedAudio(samples, info.sampleRate);
  }
  final encoding = switch (fmt) {
    AudioFormat.pcm16 => _Encoding.pcm16,
    AudioFormat.pcm32 => _Encoding.pcm32,
    _ => _Encoding.float32,
  };
  return DecodedAudio(_toMono(bytes, channels, encoding), sampleRate);
}

enum _Encoding {
  pcm8(1),
  pcm16(2),
  pcm24(3),
  pcm32(4),
  float32(4);

  final int bytes;
  const _Encoding(this.bytes);
}

_Encoding _pcmEncoding(int bits) => switch (bits) {
  8 => _Encoding.pcm8,
  16 => _Encoding.pcm16,
  24 => _Encoding.pcm24,
  _ => _Encoding.pcm32,
};

/// Interleaved little-endian [data] -> mono floats (channels averaged).
Float32List _toMono(Uint8List data, int channels, _Encoding encoding) {
  if (channels < 1) {
    throw InferenceException('Invalid channel count: $channels');
  }
  final view = ByteData.sublistView(data);
  final frameBytes = encoding.bytes * channels;
  final frames = data.length ~/ frameBytes;
  final out = Float32List(frames);

  double read(int at) => switch (encoding) {
    _Encoding.pcm8 => (view.getUint8(at) - 128) / 128,
    _Encoding.pcm16 => view.getInt16(at, Endian.little) / 32768,
    _Encoding.pcm24 => _int24(view, at) / 8388608,
    _Encoding.pcm32 => view.getInt32(at, Endian.little) / 2147483648,
    _Encoding.float32 => view.getFloat32(at, Endian.little),
  };

  for (var f = 0; f < frames; f++) {
    final base = f * frameBytes;
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += read(base + c * encoding.bytes);
    }
    out[f] = sum / channels;
  }
  return out;
}

int _int24(ByteData v, int at) {
  final u =
      v.getUint8(at) | (v.getUint8(at + 1) << 8) | (v.getUint8(at + 2) << 16);
  return u >= 0x800000 ? u - 0x1000000 : u;
}

/// Mono PCM16 little-endian bytes -> floats.
Float32List pcm16ToFloat(Uint8List pcm) =>
    decodeAudio(pcm, format: AudioFormat.pcm16).samples;
