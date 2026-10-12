import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/llm_toolkit.dart';

class _FakeLlm implements InferenceEngine, TextGenerator {
  bool loaded = false;
  @override
  String get id => 'fake';
  @override
  Set<ModelCapability> get capabilities => {ModelCapability.textGeneration};
  @override
  bool get isModelLoaded => loaded;
  @override
  String? get currentModelPath => loaded ? 'm' : null;
  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async =>
      loaded = true;
  @override
  Future<void> unloadModel() async => loaded = false;
  @override
  Stream<String> generateText(String prompt, GenerationParams params) =>
      Stream.fromIterable(['echo: ', prompt]);
}

void main() {
  group('ModelDetector', () {
    const d = ModelDetector.instance;
    test('routes by extension and name', () {
      expect(d.detect('/a/llama-3.Q4_K_M.gguf').engineId, 'llama');
      expect(d.detect('/a/gemma-3n.litertlm').engineId, 'litert');
      expect(d.detect('/a/whisper-tiny.tflite').engineId, 'asr');
      expect(d.detect('/a/nomic-embed-text.gguf').capabilities, {
        ModelCapability.embeddings,
      });
      expect(d.detect('/a/qwen2.gguf').family, ModelFamily.qwen);
    });
  });

  group('LLMToolkit', () {
    test('loads a custom engine and routes capabilities', () async {
      final toolkit =
          LLMToolkit.instance
            ..initialize(registerDefaultEngines: false)
            ..registerEngine(_FakeLlm());
      expect(
        () => toolkit.generateText('x').toList(),
        throwsA(isA<InferenceException>()),
      );
      await toolkit.loadModel('any.bin', engineId: 'fake');
      expect(toolkit.capabilities, contains(ModelCapability.textGeneration));
      expect((await toolkit.generateText('hi').toList()).join(), 'echo: hi');
      await toolkit.dispose();
      expect(toolkit.hasLoadedModel, isFalse);
    });

    test('missing capability reports clearly', () {
      expect(
        () => LLMToolkit.instance.generateImage(
          const ImageGenerationRequest(prompt: 'cat'),
        ),
        throwsA(isA<InferenceException>()),
      );
    });
  });
}
