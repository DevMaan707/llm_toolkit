import '../../exceptions/llm_toolkit_exceptions.dart';
import '../config.dart';
import '../logging/toolkit_logger.dart';
import '../model_detector.dart';
import 'base_inference_engine.dart';

/// Registry of engines plus the "slots" for what is currently loaded.
///
/// Several engines can be loaded at once (for example an LLM, an embedding
/// model and a speech recognizer for a voice-driven RAG app); each capability
/// resolves to the engine that most recently loaded a model providing it.
class InferenceManager {
  static const _tag = 'InferenceManager';

  final Map<String, InferenceEngine> _engines = {};
  final Map<ModelCapability, InferenceEngine> _slots = {};

  void registerEngine(InferenceEngine engine) {
    _engines[engine.id] = engine;
  }

  Iterable<String> get engineIds => _engines.keys;

  InferenceEngine? engineById(String id) => _engines[id];

  /// Loads [modelPath] into the engine named [engineId], or into the engine
  /// chosen by [ModelDetector]. Returns the engine that loaded it.
  Future<InferenceEngine> loadModel(
    String modelPath,
    InferenceConfig config, {
    String? engineId,
    ModelDetector detector = ModelDetector.instance,
  }) async {
    final detected = detector.detect(modelPath);
    final id = engineId ?? detected.engineId;
    final engine = _engines[id];
    if (engine == null) {
      throw UnsupportedCapabilityException(
        'No engine "$id" registered for $modelPath '
        '(registered: ${_engines.keys.join(', ')})',
      );
    }

    final effective =
        config.family == ModelFamily.generic
            ? config.copyWith(family: detected.family)
            : config;

    await engine.loadModel(modelPath, effective);
    ToolkitLog.info(_tag, 'Loaded ${modelPath.split('/').last} on "$id"');

    _slots.removeWhere((_, e) => identical(e, engine));
    for (final c in engine.capabilities) {
      _slots[c] = engine;
    }
    return engine;
  }

  /// The loaded engine for [capability], or null.
  InferenceEngine? engineFor(ModelCapability capability) {
    final e = _slots[capability];
    return (e != null && e.isModelLoaded) ? e : null;
  }

  /// Like [engineFor] but throws and checks the engine implements [T].
  T require<T>(ModelCapability capability) {
    final e = engineFor(capability);
    if (e == null) {
      throw InferenceException(
        'No model loaded that provides ${capability.name}',
      );
    }
    if (e is! T) {
      throw UnsupportedCapabilityException(
        'Engine "${e.id}" does not implement $T',
      );
    }
    return e as T;
  }

  bool get hasLoadedModel => _engines.values.any((e) => e.isModelLoaded);

  Set<ModelCapability> get availableCapabilities => {
    for (final c in _slots.keys)
      if (engineFor(c) != null) c,
  };

  Future<void> unload(ModelCapability capability) async {
    final e = _slots[capability];
    if (e == null) return;
    await e.unloadModel();
    _slots.removeWhere((_, v) => identical(v, e));
  }

  Future<void> dispose() async {
    for (final e in _engines.values) {
      if (e.isModelLoaded) await e.unloadModel();
    }
    _slots.clear();
  }
}
