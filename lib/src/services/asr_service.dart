import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/config.dart';
import '../core/inference/asr/asr_config.dart';
import '../core/inference/asr/asr_engine.dart';
import '../core/inference/asr/audio_decoder.dart';
import '../core/inference/asr/chunking.dart';
import '../core/inference/asr/pcm_recorder.dart';
import '../core/inference/asr/transcript_text.dart';
import '../core/inference/asr/vad.dart';
import '../core/inference/asr/wav_format.dart';
import '../core/inference/base_inference_engine.dart';
import '../core/logging/toolkit_logger.dart';
import '../exceptions/llm_toolkit_exceptions.dart';

const _tag = 'ASRService';

enum _Mode { idle, recording, streaming }

/// High-level speech recognition: file/bytes transcription, microphone
/// recording (plain, timed, voice-activated) and live streaming transcription.
///
/// Use [ASRService.new] followed by [initialize] with a Whisper TFLite model, or
/// [ASRService.withRecognizer] to plug in any [SpeechRecognizer] (and a custom
/// [PcmRecorder]), e.g. in tests.
class ASRService {
  ASRService({ASRConfig config = const ASRConfig(), PcmRecorder? recorder})
    : _config = config,
      _recorder = recorder,
      _ownsRecognizer = true;

  ASRService.withRecognizer(
    SpeechRecognizer recognizer, {
    ASRConfig config = const ASRConfig(),
    PcmRecorder? recorder,
  }) : _config = config,
       _recorder = recorder,
       _recognizer = recognizer,
       _ownsRecognizer = false;

  final ASRConfig _config;
  final bool _ownsRecognizer;
  SpeechRecognizer? _recognizer;
  PcmRecorder? _recorder;

  String? _modelPath;
  _Mode _mode = _Mode.idle;

  _Capture? _capture;
  _StreamingSession? _session;

  ASRConfig get config => _config;
  bool get isInitialized => _recognizer != null;
  bool get isRecording => _mode == _Mode.recording;
  bool get isStreaming => _mode == _Mode.streaming;
  String? get currentModelPath => _modelPath;

  /// Loads the Whisper TFLite model at [modelPath] into a new [AsrEngine].
  Future<void> initialize(
    String modelPath, {
    InferenceConfig inferenceConfig = const InferenceConfig(),
  }) async {
    if (!_ownsRecognizer) {
      throw StateError('This service was created with its own recognizer');
    }
    await _releaseEngine();
    final engine = AsrEngine(asrConfig: _config);
    try {
      await engine.loadModel(modelPath, inferenceConfig);
    } catch (e) {
      throw e is LLMToolkitException
          ? e
          : InferenceException('Failed to initialize ASR service', e);
    }
    _recognizer = engine;
    _modelPath = modelPath;
  }

