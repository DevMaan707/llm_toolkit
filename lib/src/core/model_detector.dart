import 'config.dart';
import 'inference/base_inference_engine.dart';

/// Result of inspecting a model file name.
class DetectedModel {
  final String engineId;
  final Set<ModelCapability> capabilities;
  final ModelFamily family;

  const DetectedModel(this.engineId, this.capabilities, this.family);
}

/// Picks an engine id for a model file based on its extension and name.
///
/// Engine ids are the ones used by the built-in engines (`llama`, `litert`,
/// `asr`). Custom engines can be selected explicitly with `engineId`.
class ModelDetector {
  const ModelDetector();

  static const instance = ModelDetector();

  static const _asrKeywords = [
    'whisper',
    'wav2vec',
    'deepspeech',
    'moonshine',
    'parakeet',
  ];
  static const _embeddingKeywords = [
    'embed',
    'bge-',
    'e5-',
    'minilm',
    'nomic-embed',
    'gte-',
  ];
  static const _visionKeywords = ['vision', 'vl-', '-vl', 'llava', 'mmproj'];

  DetectedModel detect(String modelPath) {
    final name = modelPath.split(RegExp(r'[\\/]')).last.toLowerCase();
    final family = detectFamily(name);

    if (name.endsWith('.tflite') && isASR(name)) {
      return DetectedModel('asr', {ModelCapability.speechToText}, family);
    }
    if (name.endsWith('.litertlm') || name.endsWith('.task')) {
      return DetectedModel('litert', {
        ModelCapability.textGeneration,
        if (supportsVision(name)) ModelCapability.vision,
      }, family);
    }
    if (name.endsWith('.gguf') || name.endsWith('.ggml')) {
      if (isEmbedding(name)) {
        return DetectedModel('llama', {ModelCapability.embeddings}, family);
      }
      return DetectedModel('llama', {
        ModelCapability.textGeneration,
        ModelCapability.embeddings,
        if (supportsVision(name)) ModelCapability.vision,
      }, family);
    }
    if (name.endsWith('.tflite')) {
      return DetectedModel('litert', {ModelCapability.textGeneration}, family);
    }
    return DetectedModel('llama', {ModelCapability.textGeneration}, family);
  }

  bool isASR(String fileName) =>
      _asrKeywords.any(fileName.toLowerCase().contains);

  bool isEmbedding(String fileName) =>
      _embeddingKeywords.any(fileName.toLowerCase().contains);

  bool supportsVision(String fileName) =>
      _visionKeywords.any(fileName.toLowerCase().contains);

  static const _familyKeywords = <ModelFamily, List<String>>{
    ModelFamily.gemma: ['gemma'],
    ModelFamily.deepSeek: ['deepseek'],
    ModelFamily.qwen: ['qwen', 'qwq'],
    ModelFamily.kimi: ['kimi', 'moonlight'],
    ModelFamily.glm: ['glm', 'chatglm'],
    ModelFamily.smolLm: ['smollm'],
    ModelFamily.liquid: ['lfm'],
    ModelFamily.granite: ['granite'],
    ModelFamily.cohere: ['command-r', 'aya'],
    ModelFamily.olmo: ['olmo'],
    ModelFamily.internLm: ['internlm'],
    ModelFamily.miniCpm: ['minicpm'],
    ModelFamily.yi: ['yi-'],
    ModelFamily.openAiOss: ['gpt-oss'],
    ModelFamily.phi: ['phi-', 'phi3', 'phi4', 'phi_'],
    ModelFamily.mistral: ['mistral', 'mixtral', 'ministral', 'devstral'],
    ModelFamily.llama: ['llama'],
  };

  /// Best-effort family from a model file or repo name.
  ModelFamily detectFamily(String fileName) {
    final n = fileName.toLowerCase();
    for (final MapEntry(key: family, value: keywords)
        in _familyKeywords.entries) {
      if (keywords.any(n.contains)) return family;
    }
    return ModelFamily.generic;
  }
}
