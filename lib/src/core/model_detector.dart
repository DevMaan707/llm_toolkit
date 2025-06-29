import 'package:flutter_gemma/core/model.dart';

enum InferenceEngineType { gemma, llama }

class ModelDetector {
  static ModelDetector? _instance;
  static ModelDetector get instance => _instance ??= ModelDetector._();

  ModelDetector._();

  InferenceEngineType detectEngine(String modelPath) {
    final lowerPath = modelPath.toLowerCase();

    // GGUF/GGML files always use Llama engine
    if (lowerPath.endsWith('.gguf') || lowerPath.endsWith('.ggml')) {
      return InferenceEngineType.llama;
    }

    // ALL TFLite files should ALWAYS use Gemma engine
    if (lowerPath.endsWith('.tflite')) {
      return InferenceEngineType.gemma;
    }

    // Default to Llama only for non-TFLite formats
    return InferenceEngineType.llama;
  }

  ModelType? detectGemmaModelType(String modelPath) {
    final lowerPath = modelPath.toLowerCase();

    if (lowerPath.contains('deepseek')) {
      return ModelType.deepSeek;
    }
    return ModelType.gemmaIt;
  }

  bool supportsMultimodal(String modelPath) {
    final lowerPath = modelPath.toLowerCase();

    return lowerPath.contains('gemma') &&
        lowerPath.contains('nano') &&
        lowerPath.endsWith('.tflite');
  }
}
