import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../config.dart';
import '../../logging/toolkit_logger.dart';
import '../base_inference_engine.dart';
import 'remote_http.dart';
import 'remote_model_presets.dart';

/// Engine for any server speaking the OpenAI REST dialect: OpenAI, OpenRouter,
/// Together, Groq, DeepSeek, Moonshot (Kimi), LM Studio, llama-server, vLLM...
///
/// [loadModel] takes the remote model name instead of a file path. No request
/// is needed to "load" anything; reachability is checked best-effort via
/// `GET /models` and only rejected credentials fail the load.
class OpenAiCompatibleEngine
    implements
        InferenceEngine,
        TextGenerator,
        ChatGenerator,
        VisionGenerator,
        Embedder,
        SpeechRecognizer,
        SpeechSynthesizer,
        ImageGenerator {
  static const _tag = 'OpenAiEngine';

  @override
  final String id;

  /// Model used for embeddings; falls back to the chat model.
  final String? embeddingModel;
  final String speechToTextModel;
  final String textToSpeechModel;
  final String imageModel;

  /// Sent as `response_format` for image generation. Set to null for models
  /// that always return base64 and reject the field (e.g. gpt-image-1).
  final String? imageResponseFormat;

  /// Adds `top_k` and `repeat_penalty` to chat requests. Enable for servers
  /// that accept them (llama-server, vLLM, LM Studio, OpenRouter); strict
  /// OpenAI rejects unknown fields.
  final bool sendExtendedSampling;

  /// Merged into every chat request body (e.g. `{'reasoning_effort': 'low'}`).
  final Map<String, Object?> extraBody;

  /// Receives `delta.reasoning_content` text from reasoning models.
  final void Function(String reasoning)? onReasoning;

  final bool enableSpeech;
  final bool enableImages;

  final RemoteHttp _http;
  String? _model;
  int? _embeddingDimensions;

  OpenAiCompatibleEngine({
    required String baseUrl,
    String? apiKey,
    String? model,
    this.id = 'openai',
    Map<String, String> headers = const {},
    http.Client? client,
    this.embeddingModel,
    this.speechToTextModel = 'whisper-1',
    this.textToSpeechModel = 'tts-1',
    this.imageModel = 'dall-e-3',
    this.imageResponseFormat = 'b64_json',
    this.sendExtendedSampling = false,
    this.extraBody = const {},
    this.onReasoning,
    this.enableSpeech = false,
    this.enableImages = false,
    Duration requestTimeout = const Duration(seconds: 120),
    Duration streamIdleTimeout = const Duration(seconds: 120),
  }) : _model = model,
       _http = RemoteHttp(
         baseUrl: baseUrl,
         service: id,
         apiKey: apiKey,
         headers: headers,
         client: client,
         requestTimeout: requestTimeout,
         streamIdleTimeout: streamIdleTimeout,
       );

  /// Builds an engine for a [RemoteModelPresets] entry.
  factory OpenAiCompatibleEngine.fromPreset(
    RemotePreset preset, {
    String? apiKey,
    String? model,
    String? id,
    Map<String, String> headers = const {},
    http.Client? client,
    void Function(String reasoning)? onReasoning,
  }) => OpenAiCompatibleEngine(
    baseUrl: preset.baseUrl,
    apiKey: apiKey,
    model: model,
    id: id ?? preset.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
    headers: headers,
    client: client,
    sendExtendedSampling: preset.acceptsExtendedSampling,
    onReasoning: onReasoning,
  );

  @override
  Set<ModelCapability> get capabilities => {
    ModelCapability.textGeneration,
    ModelCapability.vision,
    ModelCapability.embeddings,
    if (enableSpeech) ...{
      ModelCapability.speechToText,
      ModelCapability.textToSpeech,
    },
    if (enableImages) ModelCapability.imageGeneration,
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
      throw const InferenceException('A remote model name is required.');
    }
    _model = modelPath;
    try {
      await _http.getJson('/models');
    } on InferenceException catch (e) {
      if (e.message.contains('rejected the credentials')) {
        _model = null;
        rethrow;
      }
      ToolkitLog.warning(_tag, 'Could not verify server: ${e.message}');
    } on FormatException {
      ToolkitLog.warning(_tag, '/models returned an unexpected body');
    }
    ToolkitLog.info(_tag, 'Using remote model $modelPath at ${_http.baseUrl}');
  }

  @override
  Future<void> unloadModel() async {
    _model = null;
  }

  /// Releases the HTTP client when this engine created it.
  void close() => _http.close();

  /// Names reported by `GET /models`.
  Future<List<String>> listModels() async {
    final json = await _http.getJson('/models');
    final data = json is Map ? json['data'] : null;
    return [
      if (data is List)
        for (final m in data)
          if (m is Map && m['id'] is String) m['id'] as String,
    ];
  }

  @override
  Stream<String> generateText(String prompt, GenerationParams params) =>
      generateChat([ChatTurn('user', prompt)], params);

  @override
  Stream<String> generateChat(
    List<ChatTurn> messages,
    GenerationParams params,
  ) => _stream([for (final m in messages) _message(m)], params);

  @override
  Stream<String> generateWithImages(
    String prompt,
    List<Uint8List> images,
    GenerationParams params,
  ) => _stream([_message(ChatTurn('user', prompt, images: images))], params);

  Map<String, Object?> _message(ChatTurn turn) {
    if (turn.images.isEmpty) {
      return {'role': turn.role, 'content': turn.content};
    }
    return {
      'role': turn.role,
      'content': [
        {'type': 'text', 'text': turn.content},
        for (final image in turn.images)
          {
            'type': 'image_url',
            'image_url': {
              'url':
                  'data:${imageMimeType(image)};base64,${base64Encode(image)}',
            },
          },
      ],
    };
  }

  Stream<String> _stream(
    List<Map<String, Object?>> messages,
    GenerationParams params,
  ) async* {
    final body = <String, Object?>{
      'model': _requireModel(),
      'messages': messages,
      'stream': true,
      'max_tokens': params.maxTokens,
      'temperature': params.temperature,
      'top_p': params.topP,
      if (params.stopSequences.isNotEmpty) 'stop': params.stopSequences,
      if (params.seed != null) 'seed': params.seed,
      if (sendExtendedSampling) ...{
        'top_k': params.topK,
        'repeat_penalty': params.repeatPenalty,
      },
      ...extraBody,
    };
    await for (final line in _http.postLines('/chat/completions', body)) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload == '[DONE]') return;
      final Object? json;
      try {
        json = jsonDecode(payload);
      } on FormatException {
        ToolkitLog.debug(_tag, 'Skipping malformed stream event');
        continue;
      }
      if (json is! Map) continue;
      final error = json['error'];
      if (error != null) {
        final text = error is Map ? error['message'] ?? error : error;
        throw InferenceException('$id stream error: $text');
      }
      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'];
      if (delta is! Map) continue;
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        onReasoning?.call(reasoning);
      }
      final content = delta['content'];
      if (content is String && content.isNotEmpty) yield content;
    }
  }

  @override
  Future<List<double>> embed(String text) async =>
      (await embedBatch([text])).first;

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final json = await _http.postJson('/embeddings', {
      'model': embeddingModel ?? _requireModel(),
      'input': texts,
    });
    final data = (json as Map)['data'];
    if (data is! List || data.length != texts.length) {
      throw InferenceException(
        '$id returned ${data is List ? data.length : 0} embeddings for '
        '${texts.length} inputs.',
      );
    }
    final items = [...data.cast<Map>()]..sort(
      (a, b) => ((a['index'] ?? 0) as int).compareTo((b['index'] ?? 0) as int),
    );
    final vectors = [
      for (final item in items)
        [for (final v in item['embedding'] as List) (v as num).toDouble()],
    ];
    _embeddingDimensions = vectors.first.length;
    return vectors;
  }

  @override
  Future<String> transcribe(Uint8List audio) async {
    _requireEnabled(enableSpeech, 'speech');
    final json = await _http.postMultipart(
      '/audio/transcriptions',
      fields: {'model': speechToTextModel, 'response_format': 'json'},
      file: http.MultipartFile.fromBytes(
        'file',
        ensureWav(audio),
        filename: 'audio.wav',
      ),
    );
    return ((json as Map)['text'] as String? ?? '').trim();
  }

  @override
  Future<Uint8List> synthesize(String text, {String? voice}) async {
    _requireEnabled(enableSpeech, 'speech');
    return _http.postForBytes('/audio/speech', {
      'model': textToSpeechModel,
      'input': text,
      'voice': voice ?? 'alloy',
      'response_format': 'wav',
    });
  }

  @override
  Future<Uint8List> generateImage(ImageGenerationRequest request) async {
    _requireEnabled(enableImages, 'image generation');
    final json = await _http.postJson('/images/generations', {
      'model': imageModel,
      'prompt': request.prompt,
      'n': 1,
      'size': '${request.width}x${request.height}',
      if (imageResponseFormat != null) 'response_format': imageResponseFormat,
    });
    final data = (json as Map)['data'];
    final first = data is List && data.isNotEmpty ? data.first as Map : null;
    if (first?['b64_json'] case final String b64) return base64Decode(b64);
    if (first?['url'] case final String url) {
      return _http.getBytes(Uri.parse(url));
    }
    throw InferenceException('$id returned no image data.');
  }

  String _requireModel() =>
      _model ??
      (throw const InferenceException(
        'No remote model selected. Call loadModel(modelName, config) first.',
      ));

  void _requireEnabled(bool enabled, String feature) {
    if (!enabled) {
      throw UnsupportedCapabilityException(
        '$id was created without $feature support.',
      );
    }
  }
}
