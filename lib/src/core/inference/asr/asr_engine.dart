import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../config.dart';
import '../../logging/toolkit_logger.dart';
import '../base_inference_engine.dart';
import 'asr_config.dart';
import 'audio_decoder.dart';
import 'chunking.dart';
import 'mel_spectrogram.dart';
import 'transcript_text.dart';
import 'wav_format.dart';
import 'whisper_output.dart';
import 'whisper_tokenizer.dart';
import 'whisper_vocab_loader.dart';

const _tag = 'ASR';

/// Whisper speech recognition on TensorFlow Lite.
///
/// Expects a Whisper TFLite model taking a float32 log-mel input of
/// `[1, 80, 3000]` (or `[1, 3000, 80]`) and producing token ids (int32/int64)
/// or logits (float32). The tokenizer vocabulary is resolved by
/// [loadWhisperTokenizer]; pass `InferenceConfig.extra['vocabPath']` to
/// choose a specific file.
class AsrEngine implements InferenceEngine, SpeechRecognizer {
  /// Whisper never looks at more than 30 seconds at once.
  static const _maxWindow = Duration(seconds: 30);

  final ASRConfig asrConfig;
  final http.Client? _httpClient;

  AsrEngine({this.asrConfig = const ASRConfig(), http.Client? httpClient})
    : _httpClient = httpClient;

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  WhisperTokenizer? _tokenizer;
  String? _modelPath;
  bool _transposeInput = false;
  OutputKind _outputKind = OutputKind.int32;
  List<int> _outputShape = const [];
  int _outputBytes = 0;
  int _maxTokens = 0;
  Future<void> _lastRun = Future.value();

  @override
  String get id => 'asr';

  @override
  Set<ModelCapability> get capabilities => const {ModelCapability.speechToText};

  @override
  bool get isModelLoaded => _interpreter != null;

  @override
  String? get currentModelPath => _modelPath;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    await unloadModel();
    final file = File(modelPath);
    if (!await file.exists()) {
      throw InferenceException('ASR model not found: $modelPath');
    }
    await _checkFlatbuffer(file);

