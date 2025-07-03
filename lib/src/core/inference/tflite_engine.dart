import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import '../../exceptions/llm_toolkit_exceptions.dart';
import '../config.dart';
import 'base_inference_engine.dart';

class TFLiteInferenceEngine extends BaseInferenceEngine {
  // Use flutter_gemma's TFLite backend for non-Google models
  InferenceModel? _inferenceModel;
  bool _isModelLoaded = false;
  String? _currentModelPath;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    if (_inferenceModel != null) {
      await unloadModel();
    }

    try {
      // Use flutter_gemma's ModelFileManager for TFLite models
      final modelManager = FlutterGemmaPlugin.instance.modelManager;

      print('Installing TFLite model at path: $modelPath');
      await modelManager.setModelPath(modelPath);

      // Verify installation
      final isInstalled = await modelManager.isModelInstalled;
      if (!isInstalled) {
        throw InferenceException('TFLite model not properly installed');
      }

      // Create inference model with CPU backend for non-Google models
      _inferenceModel = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt, // Default type for TFLite models
        preferredBackend: PreferredBackend.cpu, // Use CPU for non-Google models
        maxTokens: config.maxTokens ?? 1024,
        supportImage: false, // Non-Google models typically don't support images
        maxNumImages: 1,
      );

      _isModelLoaded = true;
      _currentModelPath = modelPath;

      print('✅ TFLite model loaded successfully');
    } catch (e) {
      print('❌ Failed to load TFLite model: $e');
      throw InferenceException('Failed to load TFLite model: $e');
    }
  }

  @override
  Stream<String> generateText(String prompt, GenerationParams params) async* {
    if (!_isModelLoaded || _inferenceModel == null) {
      throw InferenceException('TFLite model not loaded');
    }

    try {
      final session = await _inferenceModel!.createSession(
        temperature: params.temperature ?? 0.8,
        topK: params.topK ?? 1,
      );

      await session.addQueryChunk(Message.text(text: prompt, isUser: true));

      await for (final chunk in session.getResponseAsync()) {
        yield chunk;
      }

      await session.close();
    } catch (e) {
      throw InferenceException('Failed to generate text with TFLite: $e');
    }
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    throw UnimplementedError('Embeddings not supported in TFLite engine');
  }

  @override
  Future<void> unloadModel() async {
    if (_inferenceModel != null) {
      await _inferenceModel!.close();
      _inferenceModel = null;
      _isModelLoaded = false;
      _currentModelPath = null;
    }
  }

  @override
  bool get isModelLoaded => _isModelLoaded;

  String? get currentModelPath => _currentModelPath;
}
