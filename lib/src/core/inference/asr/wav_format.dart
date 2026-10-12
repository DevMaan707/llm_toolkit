import 'dart:typed_data';

import '../../../exceptions/llm_toolkit_exceptions.dart';

/// Sample encodings understood by the decoder.
enum AudioFormat {
  /// RIFF/WAVE container (PCM 8/16/24/32-bit or IEEE float32).
  wav,

  /// Raw little-endian signed 16-bit PCM.
  pcm16,

  /// Raw little-endian signed 32-bit PCM.
  pcm32,

  /// Raw little-endian IEEE float32.
  float32;

  /// [wav] when [bytes] start with a RIFF/WAVE header, otherwise [pcm16].
  static AudioFormat sniff(Uint8List bytes) =>
      hasWavHeader(bytes) ? wav : pcm16;
}

/// True when [bytes] begin with `RIFF....WAVE`.
bool hasWavHeader(Uint8List bytes) =>
    bytes.length >= 12 && _tag(bytes, 0) == 'RIFF' && _tag(bytes, 8) == 'WAVE';

/// Parsed `fmt ` and `data` chunk information of a WAV file.
class WavInfo {
  final int channels;
  final int sampleRate;
  final int bitsPerSample;

  /// True for IEEE float samples, false for integer PCM.
  final bool isFloat;

  /// Byte offset of the first sample frame.
  final int dataOffset;

  /// Byte length of the sample data actually present in the file.
  final int dataLength;

  const WavInfo({
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.isFloat,
    required this.dataOffset,
    required this.dataLength,
  });

  int get bytesPerFrame => channels * bitsPerSample ~/ 8;
}

/// Walks the RIFF chunks of [bytes]. Tolerates extra chunks (LIST, fact...),
/// odd-sized chunk padding, and a data size that is zero/0xFFFFFFFF/too large
/// (as written by streaming recorders).
WavInfo parseWav(Uint8List bytes) {
  if (!hasWavHeader(bytes)) {
    throw const InferenceException('Not a WAV file: missing RIFF/WAVE header');
  }
  final view = ByteData.sublistView(bytes);
  var offset = 12;
  int? channels, sampleRate, bits;
  var isFloat = false;

  while (offset + 8 <= bytes.length) {
    final id = _tag(bytes, offset);
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;

    if (id == 'fmt ') {
      if (size < 16 || body + 16 > bytes.length) {
        throw InferenceException('Invalid WAV fmt chunk (size $size)');
      }
      var format = view.getUint16(body, Endian.little);
      if (format == 0xFFFE && size >= 26 && body + 26 <= bytes.length) {
        format = view.getUint16(body + 24, Endian.little);
      }
      if (format != 1 && format != 3) {
        throw InferenceException(
          'Unsupported WAV encoding $format (only PCM and float)',
        );
      }
      isFloat = format == 3;
      channels = view.getUint16(body + 2, Endian.little);
      sampleRate = view.getUint32(body + 4, Endian.little);
      bits = view.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (channels == null || sampleRate == null || bits == null) {
        throw const InferenceException('WAV data chunk before fmt chunk');
      }
      if (channels < 1 || sampleRate < 1) {
        throw const InferenceException('Invalid WAV channel count or rate');
      }
      final supported =
          isFloat ? bits == 32 : const {8, 16, 24, 32}.contains(bits);
      if (!supported) {
        throw InferenceException(
          'Unsupported WAV bit depth: $bits (${isFloat ? 'float' : 'PCM'})',
        );
      }
      final available = bytes.length - body;
      final declared = (size == 0 || size > available) ? available : size;
      final frame = channels * bits ~/ 8;
      return WavInfo(
        channels: channels,
        sampleRate: sampleRate,
        bitsPerSample: bits,
        isFloat: isFloat,
        dataOffset: body,
        dataLength: declared - declared % frame,
      );
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw const InferenceException('WAV file has no data chunk');
}

/// Encodes mono [samples] (-1..1) as a 16-bit PCM WAV file.
Uint8List encodeWav16(Float32List samples, int sampleRate) {
  final dataLength = samples.length * 2;
  final out = ByteData(44 + dataLength);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + dataLength, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  out.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * 32768).round().clamp(-32768, 32767);
    out.setInt16(44 + i * 2, v, Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Prepends a WAV header to raw mono PCM16 bytes.
Uint8List wrapPcm16AsWav(Uint8List pcm, int sampleRate) {
  final out = Uint8List(44 + pcm.length);
  final header = encodeWav16(Float32List(0), sampleRate);
  out.setRange(0, 44, header);
  final view = ByteData.sublistView(out);
  view.setUint32(4, 36 + pcm.length, Endian.little);
  view.setUint32(40, pcm.length, Endian.little);
  out.setRange(44, out.length, pcm);
  return out;
}

String _tag(Uint8List b, int at) => String.fromCharCodes(b, at, at + 4);
