library llm_toolkit;

export 'src/core/base_provider.dart';
export 'src/core/model_info.dart';
export 'src/core/config.dart';
export 'src/core/search_query.dart';
export 'src/core/model_detector.dart';
export 'src/exceptions/llm_toolkit_exceptions.dart';
import 'package:llm_toolkit/src/core/inference/llama_engine.dart';
export 'package:flutter_gemma/flutter_gemma.dart';

import 'src/core/base_provider.dart';
import 'src/core/inference/inference_manager.dart';
import 'src/core/inference/gemma_engine.dart';
import 'src/core/inference/tflite_engine.dart';
import 'src/core/inference/tflite_asr_engine.dart';
import 'src/core/model_info.dart';
import 'src/core/config.dart';
import 'src/core/providers/huggingface/hf_provider.dart';
import 'src/core/search_query.dart';
import 'src/core/model_detector.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
export 'package:flutter_gemma/pigeon.g.dart';

class LLMToolkit {
  static LLMToolkit? _instance;
  static LLMToolkit get instance => _instance ??= LLMToolkit._();

  LLMToolkit._();

  final Map<String, BaseModelProvider> _providers = {};
  final InferenceManager _inferenceManager = InferenceManager();
  InferenceConfig _defaultConfig = InferenceConfig.defaultConfig();

  void initialize({String? huggingFaceApiKey, InferenceConfig? defaultConfig}) {
    // Register providers
    _providers['huggingface'] = HuggingFaceProvider(apiKey: huggingFaceApiKey);

    // Register all inference engines
    _inferenceManager.registerEngine('llama', LlamaInferenceEngine());
    _inferenceManager.registerEngine('gemma', GemmaInferenceEngine());
    _inferenceManager.registerEngine('tflite', TFLiteInferenceEngine());
    _inferenceManager.registerEngine('tfliteASR', TFLiteASREngine());

    if (defaultConfig != null) {
      _defaultConfig = defaultConfig;
    }

    print(
      '🚀 LLM Toolkit initialized with Llama, Gemma, TFLite, and ASR engines',
    );
  }

  // Rest of your methods remain the same...
  Future<List<ModelInfo>> searchModels(
    String query, {
    String? provider,
    ModelFormat? format,
    int limit = 20,
    bool onlyCompatible = true,
  }) async {
    final searchQuery = SearchQuery(
      searchTerm: query,
      formats: format != null ? [format] : [],
      limit: limit,
      onlyCompatible: onlyCompatible,
    );

    if (provider != null) {
      final p = _providers[provider];
      if (p == null) throw Exception('Provider $provider not found');
      return await p.searchModels(searchQuery);
    }

    final results = <ModelInfo>[];
    for (final p in _providers.values) {
      try {
        final providerResults = await p.searchModels(searchQuery);
        results.addAll(providerResults);
      } catch (e) {
        print('Error searching provider: $e');
      }
    }

    results.sort((a, b) => b.downloads.compareTo(a.downloads));
    return results;
  }

  Future<String> downloadModel(
    ModelInfo model,
    String filename, {
    ProgressCallback? onProgress,
  }) async {
    final provider = _providers[model.provider];
    if (provider == null) {
      throw Exception('Provider ${model.provider} not available');
    }

    return await provider.downloadModel(
      model.id,
      filename,
      onProgress: onProgress,
    );
  }

  Future<void> loadModel(
    String modelPath, {
    InferenceConfig? config,
    String? forceEngine,
  }) async {
    final detectedEngine = ModelDetector.instance.detectEngine(modelPath);
    print(
      '🔍 Detected engine for ${modelPath.split('/').last}: ${detectedEngine.name}',
    );

    await _inferenceManager.loadModel(
      modelPath,
      config ?? _defaultConfig,
      engineName: forceEngine,
    );
  }

  Stream<String> generateText(String prompt, {GenerationParams? params}) {
    return _inferenceManager.generateText(
      prompt,
      params ?? GenerationParams.longForm(),
    );
  }

  Stream<String> generateMultimodalResponse(
    String prompt,
    List<String> imagePaths, {
    GenerationParams? params,
  }) {
    return _inferenceManager.generateMultimodalResponse(
      prompt,
      imagePaths,
      params ?? GenerationParams.longForm(),
    );
  }

  Future<InferenceModel> createChatInstance({
    double? temperature,
    int? randomSeed,
    int? topK,
  }) async {
    return await _inferenceManager.createChatInstance(
      temperature: temperature,
      randomSeed: randomSeed,
      topK: topK,
    );
  }

  Future<List<double>> generateEmbedding(String text) async {
    return await _inferenceManager.generateEmbedding(text);
  }

  Future<String> transcribeAudio(List<int> audioBytes) async {
    return await _inferenceManager.transcribeAudio(audioBytes);
  }

  InferenceEngineType? get activeEngine => _inferenceManager.activeEngineType;
  bool get hasLoadedModel => _inferenceManager.hasActiveModel;

  Future<void> dispose() async {
    await _inferenceManager.dispose();
  }
}
