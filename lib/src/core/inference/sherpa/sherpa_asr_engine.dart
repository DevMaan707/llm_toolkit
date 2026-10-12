import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../config.dart';
import '../../logging/toolkit_logger.dart';
import '../asr/audio_decoder.dart';
import '../base_inference_engine.dart';
import 'sherpa_asr_config.dart';
import 'sherpa_asr_worker.dart';
import 'sherpa_layout.dart';
import 'sherpa_worker.dart';

const _tag = 'SherpaASR';
const _rate = 16000;

/// Live recognition progress from [SherpaAsrEngine.transcribeUpdates].
class SherpaTranscriptUpdate {
  final String text;

  /// False for a hypothesis that may still change, true for a finished
  /// utterance.
  final bool isFinal;

  const SherpaTranscriptUpdate(this.text, {required this.isFinal});

  @override
  String toString() => 'SherpaTranscriptUpdate($text, final: $isFinal)';
}

/// Speech recognition through sherpa-onnx: Whisper, Moonshine, NeMo Parakeet,
/// Zipformer, SenseVoice, Paraformer and their streaming variants.
///
/// [loadModel] takes the model *folder* (the extracted sherpa release or
/// Hugging Face snapshot); the architecture is detected from the file names by
/// [SherpaModelLayout.detect]. Decoding runs in a dedicated isolate, so the UI
/// isolate stays free. Options go through `InferenceConfig.extra` (see
/// [SherpaAsrOptions]).
class SherpaAsrEngine implements InferenceEngine, SpeechRecognizer {
  SherpaWorker? _worker;
  SherpaAsrLayout? _layout;
  String? _modelPath;
  bool _hasVad = false;

  @override
  String get id => 'sherpa-asr';

  @override
  Set<ModelCapability> get capabilities => const {ModelCapability.speechToText};

  @override
  bool get isModelLoaded => _worker != null;

  @override
  String? get currentModelPath => _modelPath;

  /// Layout of the loaded model.
  SherpaAsrLayout? get layout => _layout;

  /// True when the loaded model is an online recognizer.
  bool get isStreamingModel => _layout?.architecture.isStreaming ?? false;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    await unloadModel();
    final options = SherpaAsrOptions.fromConfig(config);
    final layout = _resolveLayout(modelPath, options);
    final vadModel = options.vadModel;
    if (vadModel != null && !File(vadModel).existsSync()) {
      throw InferenceException('VAD model not found: $vadModel');
    }
    final args = AsrWorkerArgs(
      offline:
          layout.architecture.isStreaming
              ? null
              : buildOfflineConfig(layout, options),
      online:
          layout.architecture.isStreaming
              ? buildOnlineConfig(layout, options)
              : null,
      vad:
          vadModel == null
              ? null
              : sherpa.VadModelConfig(
                sileroVad: sherpa.SileroVadModelConfig(
                  model: vadModel,
                  threshold: options.vadThreshold,
                  minSilenceDuration: options.vadMinSilence,
                  maxSpeechDuration: options.vadMaxSpeech,
                ),
                sampleRate: _rate,
                debug: false,
              ),
    );
    _worker = await SherpaWorker.spawn(asrWorkerInit, args);
    _layout = layout;
    _modelPath = modelPath;
    _hasVad = vadModel != null;
    ToolkitLog.info(_tag, 'Loaded ${layout.architecture.name} from $modelPath');
  }

  SherpaAsrLayout _resolveLayout(String modelPath, SherpaAsrOptions options) {
    final type = FileSystemEntity.typeSync(modelPath);
    if (type == FileSystemEntityType.notFound) {
      throw InferenceException('Sherpa model folder not found: $modelPath');
    }
    if (type != FileSystemEntityType.directory) {
      throw InferenceException(
        'Sherpa models are folders, but $modelPath is a file',
      );
    }
    final layout = SherpaModelLayout.detect(
      Directory(modelPath),
      preferInt8: options.preferInt8,
      streaming: options.streaming,
    );
    if (layout is! SherpaAsrLayout) {
      throw InferenceException(
        '$modelPath is a speech synthesis model; load it with sherpa-tts',
      );
    }
    return layout;
  }

  @override
  Future<void> unloadModel() async {
    _worker?.close();
    _worker = null;
    _layout = null;
    _modelPath = null;
    _hasVad = false;
  }

  SherpaWorker get _ready =>
      _worker ?? (throw const InferenceException('No sherpa ASR model loaded'));

  /// [audio] is a WAV file (any rate or channel count) or raw PCM16 mono at
  /// 16 kHz.
  @override
  Future<String> transcribe(Uint8List audio) {
    final samples = decodeAudio(audio).resampledTo(_rate).samples;
    return _transcribeSamples(samples);
  }

  Future<String> _transcribeSamples(Float32List samples) async {
    final worker = _ready;
    if (samples.isEmpty) return '';
    return worker.request<String>(AsrDecode(_transfer(samples)));
  }

  /// Transcribes live 16 kHz mono PCM16 [pcm] and emits finished utterances.
  ///
  /// Online models endpoint on their own. Offline models need `vadModel` in
  /// `InferenceConfig.extra` to be cut into utterances; without it the whole
  /// stream is buffered and transcribed as one text when it ends.
  Stream<String> transcribeStream(Stream<Uint8List> pcm) =>
      transcribeUpdates(pcm).where((u) => u.isFinal).map((u) => u.text);

  /// Like [transcribeStream] but also reports the running hypothesis of
  /// streaming models (each partial replaces the previous one).
  Stream<SherpaTranscriptUpdate> transcribeUpdates(
    Stream<Uint8List> pcm,
  ) async* {
    final worker = _ready;
    if (!isStreamingModel && !_hasVad) {
      final all = BytesBuilder(copy: false);
      await for (final chunk in pcm) {
        all.add(chunk);
      }
      final text = await _transcribeSamples(
        pcm16ToFloat(_even(all.takeBytes())),
      );
      if (text.isNotEmpty) yield SherpaTranscriptUpdate(text, isFinal: true);
      return;
    }
    var finished = false;
    var carry = Uint8List(0);
    var lastPartial = '';
    try {
      await for (final chunk in pcm) {
        final bytes =
            BytesBuilder(copy: false)
              ..add(carry)
              ..add(chunk);
        final all = bytes.takeBytes();
        final usable = all.length - all.length % 2;
        carry = Uint8List.sublistView(all, usable);
        if (usable == 0) continue;
        final samples = pcm16ToFloat(Uint8List.sublistView(all, 0, usable));
        final (done, partial) = await worker.request<(List<Object?>, String)>(
          AsrFeed(_transfer(samples)),
        );
        for (final text in done.cast<String>()) {
          yield SherpaTranscriptUpdate(text, isFinal: true);
          lastPartial = '';
        }
        if (partial != lastPartial && partial.isNotEmpty) {
          yield SherpaTranscriptUpdate(partial, isFinal: false);
        }
        lastPartial = partial;
      }
      final rest = await worker.request<List<Object?>>(const AsrFinish());
      finished = true;
      for (final text in rest.cast<String>()) {
        yield SherpaTranscriptUpdate(text, isFinal: true);
      }
    } finally {
      if (!finished && _worker == worker) {
        await worker
            .request<List<Object?>>(const AsrFinish())
            .catchError((Object _) => <Object?>[]);
      }
    }
  }

  static Uint8List _even(Uint8List bytes) =>
      bytes.length.isEven
          ? bytes
          : Uint8List.sublistView(bytes, 0, bytes.length - 1);

  static TransferableTypedData _transfer(Float32List samples) =>
      TransferableTypedData.fromList([samples]);
}
