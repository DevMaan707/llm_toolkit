/// On-device LLMs, speech, embeddings, RAG and model management for Flutter.
library;

import 'dart:typed_data';

import 'src/chat/chat.dart';
import 'src/core/base_provider.dart';
import 'src/core/config.dart';
import 'src/core/inference/asr/asr_engine.dart';
import 'src/core/inference/base_inference_engine.dart';
import 'src/core/inference/inference_manager.dart';
import 'src/core/inference/litert_engine.dart';
import 'src/core/inference/llama_engine.dart';
import 'src/core/inference/remote/remote.dart';
import 'src/core/inference/sherpa/sherpa.dart';
import 'src/core/model_info.dart';
import 'src/core/providers/huggingface/hf_provider.dart';
import 'src/core/providers/ollama/ollama_provider.dart';
import 'src/core/search_query.dart';
import 'src/exceptions/llm_toolkit_exceptions.dart';
import 'src/rag/rag.dart';

export 'src/chat/chat.dart';
export 'src/core/base_provider.dart';
export 'src/core/config.dart';
export 'src/core/inference/asr/asr.dart';
export 'src/core/inference/base_inference_engine.dart';
export 'src/core/inference/inference_manager.dart';
export 'src/core/inference/gguf/gguf.dart';
export 'src/core/inference/litert_engine.dart';
export 'src/core/inference/llama_engine.dart';
export 'src/core/inference/remote/remote.dart';
export 'src/core/inference/sherpa/sherpa.dart';
export 'src/core/logging/toolkit_logger.dart';
export 'src/core/model_detector.dart';
export 'src/core/model_info.dart';
export 'src/core/providers/huggingface/hf_provider.dart';
export 'src/core/providers/local/local_provider.dart';
export 'src/core/providers/ollama/ollama_provider.dart';
export 'src/core/search_query.dart';
export 'src/core/storage/download_manager.dart';
export 'src/core/storage/model_store.dart';
export 'src/exceptions/llm_toolkit_exceptions.dart';
export 'src/rag/rag.dart';
export 'src/services/asr_service.dart';

/// Entry point tying engines, providers and the chat/RAG layers together.
///
/// Engines are plugins: the built-in ones (`llama`, `litert`, `asr`,
/// `sherpa-asr`, `sherpa-tts`) are registered by [initialize]; image, video, speech-synthesis or any other
/// engine can be added with [registerEngine] by implementing the matching
/// capability interface.
class LLMToolkit {
  LLMToolkit._();

  static final LLMToolkit instance = LLMToolkit._();

  final InferenceManager _manager = InferenceManager();
  final Map<String, BaseModelProvider> _providers = {};
  InferenceConfig _defaultConfig = const InferenceConfig.defaults();
  bool _initialized = false;

  /// Registers the built-in engines and providers. Safe to call once at start.
  void initialize({
    String? huggingFaceApiKey,
    InferenceConfig? defaultConfig,
    bool registerDefaultEngines = true,
    bool enableOllama = false,
    String ollamaBaseUrl = 'http://localhost:11434',
  }) {
    if (_initialized) return;
    _initialized = true;
    if (defaultConfig != null) _defaultConfig = defaultConfig;

    registerProvider(HuggingFaceProvider(apiKey: huggingFaceApiKey));
    if (enableOllama) {
      registerProvider(OllamaProvider(baseUrl: ollamaBaseUrl));
    }
    if (registerDefaultEngines) {
      registerEngine(LlamaEngine());
      registerEngine(LiteRtEngine(huggingFaceToken: huggingFaceApiKey));
      registerEngine(AsrEngine());
      registerEngine(SherpaAsrEngine());
      registerEngine(SherpaTtsEngine());
    }
  }

  void registerEngine(InferenceEngine engine) =>
      _manager.registerEngine(engine);

  void registerProvider(BaseModelProvider provider) =>
      _providers[provider.id] = provider;

  BaseModelProvider? provider(String id) => _providers[id];

  /// Capabilities of models loaded right now.
  Set<ModelCapability> get capabilities => _manager.availableCapabilities;

  bool get hasLoadedModel => _manager.hasLoadedModel;

  /// Searches every provider (or just [provider]) and merges the results.
  Future<List<ModelInfo>> searchModels(
    String query, {
    String? provider,
    Set<ModelFormat> formats = const {},
    ModelTask? task,
    int limit = 20,
    bool onlyRunnable = true,
  }) async {
    final q = SearchQuery(
      text: query,
      formats: formats,
      tasks: {if (task != null) task},
      limit: limit,
      onlyRunnable: onlyRunnable,
    );
    if (provider != null) {
      final p = _providers[provider];
      if (p == null) {
        throw ModelProviderException('Provider "$provider" is not registered');
      }
      return p.searchModels(q);
    }
    final results = await Future.wait(
      _providers.values.map(
        (p) => p.searchModels(q).catchError((Object _) => <ModelInfo>[]),
      ),
    );
    return [for (final r in results) ...r]
      ..sort((a, b) => b.downloads.compareTo(a.downloads));
  }

