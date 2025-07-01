import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../config.dart';
import 'base_inference_engine.dart';
import '../../exceptions/llm_toolkit_exceptions.dart';

class TFLiteASREngine extends BaseInferenceEngine {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  String? _currentModelPath;
  ASRModelType? _modelType;
  Map<int, String>? _vocabulary;
  List<int>? _inputShape;
  List<int>? _outputShape;

  // Audio preprocessing parameters
  int _sampleRate = 16000;
  int _nMels = 80;
  int _nFFT = 400;
  int _hopLength = 160;
  double _preemphasis = 0.97;

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    if (_interpreter != null) {
      await unloadModel();
    }

    try {
      print('🎤 Loading TFLite ASR model: $modelPath');

      // Load the TFLite model
      _interpreter = await Interpreter.fromFile(File(modelPath));

      // Analyze model structure
      await _analyzeModelStructure();

      // Detect model type based on path and structure
      _modelType = _detectASRModelType(modelPath);

      // Load vocabulary if available
      await _loadVocabulary(modelPath);

      // Configure audio parameters based on model type
      _configureAudioParameters();

      _isModelLoaded = true;
      _currentModelPath = modelPath;

      print('✅ TFLite ASR model loaded successfully');
      print('   Model Type: ${_modelType?.name}');
      print('   Input Shape: $_inputShape');
      print('   Output Shape: $_outputShape');
      print('   Sample Rate: $_sampleRate Hz');
    } catch (e) {
      throw InferenceException('Failed to load TFLite ASR model: $e');
    }
  }

  /// Main transcription method supporting various audio formats
  Future<String> transcribeAudio(
    Uint8List audioData, {
    int sampleRate = 16000,
    AudioFormat format = AudioFormat.pcm16,
    bool isMonoChannel = true,
  }) async {
    if (!_isModelLoaded || _interpreter == null) {
      throw InferenceException('TFLite ASR model not loaded');
    }

    try {
      print('🎤 Starting audio transcription...');
      print('   Audio size: ${audioData.length} bytes');
      print('   Sample rate: $sampleRate Hz');
      print('   Format: ${format.name}');

      // Step 1: Convert audio data to float samples
      final audioSamples = _convertAudioToSamples(audioData, format);
      print('   Converted to ${audioSamples.length} samples');

      // Step 2: Resample if necessary
      final resampledAudio =
          sampleRate != _sampleRate
              ? _resampleAudio(audioSamples, sampleRate, _sampleRate)
              : audioSamples;
      print(
        '   Resampled to ${resampledAudio.length} samples at $_sampleRate Hz',
      );

      // Step 3: Preprocess audio based on model type
      final processedInput = await _preprocessAudioForModel(resampledAudio);

      // Step 4: Run inference
      final output = await _runInference(processedInput);

      // Step 5: Post-process output to text
      final transcription = await _postprocessOutput(output);

      print(
        '✅ Transcription complete: "${transcription.substring(0, math.min(50, transcription.length))}..."',
      );
      return transcription;
    } catch (e) {
      throw InferenceException('Audio transcription failed: $e');
    }
  }

  /// Convert raw audio bytes to float samples
  List<double> _convertAudioToSamples(Uint8List audioData, AudioFormat format) {
    final samples = <double>[];

    switch (format) {
      case AudioFormat.pcm16:
        // 16-bit PCM: 2 bytes per sample
        for (int i = 0; i < audioData.length - 1; i += 2) {
          final sample = (audioData[i] | (audioData[i + 1] << 8));
          // Convert from signed 16-bit to float [-1.0, 1.0]
          final normalizedSample =
              sample > 32767 ? (sample - 65536) / 32768.0 : sample / 32768.0;
          samples.add(normalizedSample);
        }
        break;

      case AudioFormat.pcm32:
        // 32-bit PCM: 4 bytes per sample
        for (int i = 0; i < audioData.length - 3; i += 4) {
          final sample =
              (audioData[i] |
                  (audioData[i + 1] << 8) |
                  (audioData[i + 2] << 16) |
                  (audioData[i + 3] << 24));
          final normalizedSample = sample / 2147483648.0;
          samples.add(normalizedSample);
        }
        break;

      case AudioFormat.float32:
        // 32-bit float: 4 bytes per sample
        final byteData = ByteData.sublistView(audioData);
        for (int i = 0; i < audioData.length - 3; i += 4) {
          samples.add(byteData.getFloat32(i, Endian.little));
        }
        break;
    }

    return samples;
  }

  /// Simple linear resampling (for production, use a proper resampling library)
  List<double> _resampleAudio(List<double> audio, int fromRate, int toRate) {
    if (fromRate == toRate) return audio;

    final ratio = fromRate / toRate;
    final newLength = (audio.length / ratio).round();
    final resampled = <double>[];

    for (int i = 0; i < newLength; i++) {
      final sourceIndex = (i * ratio).round();
      if (sourceIndex < audio.length) {
        resampled.add(audio[sourceIndex]);
      }
    }

    return resampled;
  }

  /// Preprocess audio based on detected model type
  Future<List<List<double>>> _preprocessAudioForModel(
    List<double> audioSamples,
  ) async {
    switch (_modelType) {
      case ASRModelType.whisper:
        return _preprocessForWhisper(audioSamples);
      case ASRModelType.wav2vec2:
        return _preprocessForWav2Vec2(audioSamples);
      case ASRModelType.deepspeech:
        return _preprocessForDeepSpeech(audioSamples);
      case ASRModelType.speechRecognition:
        return _preprocessForSpeechRecognition(audioSamples);
      default:
        return _preprocessGeneric(audioSamples);
    }
  }

  List<List<double>> _preprocessForWhisper(List<double> audioSamples) {
    const int WHISPER_SAMPLE_RATE = 16000;
    const int WHISPER_N_SAMPLES = 30 * WHISPER_SAMPLE_RATE;
    List<double> paddedAudio;
    if (audioSamples.length > WHISPER_N_SAMPLES) {
      paddedAudio = audioSamples.sublist(0, WHISPER_N_SAMPLES);
    } else {
      paddedAudio = [...audioSamples];
      while (paddedAudio.length < WHISPER_N_SAMPLES) {
        paddedAudio.add(0.0);
      }
    }
    final melSpectrogram = _computeWhisperMelSpectrogram(paddedAudio);

    // Whisper expects shape [1, 80, 3000] for mel spectrogram
    return [melSpectrogram.expand((row) => row).toList()];
  }

  double log10(num x) => log(x) / ln10;
  // Add this method to your TFLiteASREngine class
  List<List<double>> _computeSTFT(List<double> audio, int nFFT, int hopLength) {
    final windowSize = nFFT;
    final numFrames = ((audio.length - windowSize) / hopLength).floor() + 1;
    final stftFrames = <List<double>>[];

    for (int frame = 0; frame < numFrames; frame++) {
      final start = frame * hopLength;
      final end = math.min(start + windowSize, audio.length);

      // Extract window
      List<double> window = audio.sublist(start, end);

      // Pad with zeros if necessary
      if (window.length < windowSize) {
        window.addAll(List.filled(windowSize - window.length, 0.0));
      }

      // Apply Hanning window
      final windowed = _applyHanningWindow(window);

      // Compute FFT magnitude spectrum
      final fftMagnitude = _computeFFTMagnitude(windowed);

      stftFrames.add(fftMagnitude);
    }

    return stftFrames;
  }

  // Enhanced Hanning window implementation
  List<double> _applyHanningWindow(List<double> signal) {
    final n = signal.length;
    final windowed = <double>[];

    for (int i = 0; i < n; i++) {
      final window = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      windowed.add(signal[i] * window);
    }

    return windowed;
  }

  // Enhanced FFT magnitude computation
  List<double> _computeFFTMagnitude(List<double> signal) {
    final n = signal.length;
    final magnitude = <double>[];

    // Compute only positive frequencies (n/2 + 1)
    for (int k = 0; k <= n ~/ 2; k++) {
      double real = 0.0;
      double imag = 0.0;

      for (int t = 0; t < n; t++) {
        final angle = -2 * math.pi * k * t / n;
        real += signal[t] * math.cos(angle);
        imag += signal[t] * math.sin(angle);
      }

      magnitude.add(math.sqrt(real * real + imag * imag));
    }

    return magnitude;
  }

  List<List<double>> _computeWhisperMelSpectrogram(List<double> audio) {
    const int N_FFT = 400;
    const int HOP_LENGTH = 160;
    const int N_MELS = 80;
    const int N_SAMPLES = 480000;
    final melFilters = _createMelFilterBank(N_FFT ~/ 2 + 1, N_MELS, 16000);
    final stft = _computeSTFT(audio, N_FFT, HOP_LENGTH);
    final melSpectrogram = <List<double>>[];
    for (final frame in stft) {
      final melFrame = <double>[];
      for (int i = 0; i < N_MELS; i++) {
        double melValue = 0.0;
        for (int j = 0; j < frame.length; j++) {
          melValue += frame[j] * melFilters[i][j];
        }
        melFrame.add(math.log(math.max(melValue, 1e-10)));
      }
      melSpectrogram.add(melFrame);
    }

    return melSpectrogram;
  }

  List<List<double>> _createMelFilterBank(int nFft, int nMels, int sampleRate) {
    double hzToMel(double hz) => 2595.0 * log10(1.0 + hz / 700.0);
    double melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);
    final melMin = hzToMel(0.0);
    final melMax = hzToMel(sampleRate / 2.0);
    final melPoints = <double>[];

    for (int i = 0; i <= nMels + 1; i++) {
      final mel = melMin + (melMax - melMin) * i / (nMels + 1);
      melPoints.add(melToHz(mel));
    }
    final binPoints =
        melPoints.map((hz) => (nFft * hz / sampleRate).floor()).toList();
    final filterBank = <List<double>>[];
    for (int i = 1; i <= nMels; i++) {
      final filter = List<double>.filled(nFft, 0.0);
      final left = binPoints[i - 1];
      final center = binPoints[i];
      final right = binPoints[i + 1];

      for (int j = left; j < center; j++) {
        if (j < nFft) filter[j] = (j - left) / (center - left);
      }
      for (int j = center; j < right; j++) {
        if (j < nFft) filter[j] = (right - j) / (right - center);
      }

      filterBank.add(filter);
    }

    return filterBank;
  }

  List<List<double>> _preprocessForWav2Vec2(List<double> audioSamples) {
    final mean = audioSamples.reduce((a, b) => a + b) / audioSamples.length;
    final variance =
        audioSamples
            .map((x) => (x - mean) * (x - mean))
            .reduce((a, b) => a + b) /
        audioSamples.length;
    final std = math.sqrt(variance);

    final normalized =
        audioSamples.map((x) => (x - mean) / (std + 1e-8)).toList();
    final targetLength = _inputShape![1];
    final processed = _padOrTruncateAudio(normalized, targetLength);

    return [processed];
  }

  List<List<double>> _preprocessForDeepSpeech(List<double> audioSamples) {
    // DeepSpeech typically uses MFCC features
    final mfccFeatures = _computeMFCC(audioSamples);
    return [mfccFeatures.expand((row) => row).toList()];
  }

  List<List<double>> _preprocessForSpeechRecognition(
    List<double> audioSamples,
  ) {
    final melSpectrogram = _computeMelSpectrogram(audioSamples);

    // Take log
    final logMelSpectrogram =
        melSpectrogram
            .map((row) => row.map((val) => math.log(val + 1e-8)).toList())
            .toList();

    return [logMelSpectrogram.expand((row) => row).toList()];
  }

  /// Generic preprocessing for unknown models
  List<List<double>> _preprocessGeneric(List<double> audioSamples) {
    // Try to match the input shape
    final targetLength =
        _inputShape!.reduce((a, b) => a * b) ~/ _inputShape![0];
    final processed = _padOrTruncateAudio(audioSamples, targetLength);
    return [processed];
  }

  /// Apply pre-emphasis filter
  List<double> _applyPreemphasis(List<double> audio) {
    if (audio.isEmpty) return audio;

    final filtered = <double>[audio[0]];
    for (int i = 1; i < audio.length; i++) {
      filtered.add(audio[i] - _preemphasis * audio[i - 1]);
    }
    return filtered;
  }

  /// Pad or truncate audio to target length
  List<double> _padOrTruncateAudio(List<double> audio, int targetLength) {
    if (audio.length == targetLength) return audio;

    if (audio.length > targetLength) {
      return audio.sublist(0, targetLength);
    } else {
      return [...audio, ...List.filled(targetLength - audio.length, 0.0)];
    }
  }

  /// Compute mel spectrogram (simplified implementation)
  List<List<double>> _computeMelSpectrogram(List<double> audio) {
    // This is a simplified implementation
    // For production, use a proper audio processing library

    final windowSize = _nFFT;
    final numFrames = ((audio.length - windowSize) / _hopLength).floor() + 1;
    final spectrogram = <List<double>>[];

    for (int frame = 0; frame < numFrames; frame++) {
      final start = frame * _hopLength;
      final end = math.min(start + windowSize, audio.length);

      // Extract window
      final window = audio.sublist(start, end);
      if (window.length < windowSize) {
        window.addAll(List.filled(windowSize - window.length, 0.0));
      }

      // Apply Hanning window
      final windowed = _applyHanningWindow(window);

      // Compute FFT magnitude (simplified)
      final fftMagnitude = _computeFFTMagnitude(windowed);

      // Apply mel filter banks
      final melFiltered = _applyMelFilterBanks(fftMagnitude);

      spectrogram.add(melFiltered);
    }

    return spectrogram;
  }

  /// Compute MFCC features (simplified)
  List<List<double>> _computeMFCC(List<double> audio) {
    final melSpectrogram = _computeMelSpectrogram(audio);

    // Take log
    final logMel =
        melSpectrogram
            .map((frame) => frame.map((val) => math.log(val + 1e-8)).toList())
            .toList();

    // Apply DCT (simplified - just return log mel for now)
    return logMel;
  }

  List<double> _applyMelFilterBanks(List<double> fftMagnitude) {
    // Simplified mel filter bank implementation
    final melFiltered = <double>[];
    final numFilters = _nMels;
    final fftSize = fftMagnitude.length;

    for (int i = 0; i < numFilters; i++) {
      double sum = 0.0;
      final start = (i * fftSize / numFilters).floor();
      final end = ((i + 1) * fftSize / numFilters).floor();

      for (int j = start; j < end && j < fftSize; j++) {
        sum += fftMagnitude[j];
      }

      melFiltered.add(sum / (end - start));
    }

    return melFiltered;
  }

  /// Run inference on preprocessed input
  Future<List> _runInference(List<List<double>> input) async {
    try {
      // Prepare output tensor
      final output = List.filled(
        _outputShape!.reduce((a, b) => a * b),
        0.0,
      ).reshape(_outputShape!);

      // Run inference
      _interpreter!.run(input, output);

      return output;
    } catch (e) {
      throw InferenceException('Inference failed: $e');
    }
  }

  /// Post-process model output to text
  Future<String> _postprocessOutput(List output) async {
    switch (_modelType) {
      case ASRModelType.whisper:
        return _decodeWhisperOutput(output);
      case ASRModelType.wav2vec2:
        return _decodeWav2Vec2Output(output);
      case ASRModelType.deepspeech:
        return _decodeDeepSpeechOutput(output);
      case ASRModelType.speechRecognition:
        return _decodeSpeechRecognitionOutput(output);
      default:
        return _decodeGenericOutput(output);
    }
  }

  /// Decode Whisper model output
  String _decodeWhisperOutput(List output) {
    // Whisper outputs token IDs that need to be decoded
    final tokenIds = <int>[];

    if (output[0] is List) {
      final logits = output[0] as List<double>;

      // Simple greedy decoding - take argmax
      for (int i = 0; i < logits.length; i += (_vocabulary?.length ?? 50257)) {
        final slice = logits.sublist(
          i,
          math.min(i + (_vocabulary?.length ?? 50257), logits.length),
        );
        final maxIndex = slice.indexOf(slice.reduce((a, b) => a > b ? a : b));
        tokenIds.add(maxIndex);
      }
    }

    // Decode tokens to text
    return _decodeTokens(tokenIds);
  }

  /// Decode Wav2Vec2 model output
  String _decodeWav2Vec2Output(List output) {
    // Wav2Vec2 outputs character probabilities
    final logits = output[0] as List<double>;
    final chars = <String>[];

    // Simple greedy decoding
    for (int i = 0; i < logits.length; i += 32) {
      // Assuming 32 character classes
      final slice = logits.sublist(i, math.min(i + 32, logits.length));
      final maxIndex = slice.indexOf(slice.reduce((a, b) => a > b ? a : b));

      // Convert index to character (simplified)
      if (maxIndex > 0 && maxIndex < 27) {
        chars.add(String.fromCharCode(96 + maxIndex)); // a-z
      } else if (maxIndex == 27) {
        chars.add(' ');
      }
    }

    return chars.join('').trim();
  }

  /// Decode DeepSpeech model output
  String _decodeDeepSpeechOutput(List output) {
    // DeepSpeech uses CTC decoding
    return _performCTCDecoding(output[0] as List<double>);
  }

  /// Decode generic speech recognition output
  String _decodeSpeechRecognitionOutput(List output) {
    // Try to interpret as character probabilities
    final logits = output[0] as List<double>;
    final result = StringBuffer();

    // Simple character-level decoding
    for (int i = 0; i < logits.length; i += 29) {
      // 26 letters + space + blank + apostrophe
      final slice = logits.sublist(i, math.min(i + 29, logits.length));
      final maxIndex = slice.indexOf(slice.reduce((a, b) => a > b ? a : b));

      if (maxIndex == 0) continue; // blank token
      if (maxIndex == 27) {
        result.write(' ');
      } else if (maxIndex == 28) {
        result.write("'");
      } else if (maxIndex > 0 && maxIndex < 27) {
        result.write(String.fromCharCode(96 + maxIndex));
      }
    }

    return result.toString().trim();
  }

  /// Generic output decoding
  String _decodeGenericOutput(List output) {
    // Try to find the most likely interpretation
    if (output[0] is List<double>) {
      final probs = output[0] as List<double>;
      final maxIndex = probs.indexOf(probs.reduce((a, b) => a > b ? a : b));
      return 'Detected class: $maxIndex (confidence: ${probs[maxIndex].toStringAsFixed(3)})';
    }

    return 'Generic output: ${output.toString().substring(0, math.min(100, output.toString().length))}';
  }

  /// Perform CTC decoding (simplified)
  String _performCTCDecoding(List<double> logits) {
    final chars = <String>[];
    String lastChar = '';

    for (int i = 0; i < logits.length; i += 29) {
      final slice = logits.sublist(i, math.min(i + 29, logits.length));
      final maxIndex = slice.indexOf(slice.reduce((a, b) => a > b ? a : b));

      String currentChar = '';
      if (maxIndex == 0) {
        currentChar = ''; // blank
      } else if (maxIndex == 27) {
        currentChar = ' ';
      } else if (maxIndex > 0 && maxIndex < 27) {
        currentChar = String.fromCharCode(96 + maxIndex);
      }

      // CTC rule: don't repeat consecutive characters
      if (currentChar.isNotEmpty && currentChar != lastChar) {
        chars.add(currentChar);
      }
      lastChar = currentChar;
    }

    return chars.join('');
  }

  /// Decode token IDs to text
  String _decodeTokens(List<int> tokenIds) {
    if (_vocabulary == null) {
      return 'Token IDs: ${tokenIds.take(20).join(', ')}...';
    }

    final words = <String>[];
    for (int tokenId in tokenIds) {
      final word = _vocabulary![tokenId];
      if (word != null && word != '<pad>' && word != '<blank>') {
        words.add(word);
      }
    }

    return words.join(' ').trim();
  }

  /// Analyze model structure
  Future<void> _analyzeModelStructure() async {
    final inputTensors = _interpreter!.getInputTensors();
    final outputTensors = _interpreter!.getOutputTensors();

    if (inputTensors.isNotEmpty) {
      _inputShape = inputTensors[0].shape;
    }

    if (outputTensors.isNotEmpty) {
      _outputShape = outputTensors[0].shape;
    }

    print('📊 Model Analysis:');
    for (int i = 0; i < inputTensors.length; i++) {
      print('   Input $i: ${inputTensors[i].shape} (${inputTensors[i].type})');
    }
    for (int i = 0; i < outputTensors.length; i++) {
      print(
        '   Output $i: ${outputTensors[i].shape} (${outputTensors[i].type})',
      );
    }
  }

  /// Detect ASR model type from path and structure
  ASRModelType _detectASRModelType(String modelPath) {
    final lowerPath = modelPath.toLowerCase();

    if (lowerPath.contains('whisper')) {
      return ASRModelType.whisper;
    } else if (lowerPath.contains('wav2vec')) {
      return ASRModelType.wav2vec2;
    } else if (lowerPath.contains('deepspeech')) {
      return ASRModelType.deepspeech;
    } else if (lowerPath.contains('speech') || lowerPath.contains('asr')) {
      return ASRModelType.speechRecognition;
    }

    // Try to detect from model structure
    if (_inputShape != null && _outputShape != null) {
      // Whisper typically has mel spectrogram input
      if (_inputShape!.length >= 2 && _inputShape![1] == 80) {
        return ASRModelType.whisper;
      }

      // Wav2Vec2 typically has raw audio input
      if (_inputShape!.length == 2 && _inputShape![1] > 10000) {
        return ASRModelType.wav2vec2;
      }
    }

    return ASRModelType.generic;
  }

  /// Configure audio parameters based on model type
  void _configureAudioParameters() {
    switch (_modelType) {
      case ASRModelType.whisper:
        _sampleRate = 16000;
        _nMels = 80;
        _nFFT = 400;
        _hopLength = 160;
        break;
      case ASRModelType.wav2vec2:
        _sampleRate = 16000;
        break;
      case ASRModelType.deepspeech:
        _sampleRate = 16000;
        _nMels = 26; // MFCC features
        break;
      default:
        _sampleRate = 16000;
        _nMels = 40;
    }
  }

  /// Load vocabulary from file
  Future<void> _loadVocabulary(String modelPath) async {
    final vocabPath = modelPath.replaceAll('.tflite', '_vocab.json');
    final vocabFile = File(vocabPath);

    if (await vocabFile.exists()) {
      try {
        final vocabJson = await vocabFile.readAsString();
        final vocabData = json.decode(vocabJson) as Map<String, dynamic>;
        _vocabulary = vocabData.map(
          (k, v) => MapEntry(int.parse(k), v as String),
        );
        print('📚 Loaded vocabulary with ${_vocabulary!.length} tokens');
      } catch (e) {
        print('⚠️ Failed to load vocabulary: $e');
        _createDefaultVocabulary();
      }
    } else {
      _createDefaultVocabulary();
    }
  }

  /// Create default vocabulary
  void _createDefaultVocabulary() {
    _vocabulary = {};

    // Add basic characters
    _vocabulary![0] = '<blank>';
    _vocabulary![1] = '<pad>';

    // Add letters
    for (int i = 0; i < 26; i++) {
      _vocabulary![i + 2] = String.fromCharCode(97 + i); // a-z
    }

    // Add space and punctuation
    _vocabulary![28] = ' ';
    _vocabulary![29] = "'";
    _vocabulary![30] = '.';
    _vocabulary![31] = ',';

    print('📚 Created default vocabulary with ${_vocabulary!.length} tokens');
  }

  // Implement required abstract methods
  @override
  Stream<String> generateText(String prompt, GenerationParams params) async* {
    throw UnimplementedError('ASR models do not support text generation');
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    throw UnimplementedError('ASR models do not support text embeddings');
  }

  @override
  Future<void> unloadModel() async {
    if (_interpreter != null) {
      _interpreter!.close();
      _interpreter = null;
    }
    _isModelLoaded = false;
    _currentModelPath = null;
    _modelType = null;
    _vocabulary = null;
    _inputShape = null;
    _outputShape = null;

    print('🎤 TFLite ASR model unloaded');
  }

  @override
  bool get isModelLoaded => _isModelLoaded;

  ASRModelType? get modelType => _modelType;
  String? get currentModelPath => _currentModelPath;
}

// Supporting enums and classes
enum ASRModelType { whisper, wav2vec2, deepspeech, speechRecognition, generic }

enum AudioFormat { pcm16, pcm32, float32 }
