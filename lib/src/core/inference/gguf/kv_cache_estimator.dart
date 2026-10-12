import 'dart:math' as math;

import '../../config.dart';
import 'gguf_metadata.dart';

/// KV cache sizing for a GGUF model, accounting for grouped-query attention
/// (few KV heads) and sliding-window layers (which cache only a window).
///
/// These are estimates from file metadata; llama.cpp pads and aligns buffers,
/// so treat them as within roughly 10% of the real allocation.
extension KvCacheEstimate on GgufMetadata {
  /// Bytes per cached token of one layer, or null when the file lacks the
  /// attention geometry (layers, KV heads, head size).
  double? _bytesPerTokenPerLayer(KvCacheType k, KvCacheType v) {
    final kvHeads = headCountKv ?? headCount;
    final heads = headCount;
    final embd = embeddingLength;
    final keyDim =
        keyLength ??
        (embd != null && heads != null && heads > 0 ? embd ~/ heads : null);
    final valueDim = valueLength ?? keyDim;
    if (kvHeads == null || keyDim == null || valueDim == null) return null;
    return kvHeads *
        (keyDim * k.bytesPerElement + valueDim * v.bytesPerElement);
  }

  /// Number of layers that only attend to a sliding window.
  int get slidingLayerCount {
    final layers = blockCount ?? 0;
    final window = slidingWindow;
    if (layers == 0 || window == null || window <= 0) return 0;
    final flags = slidingLayerFlags;
    if (flags != null) return flags.where((f) => f).length;
    final pattern =
        slidingWindowPattern ??
        switch (architecture) {
          'gemma2' => 2,
          'gemma3' => 6,
          'gemma3n' => 5,
          _ => 0,
        };
    return pattern < 2 ? 0 : layers - layers ~/ pattern;
  }

  /// Estimated KV cache bytes for [contextSize] tokens, or null when the file
  /// does not describe the attention geometry. Recurrent architectures have no
  /// KV cache and return 0. Sliding-window layers are capped at the window plus
  /// [ubatchSize] unless [swaFull] is set.
  int? kvCacheBytes(
    int contextSize, {
    KvCacheType k = KvCacheType.f16,
    KvCacheType v = KvCacheType.f16,
    int ubatchSize = 512,
    bool swaFull = false,
  }) {
    if (!hasKvCache) return 0;
    final layers = blockCount;
    final perToken = _bytesPerTokenPerLayer(k, v);
    if (layers == null || perToken == null) return null;
    final local = slidingLayerCount;
    final window = slidingWindow ?? contextSize;
    final localTokens =
        swaFull ? contextSize : math.min(contextSize, window + ubatchSize);
    final tokens = (layers - local) * contextSize + local * localTokens;
    return (tokens * perToken).ceil();
  }
}
