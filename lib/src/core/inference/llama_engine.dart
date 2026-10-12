import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import '../../exceptions/llm_toolkit_exceptions.dart';
import '../config.dart';
import '../logging/toolkit_logger.dart';
import 'base_inference_engine.dart';
import 'gguf/gguf_metadata.dart';
import 'gguf/memory_planner.dart';
import 'gguf/resource_plan.dart';
import 'llama/async_mutex.dart';
import 'llama/llama_params.dart';
import 'llama/memory_guard.dart';
import 'llama/stop_sequence_filter.dart';

/// llama.cpp engine running GGUF models in a background isolate.
///
/// Config options read from [InferenceConfig.extra]:
/// - `mmprojPath` (String): multimodal projector; enables [VisionGenerator].
/// - `embedding` (bool): force embedding mode (auto-detected from the GGUF
///   architecture otherwise).
/// - `chatFormat` (String): `chatml`, `gemma` or `alpaca`.
/// - `libraryPath` (String): native llama library to open.
///
/// With [InferenceConfig.optimizeForDevice] (the default) the GGUF metadata and
/// free memory are used to choose context size, KV cache precision, batch
/// sizes and threads; see [lastPlan]. Explicit config values always win.
///
/// llama.cpp fixes sampler settings when a model is loaded, so a generation
/// whose temperature, top-p, top-k, repeat penalty or seed differ from the
/// active ones reloads the model first.
class LlamaEngine
    implements
        InferenceEngine,
        TextGenerator,
        ChatGenerator,
        Embedder,
        VisionGenerator {
  static const _tag = 'LlamaEngine';
  static const _minFreeMemoryMb = 512;
  static const _bytesPerMb = 1024 * 1024;
  static const _stopTimeout = Duration(seconds: 5);
  static const _embedTimeout = Duration(seconds: 60);

  final _mutex = AsyncMutex();
  LlamaParent? _parent;
  String? _modelPath;
  InferenceConfig _config = const InferenceConfig();
  bool _embeddingMode = false;
  String? _mmprojPath;
  PromptFormat _format = ChatMLFormat();
  SamplingKey? _activeSampling;
  int? _dimensions;
  ResourcePlan? _plan;
  String? _chatTemplate;

  /// The plan applied by the last [loadModel], or null when the engine is
  /// unloaded or `optimizeForDevice` was off.
  ResourcePlan? get lastPlan => _plan;

  /// Jinja chat template embedded in the loaded GGUF, if it has one. It is
  /// used only to pick a built-in prompt format, never evaluated.
  String? get chatTemplate => _chatTemplate;

  /// Plans how [modelPath] would load without loading it, for UIs that want
  /// to show or warn about memory use. [availableBytes] defaults to the free
  /// memory reported by the OS (unknown on iOS, macOS and Windows).
  static Future<ResourcePlan> planFor(
    String modelPath, {
    int? availableBytes,
    InferenceConfig config = const InferenceConfig(),
  }) async {
    final metadata = await GgufMetadata.read(modelPath);
    final available = availableBytes ?? await _freeBytes();
    return _planFor(metadata, modelPath, config, available);
  }

  static Future<int?> _freeBytes() async {
    final mb = await availableMemoryMb();
    return mb == null ? null : mb * _bytesPerMb;
  }

  static Future<ResourcePlan> _planFor(
    GgufMetadata metadata,
    String modelPath,
    InferenceConfig config,
    int? availableBytes, {
    bool? embedding,
    String? mmprojPath,
  }) async => MemoryPlanner.plan(
    metadata: metadata,
    fileSizeBytes: await File(modelPath).length(),
    projectorBytes: mmprojPath == null ? 0 : await File(mmprojPath).length(),
    availableBytes: availableBytes,
    config: config,
    embedding: embedding,
  );

  @override
  String get id => 'llama';

  @override
  Set<ModelCapability> get capabilities =>
      !isModelLoaded
          ? const {}
          : _embeddingMode
          ? const {ModelCapability.embeddings}
          : {
            ModelCapability.textGeneration,
            if (_mmprojPath != null) ModelCapability.vision,
          };

  @override
  bool get isModelLoaded => _parent != null;

  @override
  String? get currentModelPath => _modelPath;

  @override
  int? get embeddingDimensions => _dimensions;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    await unloadModel();
    final metadata = await GgufMetadata.read(modelPath);

    final freeMb = await availableMemoryMb();
    if (freeMb != null && freeMb < _minFreeMemoryMb) {
      throw InferenceException(
        'Only ${freeMb}MB of memory is free; close other apps and try again.',
      );
    }

    final extra = config.extra;
    final mmproj = extra['mmprojPath'] as String?;
    if (mmproj != null && !await File(mmproj).exists()) {
      throw InferenceException('Multimodal projector not found: $mmproj');
    }
    final libraryPath = extra['libraryPath'] as String?;
    if (libraryPath != null) Llama.libraryPath = libraryPath;

    _config = config;
    _embeddingMode = extra['embedding'] as bool? ?? metadata.isEmbeddingModel;
    _mmprojPath = _embeddingMode ? null : mmproj;
    _chatTemplate = metadata.chatTemplate;
    _format = chatFormatFor(
      config.family,
      extra['chatFormat'] ??
          (config.family == ModelFamily.generic
              ? chatFormatFromTemplate(_chatTemplate)
              : null),
    );
    _modelPath = modelPath;
    _plan =
        config.optimizeForDevice
            ? await _planFor(
              metadata,
              modelPath,
              config,
              freeMb == null ? null : freeMb * _bytesPerMb,
              embedding: _embeddingMode,
              mmprojPath: _mmprojPath,
            )
            : null;
    if (_plan case final plan?) {
      ToolkitLog.info(_tag, 'Resource plan for $modelPath:\n$plan');
    }

    try {
      await _start(modelPath, const GenerationParams(), freeMb);
    } catch (_) {
      await unloadModel();
      rethrow;
    }
    ToolkitLog.info(
      _tag,
      'Loaded $modelPath (${metadata.architecture ?? 'unknown arch'}'
      '${_embeddingMode ? ', embeddings' : ''})',
    );
  }

  Future<void> _start(
    String modelPath,
    GenerationParams sampling,
    int? freeMb,
  ) async {
    final plan = _plan;
    final requested = _config.contextSize ?? defaultContextSize;
    final nCtx = plan?.contextSize ?? clampContextSize(requested, freeMb);
    if (plan == null && nCtx < requested) {
      ToolkitLog.warning(
        _tag,
        'Context reduced from $requested to $nCtx tokens (${freeMb}MB free)',
      );
    }
    final load = LlamaLoad(
      path: modelPath,
      modelParams: buildModelParams(_config, plan: plan),
      contextParams: buildContextParams(
        _config,
        nCtx: nCtx,
        embedding: _embeddingMode,
        plan: plan,
      ),
      samplingParams: buildSamplerParams(sampling),
      verbose: _config.verbose,
      mmprojPath: _mmprojPath,
    );
    final parent = LlamaParent(load);
    try {
      await parent.init();
    } catch (e) {
      await _disposeQuietly(parent);
      throw InferenceException(_loadFailureMessage(e, modelPath, nCtx), e);
    }
    _parent = parent;
    _activeSampling = samplingKey(sampling);
  }

  String _loadFailureMessage(Object error, String path, int nCtx) {
    final text = error.toString().toLowerCase();
    final hint = switch (text) {
      _ when error is TimeoutException =>
        'Loading timed out; the model may be too large for this device.',
      _ when text.contains('memory') || text.contains('alloc') =>
        'Not enough memory; use a smaller quantization or a context below $nCtx.',
      _ when text.contains('library') =>
        'The native llama library could not be opened '
            '(set InferenceConfig.extra[\'libraryPath\']).',
      _ => 'Try a different quantization or re-download the file.',
    };
    return 'Failed to load $path: $error. $hint';
  }

  /// Reloads the model when [params] need different sampler settings.
  Future<void> _applySampling(GenerationParams params) async {
    if (_activeSampling == samplingKey(params)) return;
    ToolkitLog.info(_tag, 'Sampler settings changed; reloading model');
    final old = _parent!;
    _parent = null;
    await _disposeQuietly(old);
    try {
      await _start(_modelPath!, params, await availableMemoryMb());
    } catch (_) {
      await unloadModel();
      rethrow;
    }
  }

  @override
  Stream<String> generateText(String prompt, GenerationParams params) =>
      _generate(prompt, params, const []);

  @override
  Stream<String> generateChat(
    List<ChatTurn> messages,
    GenerationParams params,
  ) {
    final images = <LlamaImage>[];
    final turns = [
      for (final m in messages)
        {
          'role': m.role == 'tool' ? 'user' : m.role,
          'content': _withImageMarkers(m.content, m.images, images),
        },
    ];
    return _generate(_format.formatMessages(turns), params, images);
  }

  @override
  Stream<String> generateWithImages(
    String prompt,
    List<Uint8List> images,
    GenerationParams params,
  ) {
    final collected = <LlamaImage>[];
    final content = _withImageMarkers(prompt, images, collected);
    return _generate(
      _format.formatMessages([
        {'role': 'user', 'content': content},
      ]),
      params,
      collected,
    );
  }

  static String _withImageMarkers(
    String content,
    List<Uint8List> images,
    List<LlamaImage> sink,
  ) {
    if (images.isEmpty) return content;
    sink.addAll(images.map(LlamaImage.fromBytes));
    return '${List.filled(images.length, '<image>').join('\n')}\n$content';
  }

  Stream<String> _generate(
    String prompt,
    GenerationParams params,
    List<LlamaImage> images,
  ) async* {
    _requireLoaded();
    if (_embeddingMode) {
      throw const UnsupportedCapabilityException(
        'This is an embedding model and cannot generate text.',
      );
    }
    if (images.isNotEmpty && _mmprojPath == null) {
      throw const UnsupportedCapabilityException(
        "Images need InferenceConfig.extra['mmprojPath'] at load time.",
      );
    }
    final release = await _mutex.acquire();
    try {
      _requireLoaded();
      await _applySampling(params);
      yield* _run(_parent!, prompt, images, params);
    } finally {
      release();
    }
  }

  Stream<String> _run(
    LlamaParent parent,
    String prompt,
    List<LlamaImage> images,
    GenerationParams params,
  ) async* {
    final filter = StopSequenceFilter(params.stopSequences);
    final limit = effectiveMaxTokens(params, _config);
    final events = StreamController<Object>();
    final subscriptions = [
      parent.stream.listen(events.add),
      parent.completions.listen(events.add),
    ];
    String? promptId;
    var count = 0;
    var finished = false;
    try {
      promptId =
          images.isEmpty
              ? await parent.sendPrompt(prompt)
              : await parent.sendPromptWithImages(prompt, images);
      await for (final event in events.stream) {
        if (event is CompletionEvent) {
          if (!event.success) {
            throw InferenceException(
              'Generation failed: ${event.errorDetails ?? 'unknown error'}',
            );
          }
          finished = true;
          break;
        }
        final text = filter.add(event as String);
        if (text.isNotEmpty) yield text;
        if (filter.matched || ++count >= limit) break;
      }
      final rest = filter.flush();
      if (rest.isNotEmpty) yield rest;
    } finally {
      for (final s in subscriptions) {
        await s.cancel();
      }
      await events.close();
      if (!finished) await _stopGeneration(parent, promptId);
    }
  }

  Future<void> _stopGeneration(LlamaParent parent, String? promptId) async {
    try {
      await parent.stop();
      if (promptId != null) {
        await parent.waitForCompletion(promptId).timeout(_stopTimeout);
      }
    } on Object catch (e) {
      ToolkitLog.warning(_tag, 'Could not stop generation cleanly', e);
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    _requireLoaded();
    if (!_embeddingMode) {
      throw const UnsupportedCapabilityException(
        'Loaded model is not an embedding model. Load an embedding GGUF '
        "(e.g. bge, nomic-embed) or set InferenceConfig.extra['embedding'].",
      );
    }
    final release = await _mutex.acquire();
    try {
      final vector = await _parent!.getEmbeddings(text).timeout(_embedTimeout);
      _dimensions = vector.length;
      return vector;
    } on TimeoutException catch (e) {
      throw InferenceException('Embedding timed out', e);
    } finally {
      release();
    }
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async => [
    for (final t in texts) await embed(t),
  ];

  @override
  Future<void> unloadModel() async {
    final parent = _parent;
    _parent = null;
    _modelPath = null;
    _mmprojPath = null;
    _embeddingMode = false;
    _activeSampling = null;
    _dimensions = null;
    _plan = null;
    _chatTemplate = null;
    if (parent != null) await _disposeQuietly(parent);
  }

  void _requireLoaded() {
    if (_parent == null) {
      throw const InferenceException('No llama model is loaded.');
    }
  }

  Future<void> _disposeQuietly(LlamaParent parent) async {
    try {
      await parent.dispose();
    } on Object catch (e) {
      ToolkitLog.warning(_tag, 'Error disposing llama isolate', e);
    }
  }
}
