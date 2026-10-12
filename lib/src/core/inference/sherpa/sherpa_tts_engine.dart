import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../config.dart';
import '../../logging/toolkit_logger.dart';
import '../asr/wav_format.dart';
import '../base_inference_engine.dart';
import 'sherpa_layout.dart';
import 'sherpa_tts_config.dart';
import 'sherpa_worker.dart';

const _tag = 'SherpaTTS';

/// Asks the synthesis worker for speech.
final class TtsSpeak {
  final String text;
  final int speaker;
  final double speed;
  const TtsSpeak(this.text, this.speaker, this.speed);
}

/// Asks the synthesis worker for its sample rate and speaker count.
final class TtsInfo {
  const TtsInfo();
}

SherpaWorkerSetup _ttsWorkerInit(Object? arg) {
  final tts = sherpa.OfflineTts(arg! as sherpa.OfflineTtsConfig);
  Object? handle(Object? request) => switch (request as Object) {
    TtsInfo() => (tts.sampleRate, tts.numSpeakers),
    TtsSpeak(:final text, :final speaker, :final speed) => () {
      final audio = tts.generate(text: text, sid: speaker, speed: speed);
      return (
        TransferableTypedData.fromList([audio.samples]),
        audio.sampleRate,
      );
    }(),
    _ => throw ArgumentError('Unknown request $request'),
  };
  return (handle: handle, dispose: tts.free);
}

/// Text to speech through sherpa-onnx: Kokoro, Kitten, VITS/Piper and Matcha.
///
/// [loadModel] takes the model *folder*. `InferenceConfig.extra` accepts
/// `speed`, `numThreads`, `provider`, `preferInt8`, `lang` (Kokoro),
/// `vocoder` (Matcha, when not in the folder) and `speakerNames`, a list of
/// voice names whose index is the speaker id. Synthesis runs in a dedicated
/// isolate.
class SherpaTtsEngine implements InferenceEngine, SpeechSynthesizer {
  SherpaWorker? _worker;
  SherpaTtsLayout? _layout;
  String? _modelPath;
  double _speed = 1;
  List<String> _speakerNames = const [];
  int _numSpeakers = 1;
  int _sampleRate = 0;

  @override
  String get id => 'sherpa-tts';

  @override
  Set<ModelCapability> get capabilities => const {ModelCapability.textToSpeech};

  @override
  bool get isModelLoaded => _worker != null;

  @override
  String? get currentModelPath => _modelPath;

  /// Layout of the loaded model.
  SherpaTtsLayout? get layout => _layout;

  /// Number of voices of the loaded model.
  int get numSpeakers => _numSpeakers;

  /// Output sample rate of the loaded model.
  int get sampleRate => _sampleRate;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    await unloadModel();
    final type = FileSystemEntity.typeSync(modelPath);
    if (type == FileSystemEntityType.notFound) {
      throw InferenceException('Sherpa model folder not found: $modelPath');
    }
    if (type != FileSystemEntityType.directory) {
      throw InferenceException(
        'Sherpa models are folders, but $modelPath is a file',
      );
    }
    final x = config.extra;
    final layout = SherpaModelLayout.detect(
      Directory(modelPath),
      preferInt8: x['preferInt8'] as bool? ?? true,
    );
    if (layout is! SherpaTtsLayout) {
      throw InferenceException(
        '$modelPath is a speech recognition model; load it with sherpa-asr',
      );
    }
    final ttsConfig = buildTtsConfig(
      layout,
      numThreads:
          config.threads ??
          (x['numThreads'] as num?)?.toInt() ??
          math.min(4, Platform.numberOfProcessors),
      provider: x['provider'] as String? ?? 'cpu',
      vocoder: x['vocoder'] as String?,
      lang: x['lang'] as String? ?? '',
    );
    final worker = await SherpaWorker.spawn(_ttsWorkerInit, ttsConfig);
    try {
      final (rate, speakers) = await worker.request<(int, int)>(
        const TtsInfo(),
      );
      _sampleRate = rate;
      _numSpeakers = speakers;
    } catch (_) {
      worker.close();
      rethrow;
    }
    _worker = worker;
    _layout = layout;
    _modelPath = modelPath;
    _speed = (x['speed'] as num?)?.toDouble() ?? 1;
    _speakerNames = (x['speakerNames'] as List?)?.cast<String>() ?? const [];
    ToolkitLog.info(
      _tag,
      'Loaded ${layout.architecture.name} from $modelPath '
      '($_numSpeakers voices, $_sampleRate Hz)',
    );
  }

  @override
  Future<void> unloadModel() async {
    _worker?.close();
    _worker = null;
    _layout = null;
    _modelPath = null;
    _speakerNames = const [];
  }

  /// Resolves [voice] (a speaker id or a name from `speakerNames`) to an id.
  int speakerId(String? voice) {
    if (voice == null || voice.isEmpty) return 0;
    final id = int.tryParse(voice) ?? _speakerNames.indexOf(voice);
    if (id < 0 || id >= _numSpeakers) {
      throw InferenceException(
        'Unknown voice "$voice" (model has $_numSpeakers voices)',
      );
    }
    return id;
  }

  /// Returns a 16-bit mono WAV file. [voice] is a speaker id such as `"3"`
  /// or a name listed in `speakerNames`.
  @override
  Future<Uint8List> synthesize(String text, {String? voice}) async {
    final worker =
        _worker ??
        (throw const InferenceException('No sherpa TTS model loaded'));
    if (text.trim().isEmpty) {
      throw const InferenceException('Nothing to synthesize: text is empty');
    }
    final (data, rate) = await worker.request<(TransferableTypedData, int)>(
      TtsSpeak(text, speakerId(voice), _speed),
    );
    final samples = data.materialize().asFloat32List();
    if (samples.isEmpty || rate <= 0) {
      throw const InferenceException('The model produced no audio');
    }
    return encodeWav16(samples, rate);
  }
}
