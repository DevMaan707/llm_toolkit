import 'dart:io';
import 'dart:math' as math;

import '../../config.dart';
import 'gguf_metadata.dart';
import 'kv_cache_estimator.dart';
import 'resource_plan.dart';

/// Chooses context size, KV cache precision, batch sizes and threads that fit
/// the memory available, from GGUF metadata. Explicit [InferenceConfig] fields
/// are never overridden, except that a requested context that cannot fit even
/// with the cheapest KV cache is reduced (loading would be killed otherwise).
abstract final class MemoryPlanner {
  /// Share of free memory the plan may use; the rest is a safety margin for
  /// the app, the OS and estimate error.
  static const budgetFraction = 0.80;

  static const _defaultContext = 4096;
  static const _minContext = 512;
  static const _q8ContextFloor = 2048;
  static const _baseComputeBytes = 64 * 1024 * 1024;
  static const _tightMemoryBytes = 4 * 1024 * 1024 * 1024;
  static const _fallbackKvDivisor = 20000;

  static ResourcePlan plan({
    required GgufMetadata metadata,
    required int fileSizeBytes,
    int projectorBytes = 0,
    int? availableBytes,
    int? cores,
    InferenceConfig config = const InferenceConfig(),
    bool? embedding,
  }) {
    final isEmbedding = embedding ?? metadata.isEmbeddingModel;
    final reasons = <String>[];
    final warnings = <String>[];
    final weights = fileSizeBytes + projectorBytes;
    final budget =
        availableBytes == null
            ? null
            : (availableBytes * budgetFraction).floor();
    final tight = availableBytes != null && availableBytes < _tightMemoryBytes;

    final trained = metadata.contextLength;
    final desired =
        config.contextSize ??
        math.min(trained ?? _defaultContext, _defaultContext);
    if (config.contextSize == null &&
        trained != null &&
        trained < _defaultContext) {
      reasons.add('Context capped at the trained length ($trained tokens).');
    }
    if (config.contextSize != null &&
        trained != null &&
        config.contextSize! > trained) {
      warnings.add(
        'Requested context ${config.contextSize} exceeds the trained length '
        '$trained; quality degrades beyond it.',
      );
    }

    final kvOptions =
        config.kvCacheType == null ? KvCacheType.values : [config.kvCacheType!];
    final flashSetting = config.flashAttention;

    _Candidate evaluate(int ctx, KvCacheType kv) {
      final quantised = kv != KvCacheType.f16;
      final flash = flashSetting ?? quantised;
      final vType = quantised && !flash ? KvCacheType.f16 : kv;
      final batch =
          config.batchSize ?? (isEmbedding ? ctx : math.min(512, ctx));
      final ubatch = math.min(
        config.ubatchSize ??
            (isEmbedding ? batch : math.min(batch, tight ? 256 : 512)),
        batch,
      );
      final exact = metadata.kvCacheBytes(
        ctx,
        k: kv,
        v: vType,
        ubatchSize: ubatch,
      );
      final kvBytes =
          exact ??
          (ctx *
                  fileSizeBytes *
                  (kv.bytesPerElement + vType.bytesPerElement) /
                  4 /
                  _fallbackKvDivisor)
              .ceil();
      final scores = flash ? 0 : ubatch * ctx * (metadata.headCount ?? 32) * 4;
      final compute =
          _baseComputeBytes +
          ubatch * (metadata.embeddingLength ?? 4096) * 24 +
          scores;
      return _Candidate(
        ctx: ctx,
        kv: kv,
        flash: flash,
        vType: vType,
        batch: batch,
        ubatch: ubatch,
        kvBytes: kvBytes,
        computeBytes: compute,
        estimated: exact == null,
      );
    }

    final candidates = <_Candidate>[
      for (final kv in kvOptions)
        for (final ctx in _contextLadder(desired, kv, kvOptions.length == 1))
          evaluate(ctx, kv),
    ];
    final chosen =
        budget == null
            ? candidates.first
            : candidates.firstWhere(
              (c) => weights + c.kvBytes + c.computeBytes <= budget,
              orElse: () => candidates.last,
            );
    final total = weights + chosen.kvBytes + chosen.computeBytes;
    final fits = budget == null ? null : total <= budget;

    if (chosen.estimated) {
      warnings.add(
        'The GGUF lacks attention geometry; KV cache size is a rough estimate.',
      );
    }
    if (!metadata.hasKvCache) {
      reasons.add('${metadata.architecture} keeps no attention KV cache.');
    }
    _explain(
      reasons,
      warnings,
      chosen,
      config,
      desired,
      metadata,
      budget,
      availableBytes,
      fits,
      total,
      tight,
    );

    return ResourcePlan(
      contextSize: chosen.ctx,
      kvCacheType: chosen.kv,
      flashAttention: chosen.flash,
      batchSize: chosen.batch,
      ubatchSize: chosen.ubatch,
      threads:
          config.threads ??
          performanceThreads(cores ?? Platform.numberOfProcessors),
      useMmap: config.useMmap ?? true,
      useMlock: config.useMlock ?? false,
      weightsBytes: weights,
      kvCacheBytes: chosen.kvBytes,
      computeBytes: chosen.computeBytes,
      availableBytes: availableBytes,
      budgetBytes: budget,
      fitsInMemory: fits,
      reasons: reasons,
      warnings: warnings,
    );
  }

