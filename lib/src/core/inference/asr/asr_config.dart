/// Tuning knobs for speech recognition and the recording/streaming service.
class ASRConfig {
  /// Sample rate used for recording and fed to the model.
  final int sampleRate;

  /// Upper bound on decoded tokens per window.
  final int maxTokens;

  /// Length of one transcription window (long audio and live streaming).
  final Duration chunkDuration;

  /// Audio shared between consecutive windows so words cut at a boundary are
  /// heard whole in at least one of them.
  final Duration overlapDuration;

  /// Skip windows that contain no speech while streaming.
  final bool enableVAD;

  /// Continuous silence after which VAD recording stops.
  final Duration vadSilenceTimeout;

  /// RMS level (0..1) below which a frame counts as silence.
  final double vadSilenceThreshold;

  const ASRConfig({
    this.sampleRate = 16000,
    this.maxTokens = 448,
    this.chunkDuration = const Duration(seconds: 10),
    this.overlapDuration = const Duration(seconds: 2),
    this.enableVAD = false,
    this.vadSilenceTimeout = const Duration(seconds: 3),
    this.vadSilenceThreshold = 0.01,
  }) : assert(sampleRate > 0),
       assert(maxTokens > 0);

  const ASRConfig.defaults() : this();

  /// Longer windows with more context, at the cost of latency.
  const ASRConfig.highQuality()
    : this(
        maxTokens: 448,
        chunkDuration: const Duration(seconds: 15),
        overlapDuration: const Duration(seconds: 3),
      );

  /// Short windows for quick feedback.
  const ASRConfig.lowLatency()
    : this(
        maxTokens: 224,
        chunkDuration: const Duration(seconds: 4),
        overlapDuration: const Duration(milliseconds: 1000),
        enableVAD: true,
      );

  /// Balanced for phones: VAD on and a shorter silence timeout.
  const ASRConfig.mobile()
    : this(
        maxTokens: 224,
        chunkDuration: const Duration(seconds: 6),
        overlapDuration: const Duration(milliseconds: 1500),
        enableVAD: true,
        vadSilenceTimeout: const Duration(seconds: 2),
      );

  /// Live transcription: moderate windows, VAD on.
  const ASRConfig.streaming()
    : this(
        chunkDuration: const Duration(seconds: 6),
        overlapDuration: const Duration(milliseconds: 1500),
        enableVAD: true,
      );

  /// Samples per transcription window.
  int get chunkSamples =>
      (chunkDuration.inMicroseconds * sampleRate) ~/ 1000000;

  /// Samples shared between consecutive windows.
  int get overlapSamples =>
      (overlapDuration.inMicroseconds * sampleRate) ~/ 1000000;

  ASRConfig copyWith({
    int? sampleRate,
    int? maxTokens,
    Duration? chunkDuration,
    Duration? overlapDuration,
    bool? enableVAD,
    Duration? vadSilenceTimeout,
    double? vadSilenceThreshold,
  }) => ASRConfig(
    sampleRate: sampleRate ?? this.sampleRate,
    maxTokens: maxTokens ?? this.maxTokens,
    chunkDuration: chunkDuration ?? this.chunkDuration,
    overlapDuration: overlapDuration ?? this.overlapDuration,
    enableVAD: enableVAD ?? this.enableVAD,
    vadSilenceTimeout: vadSilenceTimeout ?? this.vadSilenceTimeout,
    vadSilenceThreshold: vadSilenceThreshold ?? this.vadSilenceThreshold,
  );
}