    final options =
        InterpreterOptions()
          ..threads =
              config.threads ?? math.min(4, Platform.numberOfProcessors);
    try {
      final tokenizer = await loadWhisperTokenizer(
        modelPath,
        explicitPath: config.extra['vocabPath'] as String?,
        client: _httpClient,
      );
      final interpreter = Interpreter.fromFile(file, options: options);
      try {
        _configureTensors(interpreter);
        _isolateInterpreter = await IsolateInterpreter.create(
          address: interpreter.address,
        );
      } catch (_) {
        interpreter.close();
        rethrow;
      }
      _interpreter = interpreter;
      _tokenizer = tokenizer;
      _modelPath = modelPath;
      _maxTokens = config.maxTokens ?? asrConfig.maxTokens;
      ToolkitLog.info(
        _tag,
        'Loaded $modelPath (output $_outputKind $_outputShape, '
        '${tokenizer.vocabularySize} tokens)',
      );
    } on LLMToolkitException {
      await unloadModel();
      rethrow;
    } catch (e) {
      await unloadModel();
      throw InferenceException('Failed to load ASR model', e);
    } finally {
      options.delete();
    }
  }

  @override
  Future<void> unloadModel() async {
    try {
      await _lastRun;
    } catch (_) {
      // The failure was already reported to its caller.
    }
    await _isolateInterpreter?.close();
    _isolateInterpreter = null;
    _interpreter?.close();
    _interpreter = null;
    _tokenizer = null;
    _modelPath = null;
  }

  /// Transcribes a WAV file or raw 16-bit mono PCM at [ASRConfig.sampleRate].
  /// Audio longer than [ASRConfig.chunkDuration] is split into overlapping
  /// windows whose texts are merged without the repeated words.
  @override
  Future<String> transcribe(Uint8List audio) async {
    if (!isModelLoaded) {
      throw const InferenceException('ASR model not loaded');
    }
    final format = AudioFormat.sniff(audio);
    final inputRate = asrConfig.sampleRate;
    final decoded = await Isolate.run(
      () => decodeAudio(
        audio,
        format: format,
        sampleRate: inputRate,
      ).resampledTo(MelSpectrogram.sampleRate),
    );
    if (decoded.samples.isEmpty) return '';

    final modelRate = asrConfig.copyWith(sampleRate: MelSpectrogram.sampleRate);
    final chunk = math.min(
      modelRate.chunkSamples,
      _maxWindow.inSeconds * MelSpectrogram.sampleRate,
    );
    final overlap = math.min(modelRate.overlapSamples, chunk ~/ 2);
    final texts = await transcribeWindows(
      decoded.samples,
      chunk: chunk,
      overlap: overlap,
      transcribe: _transcribeWindow,
    );
    final merged = TranscriptAccumulator();
    for (final text in texts) {
      merged.add(text);
    }
    return merged.text;
  }

  Future<String> _transcribeWindow(Float32List window) async {
    final mel = await computeMelSpectrogram(window);
    final input = _transposeInput ? _transpose(mel) : mel;
    final output = await _serialized(() => _run(input));
    final ids = tokenIdsFromOutput(
      output,
      _outputKind,
      _outputShape,
      maxTokens: _maxTokens,
    );
    return _tokenizer!.decode(ids);
  }

  Future<Uint8List> _run(Float32List input) async {
    final isolate = _isolateInterpreter;
    if (isolate == null) {
      throw const InferenceException('ASR model unloaded during inference');
    }
    final output = Uint8List(_outputBytes);
    try {
      await isolate.run(input.buffer.asUint8List(), output);
    } catch (e) {
      throw InferenceException('ASR inference failed', e);
    }
    return output;
  }

  /// The native interpreter handles one request at a time.
  Future<T> _serialized<T>(Future<T> Function() task) {
    final result = _lastRun.then((_) => task());
    _lastRun = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _configureTensors(Interpreter interpreter) {
    final inputs = interpreter.getInputTensors();
    final outputs = interpreter.getOutputTensors();
    if (inputs.isEmpty || outputs.isEmpty) {
      throw const InferenceException('Model has no input or output tensors');
    }
    final input = inputs.first;
    if (input.type != TensorType.float32) {
      throw InferenceException(
        'Unsupported ASR input type ${input.type}; expected float32 log-mel',
      );
    }
    final shape = input.shape;
    final expected = [MelSpectrogram.nMels, MelSpectrogram.nFrames];
    final trailing =
        shape.length >= 2 ? shape.sublist(shape.length - 2) : shape;
    if (trailing[0] == expected[0] && trailing[1] == expected[1]) {
      _transposeInput = false;
    } else if (trailing[0] == expected[1] && trailing[1] == expected[0]) {
      _transposeInput = true;
    } else {
      throw InferenceException(
        'Unsupported ASR input shape $shape; expected [1, 80, 3000]',
      );
    }

    final output = outputs.first;
    _outputKind = switch (output.type) {
      TensorType.int32 => OutputKind.int32,
      TensorType.int64 => OutputKind.int64,
      TensorType.float32 => OutputKind.float32,
      final other =>
        throw InferenceException('Unsupported ASR output type $other'),
    };
    _outputShape = output.shape;
    _outputBytes =
        _outputShape.fold(1, (a, b) => a * b) *
        switch (_outputKind) {
          OutputKind.int64 => 8,
          _ => 4,
        };
  }

  static Future<void> _checkFlatbuffer(File file) async {
    final head = await file
        .openRead(0, 8)
        .fold<List<int>>([], (a, b) => a..addAll(b));
    final ident = head.length >= 8 ? String.fromCharCodes(head, 4, 8) : '';
    if (ident != 'TFL3') {
      throw InferenceException('${file.path} is not a TensorFlow Lite model');
    }
  }

  /// `[mel][frame]` -> `[frame][mel]`.
  static Float32List _transpose(Float32List mel) {
    const rows = MelSpectrogram.nMels;
    const cols = MelSpectrogram.nFrames;
    final out = Float32List(mel.length);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        out[c * rows + r] = mel[r * cols + c];
      }
    }
    return out;
  }
}
