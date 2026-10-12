/// Hardware backend preference. Engines map this to what they support and fall
/// back to CPU when a backend is unavailable.
enum ComputeBackend { cpu, gpu, npu }

/// Model family hints used by engines that need to pick a chat template or
/// runtime preset (e.g. Gemma vs. DeepSeek on LiteRT).
enum ModelFamily {
  generic,
  gemma,
  deepSeek,
  qwen,
  llama,
  phi,
  mistral,
  kimi,
  glm,
  smolLm,
  liquid,
  granite,
  cohere,
  olmo,
  internLm,
  miniCpm,
  yi,
  openAiOss,
}

/// Precision of the llama.cpp attention (KV) cache. Lower precision trades a
/// little quality for memory: `q8_0` roughly halves the cache versus `f16`
/// with negligible loss, `q4_0` quarters it at a task-dependent quality cost.
/// It saves memory, not speed.
enum KvCacheType {
  f16(2.0),
  q8_0(34 / 32),
  q4_0(18 / 32);

  /// Bytes per cached element.
  final double bytesPerElement;

  const KvCacheType(this.bytesPerElement);
}

/// How a model should be loaded. Fields left null fall back to engine defaults.
class InferenceConfig {
  final ModelFamily family;
  final ComputeBackend? backend;

  /// Context window in tokens (prompt + history + reply).
  final int? contextSize;
  final int? maxTokens;
  final int? threads;
  final int? gpuLayers;
  final bool supportImage;
  final int maxNumImages;
  final bool supportAudio;
  final bool verbose;

  /// llama.cpp: KV cache precision. Null lets the planner choose (f16 unless
  /// memory is tight). Quantised V cache needs [flashAttention].
  final KvCacheType? kvCacheType;

  /// llama.cpp: flash attention. Null enables it only when a quantised KV
  /// cache requires it.
  final bool? flashAttention;

  /// llama.cpp: logical batch size (tokens per prompt-processing step).
  final int? batchSize;

  /// llama.cpp: physical micro-batch size; defaults to the planner's choice.
  final int? ubatchSize;

  /// llama.cpp: memory-map the weights (default true; keeps RSS low).
  final bool? useMmap;

  /// llama.cpp: pin the weights in RAM (default false).
  final bool? useMlock;

  /// llama.cpp: size context, KV precision, batches and threads from the
  /// model's GGUF metadata and the memory available. Any field set above or
  /// in this config wins over the plan.
  final bool optimizeForDevice;

  /// Engine-specific options that don't merit a first-class field.
  final Map<String, Object?> extra;

  const InferenceConfig({
    this.family = ModelFamily.generic,
    this.backend,
    this.contextSize,
    this.maxTokens,
    this.threads,
    this.gpuLayers,
    this.supportImage = false,
    this.maxNumImages = 1,
    this.supportAudio = false,
    this.verbose = false,
    this.kvCacheType,
    this.flashAttention,
    this.batchSize,
    this.ubatchSize,
    this.useMmap,
    this.useMlock,
    this.optimizeForDevice = true,
    this.extra = const {},
  });

  const InferenceConfig.defaults() : this();

  const InferenceConfig.mobile()
    : this(
        backend: ComputeBackend.gpu,
        contextSize: 2048,
        maxTokens: 512,
        threads: 4,
      );

  const InferenceConfig.desktop()
    : this(
        backend: ComputeBackend.gpu,
        contextSize: 8192,
        maxTokens: 2048,
        gpuLayers: 99,
      );

  const InferenceConfig.multimodal({int maxNumImages = 1})
    : this(
        backend: ComputeBackend.gpu,
        contextSize: 4096,
        maxTokens: 4096,
        supportImage: true,
        maxNumImages: maxNumImages,
      );

  InferenceConfig copyWith({
    ModelFamily? family,
    ComputeBackend? backend,
    int? contextSize,
    int? maxTokens,
    int? threads,
    int? gpuLayers,
    bool? supportImage,
    int? maxNumImages,
    bool? supportAudio,
    bool? verbose,
    KvCacheType? kvCacheType,
    bool? flashAttention,
    int? batchSize,
    int? ubatchSize,
    bool? useMmap,
    bool? useMlock,
    bool? optimizeForDevice,
    Map<String, Object?>? extra,
  }) => InferenceConfig(
    family: family ?? this.family,
    backend: backend ?? this.backend,
    contextSize: contextSize ?? this.contextSize,
    maxTokens: maxTokens ?? this.maxTokens,
    threads: threads ?? this.threads,
    gpuLayers: gpuLayers ?? this.gpuLayers,
    supportImage: supportImage ?? this.supportImage,
    maxNumImages: maxNumImages ?? this.maxNumImages,
    supportAudio: supportAudio ?? this.supportAudio,
    verbose: verbose ?? this.verbose,
    kvCacheType: kvCacheType ?? this.kvCacheType,
    flashAttention: flashAttention ?? this.flashAttention,
    batchSize: batchSize ?? this.batchSize,
    ubatchSize: ubatchSize ?? this.ubatchSize,
    useMmap: useMmap ?? this.useMmap,
    useMlock: useMlock ?? this.useMlock,
    optimizeForDevice: optimizeForDevice ?? this.optimizeForDevice,
    extra: extra ?? this.extra,
  );
}

/// Sampling and length controls for a single generation call.
class GenerationParams {
  final int maxTokens;
  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;
  final List<String> stopSequences;
  final int? seed;

  const GenerationParams({
    this.maxTokens = 1024,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.repeatPenalty = 1.05,
    this.stopSequences = const [],
    this.seed,
  });

  const GenerationParams.creative()
    : this(maxTokens: 2048, temperature: 0.9, topP: 0.95, repeatPenalty: 1.1);

  const GenerationParams.balanced() : this();

  const GenerationParams.precise()
    : this(
        maxTokens: 512,
        temperature: 0.2,
        topP: 0.7,
        topK: 20,
        repeatPenalty: 1.0,
      );

  const GenerationParams.longForm() : this(maxTokens: 4096);

  GenerationParams copyWith({
    int? maxTokens,
    double? temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    List<String>? stopSequences,
    int? seed,
  }) => GenerationParams(
    maxTokens: maxTokens ?? this.maxTokens,
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
    topK: topK ?? this.topK,
    repeatPenalty: repeatPenalty ?? this.repeatPenalty,
    stopSequences: stopSequences ?? this.stopSequences,
    seed: seed ?? this.seed,
  );
}
