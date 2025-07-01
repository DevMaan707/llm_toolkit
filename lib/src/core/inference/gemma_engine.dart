// lib/src/core/inference/gemma_engine.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import '../../exceptions/llm_toolkit_exceptions.dart';
import '../config.dart';
import '../model_detector.dart';
import 'base_inference_engine.dart';

class GemmaInferenceEngine extends BaseInferenceEngine {
  InferenceModel? _inferenceModel;
  bool _isModelLoaded = false;
  String? _currentModelPath;
  ModelType? _currentModelType;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    if (_inferenceModel != null) {
      await unloadModel();
    }

    try {
      // Use the correct ModelFileManager from flutter_gemma directly
      final modelManager = FlutterGemmaPlugin.instance.modelManager;

      print('Installing model at path: $modelPath');
      await modelManager.setModelPath(modelPath);

      // Verify installation
      final isInstalled = await modelManager.isModelInstalled;
      if (!isInstalled) {
        throw InferenceException(
          'Model not properly installed in ModelFileManager',
        );
      }

      print('Model installed successfully, creating inference model...');

      final modelType =
          config.modelType ??
          ModelDetector.instance.detectGemmaModelType(modelPath) ??
          ModelType.gemmaIt;

      _inferenceModel = await FlutterGemmaPlugin.instance.createModel(
        modelType: modelType,
        preferredBackend: config.preferredBackend ?? PreferredBackend.gpu,
        maxTokens: config.maxTokens ?? 1024,
        supportImage: config.supportImage ?? false,
        maxNumImages: config.maxNumImages ?? 1,
      );

      _isModelLoaded = true;
      _currentModelPath = modelPath;
      _currentModelType = modelType;

      print('✅ Gemma model loaded successfully');
    } catch (e) {
      print('❌ Failed to load Gemma model: $e');
      throw InferenceException('Failed to load Gemma model: $e');
    }
  }

  @override
  Stream<String> generateText(String prompt, GenerationParams params) async* {
    if (!_isModelLoaded || _inferenceModel == null) {
      throw InferenceException('Gemma model not loaded');
    }

    try {
      final session = await _inferenceModel!.createSession(
        temperature: params.temperature ?? 0.8,
        //randomSeed: params.randomSeed ?? 1,
        topK: params.topK ?? 1,
      );

      await session.addQueryChunk(Message.text(text: prompt, isUser: true));

      // Use correct streaming method from docs
      await for (final chunk in session.getResponseAsync()) {
        yield chunk;
      }

      await session.close();
    } catch (e) {
      throw InferenceException('Failed to generate text with Gemma: $e');
    }
  }

  // Fixed multimodal generation with correct API from docs
  Stream<String> generateMultimodalResponse(
    String prompt,
    List<String> imagePaths,
    GenerationParams params,
  ) async* {
    if (!_isModelLoaded || _inferenceModel == null) {
      throw InferenceException('Gemma model not loaded');
    }

    try {
      final session = await _inferenceModel!.createSession(
        temperature: params.temperature ?? 0.8,
        //randomSeed: params.randomSeed ?? 1,
        topK: params.topK ?? 1,
      );

      // Convert image paths to bytes for the correct API
      List<Uint8List> imageBytesList = [];
      for (String imagePath in imagePaths) {
        try {
          final file = File(imagePath);
          final bytes = await file.readAsBytes();
          imageBytesList.add(bytes);
        } catch (e) {
          throw InferenceException('Failed to read image file: $imagePath');
        }
      }

      // Use correct multimodal message creation from docs
      // Based on docs: Message.withImage(text: String, imageBytes: Uint8List, isUser: bool)
      if (imageBytesList.isNotEmpty) {
        await session.addQueryChunk(
          Message.withImage(
            text: prompt,
            imageBytes: imageBytesList.first, // Take first image only
            isUser: true,
          ),
        );
      } else {
        throw InferenceException('No valid images provided');
      }

      await for (final chunk in session.getResponseAsync()) {
        yield chunk;
      }

      await session.close();
    } catch (e) {
      throw InferenceException('Failed to generate multimodal response: $e');
    }
  }

  // Use correct chat creation method from docs
  Future<InferenceModel> createChatInstance({
    double? temperature,
    int? randomSeed,
    int? topK,
  }) async {
    if (!_isModelLoaded || _inferenceModel == null) {
      throw InferenceException('Gemma model not loaded');
    }

    // Return the inference model itself as chat instance
    return _inferenceModel!;
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    throw UnimplementedError('Embeddings not supported in Gemma engine');
  }

  @override
  Future<void> unloadModel() async {
    if (_inferenceModel != null) {
      await _inferenceModel!.close();
      _inferenceModel = null;
      _isModelLoaded = false;
      _currentModelPath = null;
      _currentModelType = null;
    }
  }

  @override
  bool get isModelLoaded => _isModelLoaded;

  String? get currentModelPath => _currentModelPath;
  ModelType? get currentModelType => _currentModelType;
}
