import 'dart:math' as math;
import 'dart:typed_data';

/// Mono sine wave in -1..1.
Float32List sine(
  double hz,
  int sampleRate,
  double seconds, {
  double amp = 0.5,
}) {
  final n = (sampleRate * seconds).round();
  return Float32List.fromList([
    for (var i = 0; i < n; i++)
      amp * math.sin(2 * math.pi * hz * i / sampleRate),
  ]);
}

/// Mono samples as little-endian PCM16 bytes.
Uint8List toPcm16(Float32List samples) {
  final out = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(i * 2, (samples[i] * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}
