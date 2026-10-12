import 'dart:io';
import 'dart:math' as math;

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import '../../config.dart';
import '../gguf/memory_planner.dart';
import '../gguf/resource_plan.dart';

/// Context window used when the config does not specify one.
const defaultContextSize = 2048;

/// Layers offloaded when a GPU/NPU backend is requested without an explicit
/// layer count (llama.cpp clamps this to the model's real layer count).
const _allGpuLayers = 99;

/// Sampling settings that are fixed once a model is loaded. Two generations
/// with an equal key can share a loaded model.
typedef SamplingKey =
    (double temp, double topP, int topK, double repeat, int? seed);

SamplingKey samplingKey(GenerationParams p) => (
  p.temperature,
  p.topP,
  p.topK,
  p.repeatPenalty,
  p.seed,
);

ModelParams buildModelParams(InferenceConfig config, {ResourcePlan? plan}) {
  final layers = switch (config.backend) {
    ComputeBackend.cpu => 0,
    null => config.gpuLayers ?? 0,
    _ => config.gpuLayers ?? _allGpuLayers,
  };
  return ModelParams()
    ..nGpuLayers = layers
    ..useMemorymap = config.useMmap ?? plan?.useMmap ?? true
    ..useMemoryLock = config.useMlock ?? plan?.useMlock ?? false;
}

LlamaKvCacheType _cacheType(KvCacheType t) => switch (t) {
  KvCacheType.f16 => LlamaKvCacheType.f16,
  KvCacheType.q8_0 => LlamaKvCacheType.q8_0,
  KvCacheType.q4_0 => LlamaKvCacheType.q4_0,
};

/// Context parameters for [config]. [nCtx] is the already memory-clamped
/// window. A [plan] supplies KV precision, flash attention, batches and
/// threads (it already honours explicit config values); without one, config
/// values and conservative defaults are used. Embedding contexts batch the
/// whole window because embedding models must process the full input at once.
ContextParams buildContextParams(
  InferenceConfig config, {
  required int nCtx,
  bool embedding = false,
  int? processors,
  ResourcePlan? plan,
}) {
  final threads =
      plan?.threads ??
      config.threads ??
      MemoryPlanner.performanceThreads(
        processors ?? Platform.numberOfProcessors,
      );
  final batch =
      plan?.batchSize ??
      config.batchSize ??
      (embedding ? nCtx : math.min(512, nCtx));
  final ubatch = math.min(
    plan?.ubatchSize ?? config.ubatchSize ?? batch,
    batch,
  );
  final kv = plan?.kvCacheType ?? config.kvCacheType ?? KvCacheType.f16;
  final flash =
      plan?.flashAttention ?? config.flashAttention ?? kv != KvCacheType.f16;
  return ContextParams()
    ..nCtx = nCtx
    ..nBatch = batch
    ..nUbatch = ubatch
    ..nThreads = threads
    ..nThreadsBatch = threads
    ..typeK = _cacheType(kv)
    ..typeV = flash ? _cacheType(kv) : LlamaKvCacheType.f16
    ..flashAttention =
        flash ? LlamaFlashAttnType.enabled : LlamaFlashAttnType.disabled
    ..embeddings = embedding;
}

SamplerParams buildSamplerParams(GenerationParams p) =>
    SamplerParams()
      ..temp = p.temperature
      ..greedy = p.temperature <= 0
      ..topP = p.topP
      ..topK = p.topK
      ..penaltyRepeat = p.repeatPenalty
      ..seed = p.seed ?? 0xFFFFFFFF;

/// Maximum tokens to emit: the request limit, capped by the config limit.
int effectiveMaxTokens(GenerationParams p, InferenceConfig? config) {
  final cap = config?.maxTokens;
  return cap == null ? p.maxTokens : math.min(p.maxTokens, cap);
}

/// Chat template for [family], or the one named by `extra['chatFormat']`
/// (`chatml`, `gemma`, `alpaca`).
PromptFormat chatFormatFor(ModelFamily family, [Object? override]) =>
    switch (override ?? family) {
      'gemma' || ModelFamily.gemma => GemmaFormat(),
      'alpaca' => AlpacaFormat(),
      _ => ChatMLFormat(),
    };

/// Chat format name (`gemma`, `chatml`, `alpaca`) matching an embedded Jinja
/// [template], or null when the template is absent or not recognised. This is
/// marker matching, not Jinja evaluation.
String? chatFormatFromTemplate(String? template) => switch (template) {
  null => null,
  _ when template.contains('<start_of_turn>') => 'gemma',
  _ when template.contains('<|im_start|>') => 'chatml',
  _ when template.contains('### Instruction') => 'alpaca',
  _ => null,
};
