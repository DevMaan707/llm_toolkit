import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import '../../exceptions/llm_toolkit_exceptions.dart';
import '../config.dart';
import '../model_detector.dart';
import 'base_inference_engine.dart';
import 'gemma_engine.dart';
import 'llama_engine.dart';
import 'tflite_engine.dart';
import 'tflite_asr_engine.dart';

class InferenceManager {
  final Map<String, BaseInferenceEngine> _engines = {};
  BaseInferenceEngine? _activeEngine;
  InferenceEngineType? _activeEngineType;

  void registerEngine(String name, BaseInferenceEngine engine) {
    _engines[name] = engine;
  }

  Future<void> loadModel(
    String modelPath,
    InferenceConfig config, {
    String? engineName,
  }) async {
    BaseInferenceEngine? engine;
    InferenceEngineType engineType;

    if (engineName != null) {
      engine = _engines[engineName];
      engineType = _getEngineTypeFromName(engineName);
    } else {
      engineType = ModelDetector.instance.detectEngine(modelPath);
      final engineNameDetected = _getEngineNameFromType(engineType);
      engine = _engines[engineNameDetected];
    }

    // Special check for llama engine - verify native libraries are available
    if (engineType == InferenceEngineType.llama) {
      final libsAvailable =
          await LlamaInferenceEngine.checkNativeLibrariesAvailable();
      if (!libsAvailable) {
        throw InferenceException(
          'Llama native libraries are not available or corrupted. '
          'Please ensure libllama.so is properly installed in your app.',
        );
      }
    }

    if (engine == null) {
      throw InferenceException(
        'No suitable engine found for model: $modelPath (detected: $engineType)',
      );
    }

    // Auto-configure based on detected model type and engine
    InferenceConfig finalConfig = config;
    if (engineType == InferenceEngineType.gemma && config.modelType == null) {
      final detectedModelType = ModelDetector.instance.detectGemmaModelType(
        modelPath,
      );
      final supportsMultimodal = ModelDetector.instance.supportsMultimodal(
        modelPath,
      );

      finalConfig = InferenceConfig(
        promptFormat: config.promptFormat,
        modelType: detectedModelType,
        preferredBackend: config.preferredBackend ?? PreferredBackend.gpu,
        maxTokens: config.maxTokens ?? 1024,
        supportImage: config.supportImage ?? supportsMultimodal,
        maxNumImages: config.maxNumImages ?? 1,
        nCtx: config.nCtx,
        verbose: config.verbose,
      );
    } else if (engineType == InferenceEngineType.tflite) {
      // Configure for TFLite (non-Google models)
      finalConfig = InferenceConfig(
        promptFormat: config.promptFormat,
        modelType: ModelType.gemmaIt, // Default for TFLite
        preferredBackend: config.preferredBackend ?? PreferredBackend.cpu,
        maxTokens: config.maxTokens ?? 1024,
        supportImage: false, // Non-Google models typically don't support images
        maxNumImages: 1,
        nCtx: config.nCtx,
        verbose: config.verbose,
      );
    }

    await engine.loadModel(modelPath, finalConfig);
    _activeEngine = engine;
    _activeEngineType = engineType;

    print(
      '✅ Loaded model with ${engineType.name} engine: ${modelPath.split('/').last}',
    );
  }

  Stream<String> generateText(String prompt, GenerationParams params) {
    if (_activeEngine == null) {
      throw InferenceException('No model loaded');
    }

    return _activeEngine!.generateText(prompt, params);
  }

  // Multimodal generation (only works with Gemma)
  Stream<String> generateMultimodalResponse(
    String prompt,
    List<String> imagePaths,
    GenerationParams params,
  ) {
    if (_activeEngine == null) {
      throw InferenceException('No model loaded');
    }

    if (_activeEngineType != InferenceEngineType.gemma) {
      throw InferenceException('Multimodal generation requires Gemma engine');
    }

    final gemmaEngine = _activeEngine as GemmaInferenceEngine;
    return gemmaEngine.generateMultimodalResponse(prompt, imagePaths, params);
  }

  // Chat instance (only works with Gemma and TFLite)
  Future<InferenceModel> createChatInstance({
    double? temperature,
    int? randomSeed,
    int? topK,
  }) async {
    if (_activeEngine == null) {
      throw InferenceException('No model loaded');
    }

    if (_activeEngineType == InferenceEngineType.gemma) {
      final gemmaEngine = _activeEngine as GemmaInferenceEngine;
      return await gemmaEngine.createChatInstance(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
      );
    } else if (_activeEngineType == InferenceEngineType.tflite) {
      final tfliteEngine = _activeEngine as TFLiteInferenceEngine;
      // Return the inference model directly for TFLite
      if (tfliteEngine.isModelLoaded) {
        // For TFLite, we need to access the internal inference model
        // This is a simplified approach - you might need to adjust based on your needs
        throw InferenceException(
          'Chat instances for TFLite engine not yet implemented',
        );
      } else {
        throw InferenceException('TFLite model not loaded');
      }
    } else {
      throw InferenceException('Chat instances require Gemma or TFLite engine');
    }
  }

  // Embedding generation (only works with Llama)
  Future<List<double>> generateEmbedding(String text) async {
    if (_activeEngine == null) {
      throw InferenceException('No model loaded');
    }

    return await _activeEngine!.generateEmbedding(text);
  }

  // ASR-specific methods
  Future<String> transcribeAudio(List<int> audioBytes) async {
    if (_activeEngine == null) {
      throw InferenceException('No model loaded');
    }

    if (_activeEngineType != InferenceEngineType.tfliteASR) {
      throw InferenceException('Audio transcription requires ASR engine');
    }

    final asrEngine = _activeEngine as TFLiteASREngine;
    return await asrEngine.transcribeAudio(audioBytes as dynamic);
  }

  InferenceEngineType? get activeEngineType => _activeEngineType;
  bool get hasActiveModel => _activeEngine?.isModelLoaded ?? false;

  // Helper methods
  InferenceEngineType _getEngineTypeFromName(String engineName) {
    switch (engineName) {
      case 'gemma':
        return InferenceEngineType.gemma;
      case 'llama':
        return InferenceEngineType.llama;
      case 'tflite':
        return InferenceEngineType.tflite;
      case 'tfliteASR':
        return InferenceEngineType.tfliteASR;
      default:
        return InferenceEngineType.llama;
    }
  }

  String _getEngineNameFromType(InferenceEngineType engineType) {
    switch (engineType) {
      case InferenceEngineType.gemma:
        return 'gemma';
      case InferenceEngineType.llama:
        return 'llama';
      case InferenceEngineType.tflite:
        return 'tflite';
      case InferenceEngineType.tfliteASR:
        return 'tfliteASR';
      default:
        return 'llama';
    }
  }

  Future<void> dispose() async {
    for (final engine in _engines.values) {
      if (engine.isModelLoaded) {
        await engine.unloadModel();
      }
    }
    _activeEngine = null;
    _activeEngineType = null;
  }
}
