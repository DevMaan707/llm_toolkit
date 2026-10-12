import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/gguf/gguf_metadata.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

import 'gguf_builder.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('gguf_meta'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads common fields from a file', () async {
    final bytes =
        GgufBuilder()
            .transformer(
              arch: 'qwen2',
              context: 32768,
              embedding: 896,
              blocks: 24,
              heads: 14,
              kvHeads: 2,
            )
            .u32('general.file_type', 15)
            .u32('qwen2.attention.key_length', 64)
            .u32('qwen2.attention.value_length', 64)
            .u32('qwen2.attention.sliding_window', 1024)
            .string('tokenizer.chat_template', '<|im_start|>{{ x }}')
            .stringArray('tokenizer.ggml.tokens', ['a', 'bb', 'ccc', ''])
            .build();
    final f = File('${dir.path}/m.gguf')..writeAsBytesSync(bytes);
    final m = await GgufMetadata.read(f.path);
    expect(m.version, 3);
    expect(m.tensorCount, 7);
    expect(m.architecture, 'qwen2');
    expect(m.name, 'Test qwen2');
    expect(m.contextLength, 32768);
    expect(m.embeddingLength, 896);
    expect(m.blockCount, 24);
    expect(m.headCount, 14);
    expect(m.headCountKv, 2);
    expect(m.keyLength, 64);
    expect(m.valueLength, 64);
    expect(m.slidingWindow, 1024);
    expect(m.fileType, 15);
    expect(m.quantization, 'Q4_K_M');
    expect(m.vocabSize, 4);
    expect(m.chatTemplate, '<|im_start|>{{ x }}');
    expect(m.values.containsKey('tokenizer.ggml.tokens'), isFalse);
    expect(m.isEmbeddingModel, isFalse);
  });

  test(
    'missing fields are null and metadata after the vocab is read',
    () async {
      final m = await GgufMetadata.fromBytes(
        GgufBuilder()
            .string('general.architecture', 'bert')
            .stringArray('tokenizer.ggml.tokens', List.filled(1000, 'tok'))
            .u32('bert.context_length', 512)
            .build(),
      );
      expect(m.isEmbeddingModel, isTrue);
      expect(m.contextLength, 512);
      expect(m.chatTemplate, isNull);
      expect(m.quantization, isNull);
      expect(m.headCountKv, isNull);
      expect(m.vocabSize, 1000);
    },
  );

  test('empty chat template counts as absent', () async {
    final m = await GgufMetadata.fromBytes(
      GgufBuilder()
          .transformer()
          .string('tokenizer.chat_template', '  ')
          .build(),
    );
    expect(m.chatTemplate, isNull);
  });

  test('per-layer head_count_kv arrays use the maximum', () async {
    final m = await GgufMetadata.fromBytes(
      GgufBuilder().string('general.architecture', 'x').u32Array(
        'x.attention.head_count_kv',
        [0, 8, 0, 4],
      ).build(),
    );
    expect(m.headCountKv, 8);
  });

  test('skips scalars of every width and bool arrays', () async {
    final m = await GgufMetadata.fromBytes(
      GgufBuilder()
          .f32('a.f', 1.5)
          .u64('a.big', 1 << 40)
          .boolean('a.flag', true)
          .boolArray('x.attention.sliding_window_pattern', [true, false])
          .string('general.architecture', 'x')
          .build(),
    );
    expect(m.values['a.f'], 1.5);
    expect(m.values['a.big'], 1 << 40);
    expect(m.values['a.flag'], true);
    expect(m.slidingLayerFlags, [true, false]);
  });

  test('accepts version 2 and rejects others', () async {
    expect(
      (await GgufMetadata.fromBytes(GgufBuilder(version: 2).build())).version,
      2,
    );
    expect(
      GgufMetadata.fromBytes(GgufBuilder(version: 1).build()),
      throwsA(isA<InferenceException>()),
    );
  });

  test('rejects bad magic, tiny, truncated and missing files', () async {
    expect(
      GgufMetadata.fromBytes(Uint8List(64)),
      throwsA(isA<InferenceException>()),
    );
    expect(
      GgufMetadata.fromBytes(Uint8List.fromList([71, 71])),
      throwsA(isA<InferenceException>()),
    );
    final full = GgufBuilder().transformer().build();
    expect(
      GgufMetadata.fromBytes(Uint8List.sublistView(full, 0, full.length - 10)),
      throwsA(isA<InferenceException>()),
    );
    expect(
      GgufMetadata.read('${dir.path}/none.gguf'),
      throwsA(isA<InferenceException>()),
    );
  });

  test('large vocab file streams without storing tokens', () async {
    final tokens = List.generate(200000, (i) => 'token$i');
    final f = File('${dir.path}/big.gguf')..writeAsBytesSync(
      GgufBuilder()
          .stringArray('tokenizer.ggml.tokens', tokens)
          .string('general.architecture', 'llama')
          .build(),
    );
    final m = await GgufMetadata.read(f.path);
    expect(m.vocabSize, 200000);
    expect(m.architecture, 'llama');
  });
}