  /// Transcribes an audio file. `.pcm`/`.raw` files are read as 16-bit mono PCM
  /// at [ASRConfig.sampleRate]; anything else is detected from its header.
  Future<String> transcribeFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw InferenceException('Audio file not found: $path');
    }
    final raw = const {
      '.pcm',
      '.raw',
    }.contains(p.extension(path).toLowerCase());
    return transcribeBytes(
      await file.readAsBytes(),
      format: raw ? AudioFormat.pcm16 : null,
    );
  }

  /// Transcribes in-memory audio. [format] defaults to auto-detection (WAV
  /// header, else PCM16); [sampleRate] applies to the raw formats.
  Future<String> transcribeBytes(
    Uint8List bytes, {
    AudioFormat? format,
    int? sampleRate,
  }) async {
    final recognizer = _requireRecognizer();
    final rate = sampleRate ?? _config.sampleRate;
    final kind = format ?? AudioFormat.sniff(bytes);
    final wav = switch (kind) {
      AudioFormat.wav => bytes,
      AudioFormat.pcm16 => wrapPcm16AsWav(bytes, rate),
      _ => encodeWav16(
        decodeAudio(bytes, format: kind, sampleRate: rate).samples,
        rate,
      ),
    };
    return recognizer.transcribe(wav);
  }

  /// Starts capturing from the microphone; finish with [stopRecording].
  Future<void> startRecording() async {
    _requireRecognizer();
    _requireIdle();
    await _startCapture();
  }

  /// Stops capturing and returns the transcription of everything recorded.
  Future<String> stopRecording() async {
    if (!isRecording) throw const InferenceException('Not recording');
    final pcm = await _finishCapture();
    _mode = _Mode.idle;
    return pcm.isEmpty ? '' : transcribeBytes(pcm, format: AudioFormat.pcm16);
  }

  /// Records for [duration] and returns the transcription.
  Future<String> recordAndTranscribe(Duration duration) async {
    await startRecording();
    await Future<void>.delayed(duration);
    return stopRecording();
  }

  /// Records until [silenceTimeout] of silence follows (or [maxDuration] is
  /// reached), then returns the transcription. Defaults come from [config].
  Future<String> recordWithVAD({
    Duration maxDuration = const Duration(seconds: 30),
    Duration? silenceTimeout,
    double? silenceThreshold,
  }) async {
    _requireRecognizer();
    _requireIdle();
    final endpoint = EndpointDetector(
      vad: VoiceActivityDetector(
        threshold: silenceThreshold ?? _config.vadSilenceThreshold,
      ),
      sampleRate: _config.sampleRate,
      silenceTimeout: silenceTimeout ?? _config.vadSilenceTimeout,
    );
    final finished = Completer<void>();
    await _startCapture(
      onData: (bytes) {
        if (!finished.isCompleted && endpoint.feed(pcm16ToFloat(bytes))) {
          finished.complete();
        }
      },
    );
    final timer = Timer(maxDuration, () {
      if (!finished.isCompleted) finished.complete();
    });
    try {
      await finished.future;
    } finally {
      timer.cancel();
    }
    return stopRecording();
  }

  /// Starts the microphone and emits newly recognised text as each window
  /// completes. Windows overlap by [ASRConfig.overlapDuration]; repeated words
  /// are removed so the emitted pieces concatenate into one transcript. Cancel
  /// the subscription or call [stopStreamingTranscription] to end.
  Stream<String> startStreamingTranscription() {
    final controller = StreamController<String>(
      onCancel: stopStreamingTranscription,
    );
    unawaited(_startStreaming(controller));
    return controller.stream;
  }

  Future<void> _startStreaming(StreamController<String> controller) async {
    try {
      _requireRecognizer();
      _requireIdle();
      final session = _StreamingSession(this, controller);
      _session = session;
      _mode = _Mode.streaming;
      await _beginCapture(onData: session.onAudio);
    } catch (e, st) {
      _session = null;
      _mode = _Mode.idle;
      controller.addError(e, st);
      await controller.close();
    }
  }

  /// Stops live transcription after transcribing the audio still buffered.
  Future<void> stopStreamingTranscription() async {
    final session = _session;
    if (session == null) return;
    _session = null;
    try {
      await _finishCapture();
      await session.finish();
    } finally {
      _mode = _Mode.idle;
    }
  }

  /// Whether microphone permission is (or can be) granted.
  Future<bool> testMicrophoneAccess() async {
    try {
      return await _micRecorder.hasPermission();
    } catch (e) {
      ToolkitLog.warning(_tag, 'Microphone check failed', e);
      return false;
    }
  }

  /// Stops any capture, unloads an owned model and releases the recorder.
  Future<void> dispose() async {
    try {
      if (isStreaming) {
        await stopStreamingTranscription();
      } else if (isRecording) {
        await _finishCapture();
      }
    } catch (e) {
      ToolkitLog.warning(_tag, 'Error while stopping capture', e);
    }
    _mode = _Mode.idle;
    await _releaseEngine();
    await _recorder?.dispose();
    _recorder = null;
  }

  PcmRecorder get _micRecorder => _recorder ??= RecordPcmRecorder();

  SpeechRecognizer _requireRecognizer() =>
      _recognizer ??
      (throw const InferenceException('ASR service not initialized'));

  void _requireIdle() {
    if (_mode != _Mode.idle) {
      throw InferenceException('Already ${_mode.name}');
    }
  }

  Future<void> _releaseEngine() async {
    if (_ownsRecognizer) {
      final engine = _recognizer;
      _recognizer = null;
      _modelPath = null;
      if (engine is AsrEngine) await engine.unloadModel();
    }
  }

  /// Marks the service as recording and starts the recorder.
  Future<void> _startCapture({void Function(Uint8List bytes)? onData}) async {
    _mode = _Mode.recording;
    try {
      await _beginCapture(onData: onData);
    } catch (_) {
      _mode = _Mode.idle;
      rethrow;
    }
  }

  Future<void> _beginCapture({void Function(Uint8List bytes)? onData}) async {
    final recorder = _micRecorder;
    if (!await recorder.hasPermission()) {
      throw const InferenceException('Microphone permission not granted');
    }
    final stream = await recorder.start(_config.sampleRate);
    _capture = _Capture(stream, onData);
  }

  /// Stops the recorder and returns all PCM16 captured since [_beginCapture].
  Future<Uint8List> _finishCapture() async {
    final capture = _capture;
    _capture = null;
    if (capture == null) return Uint8List(0);
    await _micRecorder.stop();
    return capture.finish();
  }
}

