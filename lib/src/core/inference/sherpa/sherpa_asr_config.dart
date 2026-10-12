import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../config.dart';
import 'sherpa_layout.dart';

/// Tuning for [SherpaAsrLayout] models, read from `InferenceConfig.extra`.
///
/// Recognised keys: `language`, `task` (`transcribe`/`translate`, Whisper),
/// `numThreads`, `provider` (`cpu`, `xnnpack`, `nnapi`, `coreml`),
/// `decodingMethod` (`greedy_search`, `modified_beam_search`), `preferInt8`,
/// `streaming`, `inverseTextNormalization` (SenseVoice), `modelType`,
/// `vadModel` (path to `silero_vad.onnx`), `vadThreshold`,
/// `vadMinSilence` and `vadMaxSpeech` (seconds).
class SherpaAsrOptions {
  final String language;
  final String task;
  final int numThreads;
  final String provider;
  final String decodingMethod;
  final bool preferInt8;
  final bool? streaming;
  final bool inverseTextNormalization;
  final String? modelType;
  final String? vadModel;
  final double vadThreshold;
  final double vadMinSilence;
  final double vadMaxSpeech;

  const SherpaAsrOptions({
    this.language = '',
    this.task = 'transcribe',
    this.numThreads = 2,
    this.provider = 'cpu',
    this.decodingMethod = 'greedy_search',
    this.preferInt8 = true,
    this.streaming,
    this.inverseTextNormalization = true,
    this.modelType,
    this.vadModel,
    this.vadThreshold = 0.5,
    this.vadMinSilence = 0.5,
    this.vadMaxSpeech = 20,
  });

  factory SherpaAsrOptions.fromConfig(InferenceConfig config) {
    final x = config.extra;
    return SherpaAsrOptions(
      language: x['language'] as String? ?? '',
      task: x['task'] as String? ?? 'transcribe',
      numThreads:
          config.threads ??
          (x['numThreads'] as num?)?.toInt() ??
          math.min(4, Platform.numberOfProcessors),
      provider: x['provider'] as String? ?? 'cpu',
      decodingMethod: x['decodingMethod'] as String? ?? 'greedy_search',
      preferInt8: x['preferInt8'] as bool? ?? true,
      streaming: x['streaming'] as bool?,
      inverseTextNormalization: x['inverseTextNormalization'] as bool? ?? true,
      modelType: x['modelType'] as String?,
      vadModel: x['vadModel'] as String?,
      vadThreshold: (x['vadThreshold'] as num?)?.toDouble() ?? 0.5,
      vadMinSilence: (x['vadMinSilence'] as num?)?.toDouble() ?? 0.5,
      vadMaxSpeech: (x['vadMaxSpeech'] as num?)?.toDouble() ?? 20,
    );
  }
}

String _nemoModelType(SherpaAsrLayout l, SherpaAsrOptions o) {
  if (o.modelType != null) return o.modelType!;
  final name = p.basename(l.directory).toLowerCase();
  return name.contains('nemo') || name.contains('parakeet')
      ? 'nemo_transducer'
      : '';
}

/// Offline recognizer configuration for a non-streaming [layout].
sherpa.OfflineRecognizerConfig buildOfflineConfig(
  SherpaAsrLayout layout,
  SherpaAsrOptions o,
) {
  String f(SherpaFileRole r) => layout.path(r);
  final tokens = layout.tokens;
  final model = switch (layout.architecture) {
    SherpaAsrArchitecture.whisper => sherpa.OfflineModelConfig(
      whisper: sherpa.OfflineWhisperModelConfig(
        encoder: f(SherpaFileRole.encoder),
        decoder: f(SherpaFileRole.decoder),
        language: o.language,
        task: o.task,
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    SherpaAsrArchitecture.moonshine => sherpa.OfflineModelConfig(
      moonshine: sherpa.OfflineMoonshineModelConfig(
        preprocessor: f(SherpaFileRole.preprocessor),
        encoder: f(SherpaFileRole.encoder),
        uncachedDecoder: f(SherpaFileRole.uncachedDecoder),
        cachedDecoder: f(SherpaFileRole.cachedDecoder),
        mergedDecoder:
            f(SherpaFileRole.mergedDecoder).isNotEmpty
                ? f(SherpaFileRole.mergedDecoder)
                : f(SherpaFileRole.decoder),
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    SherpaAsrArchitecture.transducer => sherpa.OfflineModelConfig(
      transducer: sherpa.OfflineTransducerModelConfig(
        encoder: f(SherpaFileRole.encoder),
        decoder: f(SherpaFileRole.decoder),
        joiner: f(SherpaFileRole.joiner),
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      modelType: _nemoModelType(layout, o),
      debug: false,
    ),
    SherpaAsrArchitecture.nemoCtc => sherpa.OfflineModelConfig(
      nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(
        model: f(SherpaFileRole.model),
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    SherpaAsrArchitecture.zipformerCtc => sherpa.OfflineModelConfig(
      zipformerCtc: sherpa.OfflineZipformerCtcModelConfig(
        model: f(SherpaFileRole.model),
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    SherpaAsrArchitecture.senseVoice => sherpa.OfflineModelConfig(
      senseVoice: sherpa.OfflineSenseVoiceModelConfig(
        model: f(SherpaFileRole.model),
        language: o.language,
        useInverseTextNormalization: o.inverseTextNormalization,
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    SherpaAsrArchitecture.paraformer => sherpa.OfflineModelConfig(
      paraformer: sherpa.OfflineParaformerModelConfig(
        model: f(SherpaFileRole.model),
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    _ => throw ArgumentError('${layout.architecture} is a streaming model'),
  };
  return sherpa.OfflineRecognizerConfig(
    model: model,
    decodingMethod: o.decodingMethod,
  );
}

/// Online recognizer configuration for a streaming [layout].
sherpa.OnlineRecognizerConfig buildOnlineConfig(
  SherpaAsrLayout layout,
  SherpaAsrOptions o,
) {
  String f(SherpaFileRole r) => layout.path(r);
  final tokens = layout.tokens;
  final model = switch (layout.architecture) {
    SherpaAsrArchitecture.streamingTransducer => sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: f(SherpaFileRole.encoder),
        decoder: f(SherpaFileRole.decoder),
        joiner: f(SherpaFileRole.joiner),
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    SherpaAsrArchitecture.streamingParaformer => sherpa.OnlineModelConfig(
      paraformer: sherpa.OnlineParaformerModelConfig(
        encoder: f(SherpaFileRole.encoder),
        decoder: f(SherpaFileRole.decoder),
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    SherpaAsrArchitecture.streamingZipformerCtc => sherpa.OnlineModelConfig(
      zipformer2Ctc: sherpa.OnlineZipformer2CtcModelConfig(
        model: f(SherpaFileRole.model),
      ),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    SherpaAsrArchitecture.streamingNemoCtc => sherpa.OnlineModelConfig(
      nemoCtc: sherpa.OnlineNemoCtcModelConfig(model: f(SherpaFileRole.model)),
      tokens: tokens,
      numThreads: o.numThreads,
      provider: o.provider,
      debug: false,
    ),
    _ => throw ArgumentError('${layout.architecture} is not a streaming model'),
  };
  return sherpa.OnlineRecognizerConfig(
    model: model,
    decodingMethod: o.decodingMethod,
  );
}
