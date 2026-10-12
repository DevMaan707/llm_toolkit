import 'dart:math' as math;
import 'dart:typed_data';

/// Root-mean-square level of [samples] in `[from, to)`.
double rms(Float32List samples, [int from = 0, int? to]) {
  final end = to ?? samples.length;
  if (end <= from) return 0;
  var sum = 0.0;
  for (var i = from; i < end; i++) {
    sum += samples[i] * samples[i];
  }
  return math.sqrt(sum / (end - from));
}

/// Energy-based voice activity detection over fixed-size frames.
class VoiceActivityDetector {
  /// RMS (0..1) at or above which a frame counts as speech.
  final double threshold;

  /// Samples per analysis frame (default 100 ms at 16 kHz).
  final int frameSamples;

  const VoiceActivityDetector({this.threshold = 0.01, this.frameSamples = 1600})
    : assert(frameSamples > 0);

  bool isSpeech(Float32List frame) => rms(frame) >= threshold;

  /// Fraction (0..1) of whole frames in [samples] that contain speech.
  double speechRatio(Float32List samples) {
    final frames = samples.length ~/ frameSamples;
    if (frames == 0) return isSpeech(samples) ? 1 : 0;
    var speech = 0;
    for (var f = 0; f < frames; f++) {
      if (rms(samples, f * frameSamples, (f + 1) * frameSamples) >= threshold) {
        speech++;
      }
    }
    return speech / frames;
  }

  /// True when at least [minRatio] of the frames contain speech.
  bool containsSpeech(Float32List samples, {double minRatio = 0.05}) =>
      speechRatio(samples) >= minRatio && samples.isNotEmpty;
}

/// Decides when a live recording should end: after speech has been heard (or
/// not) and silence then lasts [silenceTimeout]. Driven by sample counts, so it
/// is deterministic and independent of wall-clock time.
class EndpointDetector {
  final VoiceActivityDetector vad;
  final int sampleRate;
  final Duration silenceTimeout;

  int _silentSamples = 0;
  bool _heardSpeech = false;

  EndpointDetector({
    required this.vad,
    required this.sampleRate,
    required this.silenceTimeout,
  });

  bool get heardSpeech => _heardSpeech;

  /// Feeds the next block of audio; returns true once the silence timeout has
  /// been reached.
  bool feed(Float32List block) {
    if (block.isEmpty) return shouldStop;
    if (vad.isSpeech(block)) {
      _heardSpeech = true;
      _silentSamples = 0;
    } else {
      _silentSamples += block.length;
    }
    return shouldStop;
  }

  bool get shouldStop =>
      _silentSamples * 1000000 ~/ sampleRate >= silenceTimeout.inMicroseconds;
}