  /// Threads for token generation: the performance cores of a big.LITTLE
  /// chip rather than every core, which slows decoding down.
  static int performanceThreads(int cores) =>
      cores <= 4 ? math.max(1, cores) : (cores ~/ 2).clamp(4, 8);

  /// Context sizes to try for [kv], largest first. f16 is only tried at the
  /// full context; q8_0 down to 2048; q4_0 down to 512. A single (explicit) KV
  /// type may shrink all the way.
  static List<int> _contextLadder(int desired, KvCacheType kv, bool only) {
    final floor =
        only || kv == KvCacheType.q4_0
            ? _minContext
            : kv == KvCacheType.q8_0
            ? _q8ContextFloor
            : desired;
    final lowest = math.min(desired, floor);
    final sizes = <int>[desired];
    for (var c = desired ~/ 2; c >= lowest; c ~/= 2) {
      sizes.add(c);
    }
    return sizes;
  }

  static void _explain(
    List<String> reasons,
    List<String> warnings,
    _Candidate chosen,
    InferenceConfig config,
    int desired,
    GgufMetadata metadata,
    int? budget,
    int? available,
    bool? fits,
    int total,
    bool tight,
  ) {
    if (budget == null) {
      warnings.add(
        'Free memory is unknown on this platform; plan not checked.',
      );
    } else {
      reasons.add(
        'Budget ${formatMegabytes(budget)} = '
        '${(budgetFraction * 100).round()}% of '
        '${formatMegabytes(available!)} free.',
      );
    }
    if (chosen.ctx < desired) {
      reasons.add(
        'Context reduced from $desired to ${chosen.ctx} tokens to fit memory.',
      );
    }
    if (config.kvCacheType != null) {
      reasons.add('KV cache type ${chosen.kv.name} set by config.');
    } else if (chosen.kv != KvCacheType.f16) {
      reasons.add(
        'KV cache quantised to ${chosen.kv.name} to save memory'
        '${chosen.kv == KvCacheType.q4_0 ? ' (noticeable quality cost on some tasks)' : ''}.',
      );
    }
    if (chosen.kv != KvCacheType.f16 && chosen.vType == KvCacheType.f16) {
      warnings.add(
        'Flash attention is disabled, so only the K cache is quantised.',
      );
    } else if (chosen.flash && config.flashAttention == null) {
      reasons.add(
        'Flash attention enabled (required for a quantised V cache).',
      );
    }
    if (metadata.slidingLayerCount > 0) {
      reasons.add(
        '${metadata.slidingLayerCount} sliding-window layers cache only '
        '${metadata.slidingWindow} tokens.',
      );
    }
    if (tight && config.ubatchSize == null && !metadata.isEmbeddingModel) {
      reasons.add('Micro-batch 256: little free memory.');
    }
    if (fits == false) {
      warnings.add(
        'Estimated ${formatMegabytes(total)} exceeds the budget even at the '
        'smallest settings; loading may fail or the app may be killed. '
        'Use a smaller quantisation or model.',
      );
    }
    if (config.useMmap == false) {
      warnings.add('mmap disabled: weights are copied into RAM.');
    }
  }
}

class _Candidate {
  final int ctx;
  final KvCacheType kv;
  final KvCacheType vType;
  final bool flash;
  final int batch;
  final int ubatch;
  final int kvBytes;
  final int computeBytes;
  final bool estimated;

  const _Candidate({
    required this.ctx,
    required this.kv,
    required this.vType,
    required this.flash,
    required this.batch,
    required this.ubatch,
    required this.kvBytes,
    required this.computeBytes,
    required this.estimated,
  });
}
