import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../config.dart';
import '../../logging/toolkit_logger.dart';
import '../base_inference_engine.dart';
import 'remote_http.dart';
import 'remote_model_presets.dart';

/// Engine for an Ollama server using its native `/api/chat` (NDJSON) API.
///
/// [loadModel] takes the Ollama model tag (for example `llama3.2:3b`).
class OllamaEngine
    implements
        InferenceEngine,
        TextGenerator,
        ChatGenerator,
        VisionGenerator,
        Embedder {
  static const _tag = 'OllamaEngine';

  @override
  String get id => 'ollama';

  /// How long Ollama keeps the model in memory after a request, such as `5m`,
  /// `-1` (forever) or `0` (unload immediately). Null uses the server default.
  final Object? keepAlive;

  /// Context window sent as `num_ctx`. Null uses the model default.
  final int? contextSize;

  /// Model used for embeddings; falls back to the chat model.
  final String? embeddingModel;

  final RemoteHttp _http;
  String? _model;
  int? _embeddingDimensions;

  OllamaEngine({
    String baseUrl = RemoteModelPresets.ollamaNativeUrl,
    String? apiKey,
    String? model,
    Map<String, String> headers = const {},
    http.Client? client,
    this.keepAlive,
    this.contextSize,
    this.embeddingModel,
    Duration requestTimeout = const Duration(seconds: 300),
    Duration streamIdleTimeout = const Duration(seconds: 300),
  }) : _model = model,
       _http = RemoteHttp(
         baseUrl: baseUrl,
         service: 'ollama',
         apiKey: apiKey,
         headers: headers,
         client: client,
         requestTimeout: requestTimeout,
         streamIdleTimeout: streamIdleTimeout,
       );

  @override
  Set<ModelCapability> get capabilities => const {
    ModelCapability.textGeneration,
    ModelCapability.vision,
    ModelCapability.embeddings,
  };

  @override
  bool get isModelLoaded => _model != null;

  @override
  String? get currentModelPath => _model;

  @override
  int? get embeddingDimensions => _embeddingDimensions;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    if (modelPath.trim().isEmpty) {
      throw const InferenceException('An Ollama model name is required.');
    }
    _model = modelPath;
    try {
      final json = await _http.getJson('/api/tags');
      final models = json is Map ? json['models'] : null;
      final known =
          models is List &&
          models.any(
            (m) =>
                m is Map && (m['name'] == modelPath || m['model'] == modelPath),
          );
      if (models is List && !known) {
        ToolkitLog.warning(
          _tag,
          '$modelPath is not pulled on the server yet (run `ollama pull`).',
        );
      }
    } on InferenceException catch (e) {
      ToolkitLog.warning(_tag, 'Could not verify server: ${e.message}');
    }
  }

  @override
  Future<void> unloadModel() async {
    _model = null;
  }

  /// Releases the HTTP client when this engine created it.
  void close() => _http.close();

  /// Tags of the models pulled on the server.
  Future<List<String>> listModels() async {
    final json = await _http.getJson('/api/tags');
    final models = json is Map ? json['models'] : null;
    return [
      if (models is List)
        for (final m in models)
          if (m is Map && m['name'] is String) m['name'] as String,
    ];
  }

  @override
  Stream<String> generateText(String prompt, GenerationParams params) =>
      generateChat([ChatTurn('user', prompt)], params);

  @override
  Stream<String> generateWithImages(
    String prompt,
    List<Uint8List> images,
    GenerationParams params,
  ) => generateChat([ChatTurn('user', prompt, images: images)], params);

  @override
  Stream<String> generateChat(
    List<ChatTurn> messages,
    GenerationParams params,
  ) async* {
    final body = <String, Object?>{
      'model': _requireModel(),
      'stream': true,
      if (keepAlive != null) 'keep_alive': keepAlive,
      'messages': [
        for (final m in messages)
          {
            'role': m.role,
            'content': m.content,
            if (m.images.isNotEmpty)
              'images': [for (final i in m.images) base64Encode(i)],
          },
      ],
      'options': {
        if (contextSize != null) 'num_ctx': contextSize,
        'num_predict': params.maxTokens,
        'temperature': params.temperature,
        'top_k': params.topK,
        'top_p': params.topP,
        'repeat_penalty': params.repeatPenalty,
        if (params.seed != null) 'seed': params.seed,
        if (params.stopSequences.isNotEmpty) 'stop': params.stopSequences,
      },
    };
    await for (final line in _http.postLines('/api/chat', body)) {
      final Object? json;
      try {
        json = jsonDecode(line);
      } on FormatException {
        ToolkitLog.debug(_tag, 'Skipping malformed stream line');
        continue;
      }
      if (json is! Map) continue;
      if (json['error'] case final Object error) {
        throw InferenceException('ollama stream error: $error');
      }
      final message = json['message'];
      final content = message is Map ? message['content'] : null;
      if (content is String && content.isNotEmpty) yield content;
      if (json['done'] == true) return;
    }
  }

  @override
  Future<List<double>> embed(String text) async =>
      (await embedBatch([text])).first;

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final json = await _http.postJson('/api/embed', {
      'model': embeddingModel ?? _requireModel(),
      'input': texts,
      if (keepAlive != null) 'keep_alive': keepAlive,
    });
    final embeddings = (json as Map)['embeddings'];
    if (embeddings is! List || embeddings.length != texts.length) {
      throw InferenceException(
        'ollama returned ${embeddings is List ? embeddings.length : 0} '
        'embeddings for ${texts.length} inputs.',
      );
    }
    final vectors = [
      for (final e in embeddings)
        [for (final v in e as List) (v as num).toDouble()],
    ];
    _embeddingDimensions = vectors.first.length;
    return vectors;
  }

  String _requireModel() =>
      _model ??
      (throw const InferenceException(
        'No Ollama model selected. Call loadModel(modelTag, config) first.',
      ));
}
