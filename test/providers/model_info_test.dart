import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/model_info.dart';

ModelFile file(String name, int? size) =>
    ModelFile(filename: name, downloadUrl: 'https://x/$name', sizeBytes: size);

void main() {
  group('quantization', () {
    test('parses common GGUF labels', () {
      expect(ModelNaming.quantization('gemma-3-1b-it-Q4_K_M.gguf'), 'Q4_K_M');
      expect(
        ModelNaming.quantization('llama-3.2-1b-instruct-q8_0.gguf'),
        'Q8_0',
      );
      expect(ModelNaming.quantization('x/model.IQ3_XXS.gguf'), 'IQ3_XXS');
      expect(ModelNaming.quantization('Qwen3-Q4_K_XL.gguf'), 'Q4_K_XL');
      expect(ModelNaming.quantization('gemma-3-1b-it-BF16.gguf'), 'BF16');
      expect(ModelNaming.quantization('foo-UD-Q2_K_L.gguf'), 'Q2_K_L');
      expect(ModelNaming.quantization('gemma-cpu-int4.task'), 'INT4');
    });

    test('ignores names without a label', () {
      expect(
        ModelNaming.quantization('Qwen2.5-1.5B-Instruct.litertlm'),
        isNull,
      );
      expect(ModelNaming.quantization('model.gguf'), isNull);
    });
  });

  group('parameter count', () {
    test('parses sizes', () {
      expect(ModelNaming.parameterCount('Llama-3.1-8B-Instruct'), 8000000000);
      expect(ModelNaming.parameterCount('Qwen2.5-1.5B-Instruct'), 1500000000);
      expect(ModelNaming.parameterCount('gemma-3-270m-it'), 270000000);
      expect(ModelNaming.parameterCount('gemma-4-E2B-it'), 2000000000);
      expect(ModelNaming.parameterCount('Mixtral-8x7B-v0.1'), 56000000000);
      expect(ModelNaming.parameterCount('Qwen3-30B-A3B'), 30000000000);
    });

    test('does not mistake other numbers for sizes', () {
      expect(ModelNaming.parameterCount('gemma-3-it'), isNull);
      expect(ModelNaming.parameterCount('model-4bit'), isNull);
      expect(ModelNaming.parameterCount('llama-3.1-instruct-128k'), isNull);
    });
  });

  test('format and shard detection', () {
    expect(ModelFormat.fromFilename('A.GGUF'), ModelFormat.gguf);
    expect(ModelFormat.fromFilename('a.litertlm'), ModelFormat.litertlm);
    expect(ModelFormat.fromFilename('README.md'), isNull);
    final shard = file('m-Q4_K_M-00002-of-00003.gguf', 1);
    expect(shard.shard, (2, 3));
    expect(shard.isLoadable, isFalse);
    expect(file('mmproj-f16.gguf', 1).isLoadable, isFalse);
    expect(file('m.safetensors', 1).isLoadable, isFalse);
    expect(file('m.onnx', 1).isLoadable, isTrue);
  });

  test('formatBytes', () {
    expect(formatBytes(null), 'unknown');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  group('recommendedFileFor', () {
    const gb = 1024 * 1024 * 1024;
    final model = ModelInfo(
      id: 'a/b',
      name: 'b',
      provider: 'test',
      files: [
        file('b-Q2_K.gguf', 1 * gb),
        file('b-Q4_K_M.gguf', 2 * gb),
        file('b-Q8_0.gguf', 4 * gb),
        file('b-Q4_K_M-00001-of-00002.gguf', 3 * gb),
        file('b-unknown.gguf', null),
        file('b.safetensors', 1 * gb),
      ],
    );

    test('picks the largest file that fits with overhead', () {
      expect(model.recommendedFileFor(3 * gb)!.quantization, 'Q4_K_M');
      expect(model.recommendedFileFor(8 * gb)!.quantization, 'Q8_0');
    });

    test('returns null when nothing fits', () {
      expect(model.recommendedFileFor(1 * gb), isNull);
    });

    test('can be limited to a format', () {
      expect(
        model.recommendedFileFor(8 * gb, format: ModelFormat.onnx),
        isNull,
      );
    });
  });

  test('totalSizeBytes is null when any size is unknown', () {
    final m = ModelInfo(
      id: 'a',
      name: 'a',
      provider: 't',
      files: [file('a.gguf', 5), file('b.gguf', null)],
    );
    expect(m.totalSizeBytes, isNull);
    expect(m.copyWith(files: [file('a.gguf', 5)]).totalSizeBytes, 5);
  });
}