/// Accumulates the PCM16 chunks of one recording session.
class _Capture {
  _Capture(Stream<Uint8List> stream, void Function(Uint8List)? onData) {
    _subscription = stream.listen(
      (bytes) {
        _pcm.add(bytes);
        onData?.call(bytes);
      },
      onError:
          (Object e, StackTrace st) =>
              ToolkitLog.warning(_tag, 'Recorder stream error', e),
      onDone: _done.complete,
    );
  }

  final BytesBuilder _pcm = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<Uint8List> _subscription;

  Future<Uint8List> finish() async {
    await _done.future.timeout(const Duration(seconds: 1), onTimeout: () {});
    await _subscription.cancel();
    return _pcm.takeBytes();
  }
}

/// One live-transcription run: windows the incoming audio, transcribes the
/// windows one at a time and emits only text not already emitted.
class _StreamingSession {
  _StreamingSession(this._service, this._out)
    : _windower = PcmWindower(
        windowSamples: _service._config.chunkSamples,
        overlapSamples: _service._config.overlapSamples,
      ),
      _vad = VoiceActivityDetector(
        threshold: _service._config.vadSilenceThreshold,
      );

  final ASRService _service;
  final StreamController<String> _out;
  final PcmWindower _windower;
  final VoiceActivityDetector _vad;
  final TranscriptAccumulator _transcript = TranscriptAccumulator();
  Future<void> _work = Future.value();

  void onAudio(Uint8List bytes) {
    _windower.add(bytes);
    for (
      var w = _windower.takeWindow();
      w != null;
      w = _windower.takeWindow()
    ) {
      _enqueue(w);
    }
  }

  /// Transcribes the audio left in the buffer, then closes the stream.
  Future<void> finish() async {
    final rest = _windower.flush(
      minNewSamples: _service._config.sampleRate ~/ 2,
    );
    if (rest != null) _enqueue(rest);
    await _work;
    if (!_out.isClosed) await _out.close();
  }

  void _enqueue(Uint8List window) {
    _work = _work.then((_) => _transcribe(window));
  }

  Future<void> _transcribe(Uint8List window) async {
    if (_out.isClosed) return;
    if (_service._config.enableVAD &&
        !_vad.containsSpeech(pcm16ToFloat(window))) {
      return;
    }
    try {
      final text = await _service.transcribeBytes(
        window,
        format: AudioFormat.pcm16,
      );
      if (!isMeaningfulTranscript(text)) return;
      final fresh = _transcript.add(text);
      if (fresh.isNotEmpty && !_out.isClosed) _out.add(fresh);
    } catch (e) {
      ToolkitLog.warning(_tag, 'Streaming window failed', e);
    }
  }
}
