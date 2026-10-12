import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart'
    show
        FlutterEdgeAi,
        InferenceChat,
        InferenceModel,
        Message,
        ModelType,
        TextResponse;
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart'
    show LiteRtLmEngine;

import '../../exceptions/llm_toolkit_exceptions.dart';
import '../config.dart';
import '../logging/toolkit_logger.dart';
import 'base_inference_engine.dart';
import 'litert/litert_mapping.dart';

/// On-device inference through LiteRT-LM / MediaPipe (`.litertlm` and `.task`
/// models such as Gemma, Qwen and DeepSeek exports) via `flutter_edge_ai`.
///
/// `flutter_edge_ai` registers no engine on its own, so this class calls
/// `FlutterEdgeAi.initialize` with `LiteRtLmEngine` once, lazily, on the first
/// [loadModel]. Apps that initialize `flutter_edge_ai` themselves (for example
/// to add embedding backends) pass `autoInitialize: false`.
///
/// One generation runs at a time; concurrent calls queue.
class LiteRtEngine
    implements InferenceEngine, TextGenerator, ChatGenerator, VisionGenerator {
  static const _tag = 'LiteRtEngine';

  /// Initializes `flutter_edge_ai` on first use unless the app already did.
  final bool autoInitialize;

  /// Hugging Face token passed to `FlutterEdgeAi.initialize`.
  final String? huggingFaceToken;

  LiteRtEngine({this.autoInitialize = true, this.huggingFaceToken});

  static Future<void>? _initialization;

  InferenceModel? _model;
  InferenceChat? _activeChat;
  InferenceConfig _config = const InferenceConfig();
  ModelType _modelType = ModelType.general;
  String? _modelPath;
  int _contextWindow = litertDefaultContextTokens;
  Future<void> _queueTail = Future.value();

  @override
  String get id => 'litert';

  @override
  Set<ModelCapability> get capabilities => {
    ModelCapability.textGeneration,
    if (_config.supportImage) ModelCapability.vision,
    if (_config.supportAudio) ModelCapability.audioInput,
  };

  @override
  bool get isModelLoaded => _model != null;

  @override
  String? get currentModelPath => _modelPath;

  Future<void> _ensureInitialized() {
    if (!autoInitialize) return Future.value();
    return _initialization ??= FlutterEdgeAi.initialize(
      huggingFaceToken: huggingFaceToken,
      inferenceEngines: [LiteRtLmEngine()],
    ).catchError((Object e) {
      _initialization = null;
      throw e;
    });
  }

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    if (_model != null) await unloadModel();
    try {
      await _ensureInitialized();

      final fileType = litertFileTypeFor(modelPath);
      final modelType =
          (config.extra['modelType'] as ModelType?) ??
          litertModelTypeFor(config.family, path: modelPath);
      final contextWindow = litertContextWindow(config, fileType);

      await FlutterEdgeAi.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromFile(modelPath).install();

      _model = await FlutterEdgeAi.getActiveModel(
        maxTokens: contextWindow,
        preferredBackend: litertBackendFor(config.backend),
        supportImage: config.supportImage,
        supportAudio: config.supportAudio,
        maxNumImages: config.supportImage ? config.maxNumImages : null,
      );
      _config = config;
      _modelType = modelType;
      _modelPath = modelPath;
      _contextWindow = contextWindow;
      ToolkitLog.info(
        _tag,
        'Loaded $modelPath as ${modelType.name} '
        '(${fileType.name}, context $contextWindow, '
        'backend ${_model!.activeBackend?.name ?? 'default'})',
      );
    } catch (e) {
      throw InferenceException('Failed to load LiteRT model: $e', e);
    }
  }

  @override
  Stream<String> generateText(String prompt, GenerationParams params) =>
      _generate(null, [Message.text(text: prompt, isUser: true)], params);

  @override
  Stream<String> generateChat(
    List<ChatTurn> messages,
    GenerationParams params,
  ) {
    final LitertTranscript transcript;
    try {
      transcript = litertTranscriptFrom(messages);
    } on ArgumentError catch (e) {
      return Stream.error(InferenceException('Invalid chat: ${e.message}'));
    }
    return _generate(transcript.system, transcript.messages, params);
  }

  @override
  Stream<String> generateWithImages(
    String prompt,
    List<Uint8List> images,
    GenerationParams params,
  ) {
    if (!_config.supportImage) {
      return Stream.error(
        const UnsupportedCapabilityException(
          'Model was loaded without image support '
          '(set InferenceConfig.supportImage)',
        ),
      );
    }
    if (images.isEmpty) {
      return Stream.error(const InferenceException('No images provided'));
    }
    return _generate(null, [
      Message.withImages(text: prompt, imageBytes: images, isUser: true),
    ], params);
  }

  Stream<String> _generate(
    String? system,
    List<Message> messages,
    GenerationParams params,
  ) async* {
    final model = _model;
    if (model == null) {
      throw const InferenceException('LiteRT model not loaded');
    }

    final release = await _acquire();
    InferenceChat? chat;
    var finished = false;
    try {
      final sampling = litertSamplingFor(params);
      chat = await model.createChat(
        temperature: sampling.temperature,
        topK: sampling.topK,
        topP: sampling.topP,
        randomSeed: sampling.randomSeed,
        supportImage: _config.supportImage,
        supportAudio: _config.supportAudio,
        modelType: _modelType,
        systemInstruction: system,
        maxOutputTokens: litertMaxOutputTokens(params, _contextWindow),
      );
      _activeChat = chat;
      for (final message in messages) {
        await chat.addQueryChunk(message);
      }
      final tokens = chat.generateChatResponseAsync().expand(
        (r) => r is TextResponse ? [r.token] : const <String>[],
      );
      yield* litertApplyStopSequences(tokens, params.stopSequences);
      finished = true;
    } on InferenceException {
      rethrow;
    } catch (e) {
      throw InferenceException('LiteRT generation failed: $e', e);
    } finally {
      await _closeChat(chat, stopFirst: !finished);
      if (identical(_activeChat, chat)) _activeChat = null;
      release();
    }
  }

  Future<void> _closeChat(
    InferenceChat? chat, {
    required bool stopFirst,
  }) async {
    if (chat == null) return;
    try {
      if (stopFirst) await chat.stopGeneration();
    } catch (e) {
      ToolkitLog.debug(_tag, 'stopGeneration failed: $e');
    }
    try {
      await chat.close();
    } catch (e) {
      ToolkitLog.warning(_tag, 'Closing chat session failed: $e');
    }
  }

  /// Serializes generations; the returned callback frees the next in line.
  Future<void Function()> _acquire() async {
    final previous = _queueTail;
    final done = Completer<void>();
    _queueTail = done.future;
    await previous;
    return done.complete;
  }

  @override
  Future<void> unloadModel() async {
    final model = _model;
    if (model == null) return;
    final chat = _activeChat;
    _model = null;
    _modelPath = null;
    _config = const InferenceConfig();
    await _closeChat(chat, stopFirst: true);
    try {
      await model.close();
    } catch (e) {
      ToolkitLog.warning(_tag, 'Closing model failed: $e');
    }
  }
}
