import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/asr/asr.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

void main() {
  // GPT-2 byte-level: space is "Ġ", "é" is the two bytes C3 A9 -> "Ã©".
  final vocab = jsonEncode({
    'Hello': 0,
    'Ġworld': 1,
    'Ã©': 2,
    '!': 3,
    '<|endoftext|>': 7,
    '<|startoftranscript|>': 8,
  });
  final tokenizer = WhisperTokenizer.fromJson(vocab);

  group('WhisperTokenizer', () {
    test('joins byte-level tokens and restores spaces', () {
      expect(tokenizer.decode([0, 1, 3]), 'Hello world!');
    });

    test('decodes multi-byte UTF-8 through the byte mapping', () {
      expect(tokenizer.decode([0, 2]), 'Helloé');
    });

    test('stops at end-of-text and skips special or unknown ids', () {
      expect(tokenizer.decode([8, 0, 99, 1, 7, 3]), 'Hello world');
      expect(tokenizer.eotId, 7);
      expect(tokenizer.isSpecial(8), isTrue);
      expect(tokenizer.isSpecial(3), isFalse);
    });

    test('rejects malformed vocabularies', () {
      expect(
        () => WhisperTokenizer.fromJson('nope'),
        throwsA(isA<InferenceException>()),
      );
      expect(
        () => WhisperTokenizer.fromJson('[]'),
        throwsA(isA<InferenceException>()),
      );
    });
  });

  group('tokenIdsFromOutput', () {
    test('int32 ids', () {
      final b = ByteData(16);
      for (var i = 0; i < 4; i++) {
        b.setInt32(i * 4, i + 10, Endian.little);
      }
      expect(
        tokenIdsFromOutput(b.buffer.asUint8List(), OutputKind.int32, [
          1,
          4,
        ], maxTokens: 100),
        [10, 11, 12, 13],
      );
      expect(
        tokenIdsFromOutput(b.buffer.asUint8List(), OutputKind.int32, [
          1,
          4,
        ], maxTokens: 2),
        [10, 11],
      );
    });

    test('int64 ids', () {
      final b =
          ByteData(16)
            ..setInt64(0, 5, Endian.little)
            ..setInt64(8, 6, Endian.little);
      expect(
        tokenIdsFromOutput(b.buffer.asUint8List(), OutputKind.int64, [
          1,
          2,
        ], maxTokens: 9),
        [5, 6],
      );
    });

    test('float32 logits are decoded greedily per step', () {
      final logits = [
        [0.1, 0.9, 0.0],
        [2.0, 1.0, 0.0],
        [-1.0, -2.0, -0.5],
      ];
      final b = ByteData(9 * 4);
      var o = 0;
      for (final step in logits) {
        for (final v in step) {
          b.setFloat32(o, v, Endian.little);
          o += 4;
        }
      }
      expect(
        tokenIdsFromOutput(b.buffer.asUint8List(), OutputKind.float32, [
          1,
          3,
          3,
        ], maxTokens: 9),
        [1, 0, 2],
      );
    });

    test('float32 needs a usable shape', () {
      expect(
        () => tokenIdsFromOutput(Uint8List(8), OutputKind.float32, [
          4,
        ], maxTokens: 1),
        throwsA(isA<InferenceException>()),
      );
    });
  });

  group('ASRConfig', () {
    test('presets differ and sample counts follow the durations', () {
      const c = ASRConfig();
      expect(c.chunkSamples, 160000);
      expect(c.overlapSamples, 32000);
      expect(
        const ASRConfig.lowLatency().chunkDuration,
        lessThan(c.chunkDuration),
      );
      expect(
        const ASRConfig.highQuality().chunkDuration,
        greaterThan(c.chunkDuration),
      );
      expect(const ASRConfig.mobile().enableVAD, isTrue);
      expect(c.copyWith(sampleRate: 8000).chunkSamples, 80000);
    });
  });
}
