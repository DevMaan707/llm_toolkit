import 'package:flutter_gemma/core/model.dart';

enum InferenceEngineType { llama, gemma, tflite, tfliteASR, whisper_gguf }

class ModelDetector {
  static final ModelDetector instance = ModelDetector._internal();
  ModelDetector._internal();

  InferenceEngineType detectEngine(String modelPath) {
    final fileName = modelPath.toLowerCase();

    // Check if it's an ASR model first
    if (isASRModel(fileName)) {
      return InferenceEngineType.tfliteASR;
    }

    // For Gemma models - only use Gemma engine for Google/Gemini models
    if (isGemmaModel(fileName) && isGoogleModel(fileName)) {
      return InferenceEngineType.gemma;
    }

    // For all other TFLite models (including non-Google Gemma), use TFLite engine
    if (fileName.endsWith('.tflite')) {
      return InferenceEngineType.tflite;
    }

    // Default to Llama for GGUF files
    if (fileName.endsWith('.gguf')) {
      return InferenceEngineType.llama;
    }

    return InferenceEngineType.llama; // Default fallback
  }

  bool isASRModel(String fileName) {
    final asrKeywords = [
      'whisper',
      'asr',
      'speech',
      'voice',
      'audio',
      'transcribe',
      'stt', // speech-to-text
    ];

    return asrKeywords.any((keyword) => fileName.contains(keyword));
  }

  bool isGemmaModel(String fileName) {
    return fileName.contains('gemma');
  }

  bool isGoogleModel(String fileName) {
    final googleIndicators = ['google', 'gemini', 'bard'];
    return googleIndicators.any((indicator) => fileName.contains(indicator));
  }

  // Keep existing methods for Gemma compatibility
  ModelType? detectGemmaModelType(String modelPath) {
    final fileName = modelPath.toLowerCase();

    if (fileName.contains('deepseek')) {
      return ModelType.deepSeek;
    }

    // Default to gemmaIt for other Gemma models
    return ModelType.gemmaIt;
  }

  bool supportsMultimodal(String modelPath) {
    final fileName = modelPath.toLowerCase();

    // Check for multimodal indicators
    final multimodalKeywords = ['vision', 'multimodal', 'image', 'visual'];

    return multimodalKeywords.any((keyword) => fileName.contains(keyword));
  }
}
