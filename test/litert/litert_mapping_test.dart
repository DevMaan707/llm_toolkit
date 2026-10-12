import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/config.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';
import 'package:llm_toolkit/src/core/inference/litert/litert_mapping.dart';

void main() {
  test('file type follows extension', () {
    expect(litertFileTypeFor('/m/a.litertlm'), ModelFileType.litertlm);
    expect(litertFileTypeFor('/m/A.TASK'), ModelFileType.task);
    expect(litertFileTypeFor('/m/a.tflite'), ModelFileType.binary);
  });

  test('model type from family and path', () {
    expect(litertModelTypeFor(ModelFamily.gemma), ModelType.gemmaIt);
    expect(
      litertModelTypeFor(ModelFamily.gemma, path: 'gemma-4-E2B.litertlm'),
      ModelType.gemma4,
    );
    expect(
      litertModelTypeFor(ModelFamily.qwen, path: 'Qwen3-0.6B.litertlm'),
      ModelType.qwen3,
    );
    expect(litertModelTypeFor(ModelFamily.qwen), ModelType.qwen);
    expect(litertModelTypeFor(ModelFamily.deepSeek), ModelType.deepSeek);
    expect(litertModelTypeFor(ModelFamily.generic), ModelType.general);
  });

  test('backend mapping', () {
    expect(litertBackendFor(null), isNull);
    expect(litertBackendFor(ComputeBackend.gpu), PreferredBackend.gpu);
    expect(litertBackendFor(ComputeBackend.npu), PreferredBackend.npu);
    expect(litertBackendFor(ComputeBackend.cpu), PreferredBackend.cpu);
  });

  test('context window is at least 1024 for litertlm', () {
    const small = InferenceConfig(contextSize: 512);
    expect(litertContextWindow(small, ModelFileType.litertlm), 1024);
    expect(litertContextWindow(small, ModelFileType.task), 512);
    expect(
      litertContextWindow(const InferenceConfig(), ModelFileType.litertlm),
      litertDefaultContextTokens,
    );
    expect(
      litertContextWindow(
        const InferenceConfig(maxTokens: 4096),
        ModelFileType.litertlm,
      ),
      4096,
    );
  });

  test('sampling is clamped to valid ranges', () {
    final s = litertSamplingFor(
      const GenerationParams(temperature: -1, topK: 0, topP: 1.5, seed: 3),
    );
    expect(s.temperature, 0);
    expect(s.topK, 1);
    expect(s.topP, 1);
    expect(s.randomSeed, 3);
    expect(() => s.validate(), returnsNormally);
    expect(litertSamplingFor(const GenerationParams(topP: 0)).topP, isNull);
  });

  test('max output tokens never exceeds the context', () {
    expect(
      litertMaxOutputTokens(const GenerationParams(maxTokens: 9000), 2048),
      2048,
    );
    expect(
      litertMaxOutputTokens(const GenerationParams(maxTokens: 100), 2048),
      100,
    );
  });

  group('transcript', () {
    test('system turns become the system prompt, roles are explicit', () {
      final t = litertTranscriptFrom([
        const ChatTurn('system', 'be brief'),
        const ChatTurn('user', 'hi'),
        const ChatTurn('assistant', 'hello'),
        const ChatTurn('user', 'bye'),
      ]);
      expect(t.system, 'be brief');
      expect(t.messages.map((m) => m.isUser), [true, false, true]);
    });

    test('images are attached', () {
      final m = litertMessageFrom(
        ChatTurn(
          'user',
          'look',
          images: [
            Uint8List.fromList([1, 2]),
          ],
        ),
      );
      expect(m.hasImage, isTrue);
      expect(m.images, hasLength(1));
    });

    test('must end with a user turn', () {
      expect(
        () => litertTranscriptFrom([const ChatTurn('assistant', 'x')]),
        throwsArgumentError,
      );
      expect(() => litertTranscriptFrom(const []), throwsArgumentError);
    });
  });

  group('stop sequences', () {
    Future<String> run(List<String> chunks, List<String> stops) async =>
        (await litertApplyStopSequences(
              Stream.fromIterable(chunks),
              stops,
            ).toList())
            .join();

    test('passes through without stops', () async {
      expect(await run(['a', 'b'], []), 'ab');
    });

    test('cuts at a stop inside a chunk', () async {
      expect(await run(['hello END tail'], ['END']), 'hello ');
    });

    test('cuts at a stop split across chunks', () async {
      expect(await run(['hello E', 'N', 'D more'], ['END']), 'hello ');
    });

    test('flushes held-back text when no stop appears', () async {
      expect(await run(['hello E', 'N'], ['END']), 'hello EN');
    });

    test('earliest stop wins', () async {
      expect(await run(['a<b>c</s>'], ['</s>', '<b>']), 'a');
    });
  });
}