  Future<String> downloadModel(
    ModelInfo model,
    String filename, {
    ProgressCallback? onProgress,
    DownloadProgressCallback? onDetailedProgress,
  }) {
    final p = _providers[model.provider];
    if (p == null) {
      throw ModelProviderException(
        'Provider "${model.provider}" is not registered',
      );
    }
    return p.downloadModel(
      model.id,
      filename,
      onProgress: onProgress,
      onDetailedProgress: onDetailedProgress,
    );
  }

  /// Loads a model; the engine is chosen from the file unless [engineId] is
  /// given. Several models (LLM + embedder + ASR) can be loaded together.
  Future<InferenceEngine> loadModel(
    String modelPath, {
    InferenceConfig? config,
    String? engineId,
  }) => _manager.loadModel(
    modelPath,
    config ?? _defaultConfig,
    engineId: engineId,
  );

  /// Registers and selects a hosted or LAN model behind an OpenAI-compatible
  /// API (OpenAI, OpenRouter, DeepSeek, Moonshot/Kimi, LM Studio, vLLM, ...).
  Future<OpenAiCompatibleEngine> useRemote(
    RemotePreset preset, {
    required String model,
    String? apiKey,
    String? id,
    Map<String, String> headers = const {},
  }) async {
    final engine = OpenAiCompatibleEngine.fromPreset(
      preset,
      apiKey: apiKey,
      id: id,
      headers: headers,
    );
    registerEngine(engine);
    await loadModel(model, engineId: engine.id);
    return engine;
  }

  /// Registers and selects a model served by an Ollama server.
  Future<OllamaEngine> useOllama({
    required String model,
    String baseUrl = 'http://localhost:11434',
  }) async {
    final engine = OllamaEngine(baseUrl: baseUrl);
    registerEngine(engine);
    await loadModel(model, engineId: engine.id);
    return engine;
  }

  Future<void> unload(ModelCapability capability) =>
      _manager.unload(capability);

  Stream<String> generateText(String prompt, {GenerationParams? params}) =>
      _manager
          .require<TextGenerator>(ModelCapability.textGeneration)
          .generateText(prompt, params ?? const GenerationParams());

  Stream<String> generateWithImages(
    String prompt,
    List<Uint8List> images, {
    GenerationParams? params,
  }) => _manager
      .require<VisionGenerator>(ModelCapability.vision)
      .generateWithImages(prompt, images, params ?? const GenerationParams());

  Future<List<double>> embed(String text) =>
      _manager.require<Embedder>(ModelCapability.embeddings).embed(text);

  Future<String> transcribe(Uint8List audio) => _manager
      .require<SpeechRecognizer>(ModelCapability.speechToText)
      .transcribe(audio);

  Future<Uint8List> synthesizeSpeech(String text, {String? voice}) => _manager
      .require<SpeechSynthesizer>(ModelCapability.textToSpeech)
      .synthesize(text, voice: voice);

  Future<Uint8List> generateImage(ImageGenerationRequest request) => _manager
      .require<ImageGenerator>(ModelCapability.imageGeneration)
      .generateImage(request);

  Stream<Uint8List> generateVideo(VideoGenerationRequest request) => _manager
      .require<VideoGenerator>(ModelCapability.videoGeneration)
      .generateVideo(request);

  /// A chat session on the loaded text model. The prompt template follows
  /// [family] when given.
  ChatSession createChat({
    String? systemPrompt,
    ModelFamily family = ModelFamily.generic,
    GenerationParams params = const GenerationParams(),
    int? contextSize,
  }) {
    final engine = _manager.engineFor(ModelCapability.textGeneration);
    if (engine == null) {
      throw const InferenceException('No text generation model is loaded');
    }
    return ChatSession(
      engine,
      systemPrompt: systemPrompt,
      template: PromptTemplate.forFamily(family),
      params: params,
      contextSize: contextSize,
    );
  }

  /// A RAG pipeline using the loaded embedding model (and, if present, the
  /// loaded text model for answers). Defaults to an in-memory store.
  RagPipeline createRagPipeline({VectorStore? store, RagConfig? config}) {
    final embedder = _manager.require<Embedder>(ModelCapability.embeddings);
    final generator =
        _manager.engineFor(ModelCapability.textGeneration) is TextGenerator
            ? _manager.engineFor(ModelCapability.textGeneration)
                as TextGenerator
            : null;
    return RagPipeline(
      embedder: embedder,
      store: store ?? InMemoryVectorStore(),
      generator: generator,
      config: config ?? const RagConfig(),
    );
  }

  Future<void> dispose() async {
    await _manager.dispose();
    for (final p in _providers.values) {
      p.dispose();
    }
  }
}
