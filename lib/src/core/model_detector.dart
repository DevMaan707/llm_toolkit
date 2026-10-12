import 'dart:io';

import '../exceptions/llm_toolkit_exceptions.dart';
import 'config.dart';
import 'inference/base_inference_engine.dart';
import 'inference/sherpa/sherpa_layout.dart';

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
/// `asr`, `sherpa-asr`, `sherpa-tts`). Folders holding sherpa-onnx speech
/// models are recognised by their contents. Custom engines can be selected explicitly with `engineId`.
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
  static const _sherpaTtsKeywords = [
    'kokoro',
    'piper',
    'vits',
    'matcha',
    'kitten',
  ];
  static const _sherpaAsrKeywords = [
    'whisper',
    'moonshine',
    'parakeet',
    'zipformer',
    'sense-voice',
    'sensevoice',
    'paraformer',
    'sherpa-onnx',
  ];
  static const _otherFormats = [
    '.gguf',
    '.ggml',
    '.litertlm',
    '.task',
    '.tflite',
    '.bin',
    '.safetensors',
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

    final sherpa = _detectSherpa(modelPath, name, family);
    if (sherpa != null) return sherpa;

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

  DetectedModel? _detectSherpa(String path, String name, ModelFamily family) {
    if (Directory(path).existsSync()) {
      try {
        return switch (SherpaModelLayout.detect(Directory(path))) {
          SherpaAsrLayout() => DetectedModel('sherpa-asr', {
            ModelCapability.speechToText,
          }, family),
          SherpaTtsLayout() => DetectedModel('sherpa-tts', {
            ModelCapability.textToSpeech,
          }, family),
        };
      } on InferenceException {
        return _sherpaByName(name, family);
      }
    }
    return _otherFormats.any(name.endsWith)
        ? null
        : _sherpaByName(name, family);
  }

  DetectedModel? _sherpaByName(String name, ModelFamily family) {
    if (_sherpaTtsKeywords.any(name.contains)) {
      return DetectedModel('sherpa-tts', {
        ModelCapability.textToSpeech,
      }, family);
    }
    if (_sherpaAsrKeywords.any(name.contains)) {
      return DetectedModel('sherpa-asr', {
        ModelCapability.speechToText,
      }, family);
    }
    return null;
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
