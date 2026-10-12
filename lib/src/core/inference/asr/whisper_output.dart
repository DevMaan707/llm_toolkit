import 'dart:typed_data';

import '../../../exceptions/llm_toolkit_exceptions.dart';

/// Element type of the model's first output tensor.
enum OutputKind { int32, int64, float32 }

/// Turns the raw bytes of a Whisper TFLite output tensor into token ids.
///
/// End-to-end exports emit ids directly (`int32`/`int64`, shape `[1, T]`);
/// others emit logits (`float32`, shape `[1, T, vocab]`) which are decoded
/// greedily. At most [maxTokens] ids are returned.
List<int> tokenIdsFromOutput(
  Uint8List bytes,
  OutputKind kind,
  List<int> shape, {
  required int maxTokens,
}) {
  final view = ByteData.sublistView(bytes);
  switch (kind) {
    case OutputKind.int32:
      final n = bytes.length ~/ 4;
      return [
        for (var i = 0; i < n && i < maxTokens; i++)
          view.getInt32(i * 4, Endian.little),
      ];
    case OutputKind.int64:
      final n = bytes.length ~/ 8;
      return [
        for (var i = 0; i < n && i < maxTokens; i++)
          view.getInt64(i * 8, Endian.little),
      ];
    case OutputKind.float32:
      if (shape.length < 2 || shape.last <= 0) {
        throw InferenceException('Unexpected logits shape: $shape');
      }
      final vocab = shape.last;
      final steps = bytes.length ~/ 4 ~/ vocab;
      return [
        for (var t = 0; t < steps && t < maxTokens; t++)
          _argmax(view, t * vocab, vocab),
      ];
  }
}

int _argmax(ByteData view, int start, int count) {
  var best = 0;
  var bestValue = double.negativeInfinity;
  for (var i = 0; i < count; i++) {
    final v = view.getFloat32((start + i) * 4, Endian.little);
    if (v > bestValue) {
      bestValue = v;
      best = i;
    }
  }
  return best;
}
