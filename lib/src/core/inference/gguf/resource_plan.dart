import '../../config.dart';

/// `123MB` style size for logs and reasons.
String formatMegabytes(int bytes) => '${(bytes / (1024 * 1024)).round()}MB';

/// How a model will be loaded on this device, with the memory it is expected
/// to need and why each choice was made.
class ResourcePlan {
  final int contextSize;
  final KvCacheType kvCacheType;
  final bool flashAttention;
  final int batchSize;
  final int ubatchSize;
  final int threads;
  final bool useMmap;
  final bool useMlock;

  /// Estimated bytes for weights (including any projector), the KV cache and
  /// llama.cpp compute buffers.
  final int weightsBytes;
  final int kvCacheBytes;
  final int computeBytes;

  /// Memory reported free when planning, and the share the plan may use.
  final int? availableBytes;
  final int? budgetBytes;

  /// Null when available memory is unknown (iOS, macOS, Windows).
  final bool? fitsInMemory;

  /// Human-readable decisions and risks.
  final List<String> reasons;
  final List<String> warnings;

  const ResourcePlan({
    required this.contextSize,
    required this.kvCacheType,
    required this.flashAttention,
    required this.batchSize,
    required this.ubatchSize,
    required this.threads,
    required this.useMmap,
    required this.useMlock,
    required this.weightsBytes,
    required this.kvCacheBytes,
    required this.computeBytes,
    this.availableBytes,
    this.budgetBytes,
    this.fitsInMemory,
    this.reasons = const [],
    this.warnings = const [],
  });

  int get totalBytes => weightsBytes + kvCacheBytes + computeBytes;

  /// One-line summary of the numbers.
  String get summary =>
      'ctx=$contextSize kv=${kvCacheType.name} flash=$flashAttention '
      'batch=$batchSize/$ubatchSize threads=$threads mmap=$useMmap '
      'mlock=$useMlock; est ${formatMegabytes(totalBytes)} '
      '(weights ${formatMegabytes(weightsBytes)}, kv ${formatMegabytes(kvCacheBytes)}, '
      'compute ${formatMegabytes(computeBytes)})'
      '${availableBytes == null ? '' : ' of ${formatMegabytes(availableBytes!)} free'}';

  @override
  String toString() => [
    summary,
    for (final r in reasons) '- $r',
    for (final w in warnings) '! $w',
  ].join('\n');
}
