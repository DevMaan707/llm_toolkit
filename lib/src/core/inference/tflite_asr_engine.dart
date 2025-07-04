import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fftea/fftea.dart';
import 'package:flutter/foundation.dart';
import '../config.dart';
import 'base_inference_engine.dart';
import '../../exceptions/llm_toolkit_exceptions.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class TFLiteASREngine extends BaseInferenceEngine {
  // Core TFLite components
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  String? _currentModelPath;
  ASRModelType? _modelType;
  Map<int, String>? _vocabulary;
  List<int>? _inputShape;
  List<int>? _outputShape;

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isStreamingMode = false;

  // Audio preprocessing parameters (optimized for Whisper)
  static const int SAMPLE_RATE = 16000;
  static const int N_MELS = 80;
  static const int N_FFT = 400;
  static const int HOP_LENGTH = 160;
  static const int N_FRAMES = 3000;
  static const int MAX_AUDIO_LENGTH = 480000;
  static const double LOG_EPSILON = 1e-10;
  static const double SILENCE_VALUE = -11.512925;

  final List<double> _audioBuffer = [];
  static const int CHUNK_SIZE = 8000;
  static const int OVERLAP_SIZE = 1600;

  // Pre-computed components for performance
  late FFT _fft;
  late List<List<double>> _melFilterBank;
  late List<double> _hanningWindow;
  bool _componentsInitialized = false;

  // Model-specific configurations
  late ModelConfig _modelConfig;
  static const int MIN_FRAMES = 100;
  static const int SHORT_AUDIO_THRESHOLD = 5 * SAMPLE_RATE;
  static const double SILENCE_THRESHOLD = 0.01;
  static const int MIN_CHUNK_SIZE = 32000;
  // Performance monitoring
  final Map<String, int> _performanceMetrics = {
    'totalInferences': 0,
    'totalPreprocessingTime': 0,
    'totalInferenceTime': 0,
    'totalPostprocessingTime': 0,
  };

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    if (_interpreter != null) {
      await unloadModel();
    }

    final stopwatch = Stopwatch()..start();

    try {
      print('🎤 Loading TFLite ASR model: $modelPath');

      // Validate model file
      await _validateModelFile(modelPath);

      // Load the TFLite model with optimizations
      final options =
          InterpreterOptions()
            ..threads = math.min(4, Platform.numberOfProcessors);

      _interpreter = await Interpreter.fromFile(
        File(modelPath),
        options: options,
      );

      // Analyze model structure
      await _analyzeModelStructure();

      // Detect model type and configure
      _modelType = _detectASRModelType(modelPath);
      _configureModelSpecificSettings();

      // Initialize audio processing components
      await _initializeAudioProcessing();

      // Load vocabulary if available
      await _loadVocabulary();

      // Validate model compatibility
      await _validateModelCompatibility();

      _isModelLoaded = true;
      _currentModelPath = modelPath;

      stopwatch.stop();
      print(
        '✅ TFLite ASR model loaded successfully in ${stopwatch.elapsedMilliseconds}ms',
      );
      print('   Model Type: ${_modelType?.name}');
      print('   Input Shape: $_inputShape');
      print('   Output Shape: $_outputShape');
      print('   Sample Rate: $SAMPLE_RATE Hz');
      print('   Vocabulary Size: ${_vocabulary?.length ?? 0}');
    } catch (e, stackTrace) {
      await unloadModel();
      print('❌ Failed to load TFLite ASR model: $e');
      print('Stack trace: $stackTrace');
      throw InferenceException('Failed to load TFLite ASR model: $e');
    }
  }

  /// Validate model file before loading
  Future<void> _validateModelFile(String modelPath) async {
    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      throw InferenceException('Model file not found: $modelPath');
    }

    final fileSize = await modelFile.length();
    print(
      '   Model file size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB',
    );

    if (fileSize < 1024 * 1024) {
      // Less than 1MB
      throw InferenceException(
        'Model file appears to be too small: ${fileSize} bytes',
      );
    }

    if (fileSize > 500 * 1024 * 1024) {
      // Greater than 500MB
      print(
        '⚠️ Warning: Large model file detected (${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB)',
      );
    }

    // Validate TFLite magic number
    try {
      final bytes = await modelFile.openRead(0, 8).first;
      if (bytes.length >= 8) {
        final magic = String.fromCharCodes(bytes.take(8));
        if (!magic.contains('TFL3') && !magic.contains('TFLM')) {
          print('⚠️ Warning: File may not be a valid TFLite model');
        }
      }
    } catch (e) {
      print('⚠️ Warning: Could not validate model file format: $e');
    }
  }

  /// Initialize audio processing components for maximum performance
  Future<void> _initializeAudioProcessing() async {
    try {
      print('🔧 Initializing audio processing components...');

      // Initialize FFT for fast processing
      _fft = FFT(N_FFT);

      // Pre-compute mel filter bank
      _melFilterBank = await compute(_createWhisperMelFilterBankIsolate, {
        'nFft': N_FFT ~/ 2 + 1,
        'nMels': N_MELS,
        'sampleRate': SAMPLE_RATE.toDouble(),
      });

      // Pre-compute Hanning window
      _hanningWindow = _createHanningWindow(N_FFT);

      _componentsInitialized = true;
      print('✅ Audio processing components initialized');
    } catch (e) {
      throw InferenceException('Failed to initialize audio processing: $e');
    }
  }

  Future<String> transcribeAudio(
    Uint8List audioData, {
    int sampleRate = SAMPLE_RATE,
    AudioFormat format = AudioFormat.wav,
    bool isMonoChannel = true,
    bool useEnhancedPreprocessing = true,
  }) async {
    if (!_isModelLoaded || _interpreter == null) {
      throw InferenceException('TFLite ASR model not loaded');
    }

    final totalStopwatch = Stopwatch()..start();

    try {
      print('🎤 Starting enhanced audio transcription...');
      print('   Audio size: ${audioData.length} bytes');
      print('   Sample rate: $sampleRate Hz');
      print('   Format: ${format.name}');

      // Convert audio data to float samples
      final audioSamples = await convertAudioToSamples(audioData, format);
      print('   Converted to ${audioSamples.length} samples');

      if (audioSamples.isEmpty) {
        return 'No audio data detected';
      }

      // Check audio duration and characteristics
      final durationSeconds = audioSamples.length / sampleRate;
      print('   Duration: ${durationSeconds.toStringAsFixed(2)}s');

      // For very short audio, use enhanced preprocessing
      if (durationSeconds < 2.0 && useEnhancedPreprocessing) {
        print('   Using enhanced preprocessing for short audio');
      }

      // Resample if necessary
      final resampledAudio =
          sampleRate != SAMPLE_RATE
              ? await compute(_resampleAudioIsolate, {
                'audio': audioSamples,
                'fromRate': sampleRate,
                'toRate': SAMPLE_RATE,
              })
              : audioSamples;

      // Use enhanced preprocessing
      final processedInput = await compute(
        _preprocessAudioForWhisperIsolate,
        resampledAudio,
      );

      // Run inference
      final output = await _runInference(processedInput);

      // Post-process output
      final transcription = await _postprocessOutput(output);

      totalStopwatch.stop();
      print(
        '✅ Enhanced transcription complete in ${totalStopwatch.elapsedMilliseconds}ms',
      );
      print(
        '   Result: "${transcription.substring(0, math.min(100, transcription.length))}"',
      );

      return transcription;
    } catch (e, stackTrace) {
      print('❌ Enhanced transcription error: $e');
      print('Stack trace: $stackTrace');
      throw InferenceException('Enhanced audio transcription failed: $e');
    }
  }

  static List<double> _preprocessAudioForWhisperIsolate(
    List<double> audioSamples,
  ) {
    print('🎤 Enhanced Whisper preprocessing:');
    print('   Input samples: ${audioSamples.length}');
    try {
      final silenceInfo = _detectSilence(audioSamples);
      print('   Silence detection: ${silenceInfo['percentage']}% silence');

      if (silenceInfo['percentage'] > 90.0) {
        print('⚠️ Audio is mostly silence, using minimal processing');
        return _processShortAudio(audioSamples);
      }
      final int nFrames =
          ((audioSamples.length - N_FFT) / HOP_LENGTH).floor() + 1;
      final int minTargetLength = (nFrames - 1) * HOP_LENGTH + N_FFT;
      final int targetLength = _calculateOptimalLength(
        audioSamples.length,
        minTargetLength,
      );

      List<double> paddedAudio = List.from(audioSamples);
      while (paddedAudio.length < targetLength) {
        paddedAudio.add(0.0);
      }
      print(
        '   Adaptive padding: ${audioSamples.length} → ${paddedAudio.length} samples',
      );
      print('   Target frames: $nFrames');
      final stft = _computeAdaptiveSTFT(paddedAudio, nFrames);
      print('   STFT frames: ${stft.length}');
      final melFilters = _createWhisperMelFilterBankIsolate({
        'nFft': N_FFT ~/ 2 + 1,
        'nMels': N_MELS,
        'sampleRate': SAMPLE_RATE.toDouble(),
      });

      final melSpectrogram = _applyMelFiltersIsolate(stft, melFilters);
      print('   Mel spectrogram: ${melSpectrogram.length} frames');
      return _createAdaptiveOutput(melSpectrogram, nFrames);
    } catch (e, stackTrace) {
      print('❌ Enhanced preprocessing error: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Enhanced preprocessing failed: $e');
    }
  }

  static int _calculateOptimalLength(int actualLength, int minLength) {
    if (actualLength < SAMPLE_RATE * 5) {
      final frames = ((actualLength - N_FFT) / HOP_LENGTH).floor() + 1;
      return math.max(minLength, frames * HOP_LENGTH + N_FFT);
    }
    if (actualLength < SAMPLE_RATE * 15) {
      return math.max(minLength, (actualLength * 1.1).round());
    }
    return math.min(SAMPLE_RATE * 20, math.max(minLength, actualLength));
  }

  static Map<String, dynamic> _detectSilence(List<double> audio) {
    if (audio.isEmpty) return {'percentage': 100.0, 'threshold': 0.01};

    const double silenceThreshold = 0.015; // Slightly higher threshold
    const int windowSize = 1600; // 100ms windows at 16kHz

    int silentWindows = 0;
    int totalWindows = (audio.length / windowSize).floor();

    for (int i = 0; i < totalWindows; i++) {
      final start = i * windowSize;
      final end = math.min(start + windowSize, audio.length);
      final window = audio.sublist(start, end);

      // Calculate RMS for window
      double rms = 0.0;
      for (final sample in window) {
        rms += sample * sample;
      }
      rms = math.sqrt(rms / window.length);

      if (rms < silenceThreshold) {
        silentWindows++;
      }
    }

    final percentage =
        totalWindows > 0 ? (silentWindows / totalWindows) * 100 : 100.0;

    return {
      'percentage': percentage,
      'threshold': silenceThreshold,
      'silentWindows': silentWindows,
      'totalWindows': totalWindows,
      'recommendedAction': percentage > 80 ? 'skip' : 'process',
    };
  }

  static List<double> _processShortAudio(List<double> audioSamples) {
    print('🔧 Processing short/silent audio with minimal context');
    const int shortContextFrames = 500;
    const int shortContextSize = N_MELS * shortContextFrames;
    final paddedAudio = List<double>.from(audioSamples);
    final minLength = N_FFT + HOP_LENGTH * 10;

    while (paddedAudio.length < minLength) {
      paddedAudio.add(0.0);
    }

    final stft = _computeSTFTWithFftea(paddedAudio);
    final melFilters = _createWhisperMelFilterBankIsolate({
      'nFft': N_FFT ~/ 2 + 1,
      'nMels': N_MELS,
      'sampleRate': SAMPLE_RATE.toDouble(),
    });

    final melSpectrogram = _applyMelFiltersIsolate(stft, melFilters);
    final flattened = <double>[];
    for (int frame = 0; frame < shortContextFrames; frame++) {
      for (int mel = 0; mel < N_MELS; mel++) {
        if (frame < melSpectrogram.length &&
            mel < melSpectrogram[frame].length) {
          flattened.add(melSpectrogram[frame][mel]);
        } else {
          flattened.add(SILENCE_VALUE);
        }
      }
    }
    while (flattened.length < N_MELS * N_FRAMES) {
      flattened.add(SILENCE_VALUE);
    }

    return flattened.take(N_MELS * N_FRAMES).toList();
  }

  /// Compute STFT with adaptive frame count
  static List<List<double>> _computeAdaptiveSTFT(
    List<double> audio,
    int targetFrames,
  ) {
    final fft = FFT(N_FFT);
    final stftFrames = <List<double>>[];
    final hanningWindow = _createHanningWindowIsolate(N_FFT);

    // Calculate actual frames we can extract
    final maxFrames = ((audio.length - N_FFT) / HOP_LENGTH).floor() + 1;
    final framesToProcess = math.min(targetFrames, maxFrames);

    for (int frame = 0; frame < framesToProcess; frame++) {
      final start = frame * HOP_LENGTH;
      final end = math.min(start + N_FFT, audio.length);

      List<double> window = audio.sublist(start, end);

      if (window.length < N_FFT) {
        window.addAll(List.filled(N_FFT - window.length, 0.0));
      }

      final windowed = <double>[];
      for (int i = 0; i < N_FFT; i++) {
        windowed.add(window[i] * hanningWindow[i]);
      }

      try {
        final complexResult = fft.realFft(windowed);
        final magnitude = <double>[];
        for (final complex in complexResult) {
          final real = complex.x;
          final imag = complex.y;
          magnitude.add(math.sqrt(real * real + imag * imag));
        }
        stftFrames.add(magnitude);
      } catch (e) {
        print('FFT error at frame $frame: $e');
        stftFrames.add(List.filled(N_FFT ~/ 2 + 1, 0.0));
      }
    }

    return stftFrames;
  }

  /// Create adaptive output based on actual audio length
  static List<double> _createAdaptiveOutput(
    List<List<double>> melSpectrogram,
    int actualFrames,
  ) {
    // For shorter audio, use less aggressive padding
    final effectiveFrames = math.min(
      N_FRAMES,
      math.max(actualFrames, melSpectrogram.length),
    );

    final flattened = <double>[];

    // Fill with actual data first
    for (int frame = 0; frame < effectiveFrames; frame++) {
      for (int mel = 0; mel < N_MELS; mel++) {
        if (frame < melSpectrogram.length &&
            mel < melSpectrogram[frame].length) {
          flattened.add(melSpectrogram[frame][mel]);
        } else {
          flattened.add(SILENCE_VALUE);
        }
      }
    }

    // Pad remaining to full model input size
    while (flattened.length < N_MELS * N_FRAMES) {
      flattened.add(SILENCE_VALUE);
    }

    print('   Adaptive output: ${flattened.length} elements');
    return flattened;
  }

  Future<String> transcribeAudioChunked(
    Uint8List audioData, {
    int sampleRate = SAMPLE_RATE,
    AudioFormat format = AudioFormat.wav,
    bool useChunking = true,
  }) async {
    if (!_isModelLoaded || _interpreter == null) {
      throw InferenceException('TFLite ASR model not loaded');
    }

    try {
      print('🎤 Starting enhanced chunked transcription...');

      final audioSamples = await convertAudioToSamples(audioData, format);
      final durationSeconds = audioSamples.length / sampleRate;

      print('   Audio duration: ${durationSeconds.toStringAsFixed(2)}s');

      if (!useChunking || durationSeconds < 6.0) {
        print('   Using direct inference for short audio');
        return await transcribeAudio(
          audioData,
          sampleRate: sampleRate,
          format: format,
        );
      }

      // Enhanced chunking parameters
      const chunkDuration = 10.0; // 10 second chunks
      const overlapDuration = 2.0; // 2 second overlap

      final chunkSize = (chunkDuration * sampleRate).round();
      final overlapSize = (overlapDuration * sampleRate).round();
      final stepSize = chunkSize - overlapSize;

      final transcriptions = <String>[];
      final processedWords = <String>{};

      for (int start = 0; start < audioSamples.length; start += stepSize) {
        final end = math.min(start + chunkSize, audioSamples.length);
        final chunk = audioSamples.sublist(start, end);

        // Skip chunks that are too short
        if (chunk.length < sampleRate * 3) continue; // Minimum 3 seconds

        print(
          '   Processing chunk: ${start ~/ sampleRate}s - ${end ~/ sampleRate}s',
        );

        try {
          final chunkBytes = await _samplesToWavBytes(chunk, sampleRate);
          final chunkTranscription = await transcribeAudio(
            chunkBytes,
            sampleRate: sampleRate,
            format: AudioFormat.wav,
          );

          if (isValidTranscription(chunkTranscription)) {
            // Remove duplicate words from overlap
            final words = chunkTranscription.split(' ');
            final newWords =
                words.where((word) => !processedWords.contains(word)).toList();

            if (newWords.isNotEmpty) {
              transcriptions.add(newWords.join(' '));
              processedWords.addAll(newWords);
            }
          }
        } catch (e) {
          print('   Chunk processing error: $e');
          continue;
        }
      }

      final result = transcriptions.join(' ').trim();
      print('✅ Enhanced chunked transcription complete');

      return result.isEmpty ? 'No speech detected' : result;
    } catch (e) {
      throw InferenceException('Enhanced chunked transcription failed: $e');
    }
  }

  Future<Uint8List> _samplesToWavBytes(
    List<double> samples,
    int sampleRate,
  ) async {
    final byteData = ByteData(44 + samples.length * 2);

    // WAV header
    byteData.setUint32(0, 0x52494646, Endian.little); // 'RIFF'
    byteData.setUint32(4, 36 + samples.length * 2, Endian.little);
    byteData.setUint32(8, 0x57415645, Endian.little); // 'WAVE'
    byteData.setUint32(12, 0x666D7420, Endian.little); // 'fmt '
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, 1, Endian.little); // Mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    byteData.setUint32(36, 0x64617461, Endian.little); // 'data'
    byteData.setUint32(40, samples.length * 2, Endian.little);

    // Audio data
    for (int i = 0; i < samples.length; i++) {
      final sample = (samples[i] * 32767).round().clamp(-32768, 32767);
      byteData.setInt16(44 + i * 2, sample, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  static List<List<double>> _computeSTFTWithFftea(List<double> audio) {
    final fft = FFT(N_FFT);
    final stftFrames = <List<double>>[];
    final hanningWindow = _createHanningWindowIsolate(N_FFT);

    final numFrames = ((audio.length - N_FFT) / HOP_LENGTH).floor() + 1;

    for (int frame = 0; frame < numFrames; frame++) {
      final start = frame * HOP_LENGTH;
      final end = math.min(start + N_FFT, audio.length);

      // Extract window
      List<double> window = audio.sublist(start, end);

      // Pad with zeros if necessary
      if (window.length < N_FFT) {
        window.addAll(List.filled(N_FFT - window.length, 0.0));
      }

      // Apply Hanning window
      final windowed = <double>[];
      for (int i = 0; i < N_FFT; i++) {
        windowed.add(window[i] * hanningWindow[i]);
      }

      // Compute FFT using fftea
      try {
        final complexResult = fft.realFft(windowed);

        // Convert to magnitude spectrum
        final magnitude = <double>[];
        for (final complex in complexResult) {
          final real = complex.x; // Real part
          final imag = complex.y; // Imaginary part
          magnitude.add(math.sqrt(real * real + imag * imag));
        }

        stftFrames.add(magnitude);
      } catch (e) {
        print('FFT error at frame $frame: $e');
        // Add zero magnitude frame as fallback
        stftFrames.add(List.filled(N_FFT ~/ 2 + 1, 0.0));
      }
    }

    return stftFrames;
  }

  /// Create Hanning window for isolate processing
  static List<double> _createHanningWindowIsolate(int size) {
    final window = <double>[];
    for (int i = 0; i < size; i++) {
      window.add(0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1)));
    }
    return window;
  }

  /// Create Hanning window (instance method)
  List<double> _createHanningWindow(int size) {
    return _createHanningWindowIsolate(size);
  }

  /// Apply mel filters to STFT in isolate
  static List<List<double>> _applyMelFiltersIsolate(
    List<List<double>> stft,
    List<List<double>> melFilters,
  ) {
    final melSpectrogram = <List<double>>[];

    for (final frame in stft) {
      final melFrame = <double>[];
      for (int i = 0; i < melFilters.length; i++) {
        double melValue = 0.0;
        for (int j = 0; j < frame.length && j < melFilters[i].length; j++) {
          melValue += frame[j] * melFilters[i][j];
        }
        melFrame.add(math.log(math.max(melValue, LOG_EPSILON)));
      }
      melSpectrogram.add(melFrame);
    }

    return melSpectrogram;
  }

  /// Create Whisper-compatible mel filter bank in isolate
  static List<List<double>> _createWhisperMelFilterBankIsolate(
    Map<String, dynamic> params,
  ) {
    final int nFft = params['nFft'];
    final int nMels = params['nMels'];
    final double sampleRate = params['sampleRate'];

    double hzToMel(double hz) =>
        2595.0 * (math.log(1.0 + hz / 700.0) / math.ln10);
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

      for (int j = left; j < center && j < nFft; j++) {
        if (center > left) {
          filter[j] = (j - left) / (center - left);
        }
      }

      for (int j = center; j < right && j < nFft; j++) {
        if (right > center) {
          filter[j] = (right - j) / (right - center);
        }
      }

      filterBank.add(filter);
    }

    return filterBank;
  }

  /// Ensure mel spectrogram has correct dimensions in isolate
  static List<List<double>> _ensureCorrectMelDimensionsIsolate(
    List<List<double>> melSpectrogram,
    int targetMels,
    int targetFrames,
  ) {
    final corrected = <List<double>>[];

    for (int frame = 0; frame < targetFrames; frame++) {
      List<double> melFrame;

      if (frame < melSpectrogram.length) {
        melFrame = [...melSpectrogram[frame]];
      } else {
        melFrame = List.filled(targetMels, SILENCE_VALUE);
      }

      if (melFrame.length > targetMels) {
        melFrame = melFrame.sublist(0, targetMels);
      } else if (melFrame.length < targetMels) {
        melFrame.addAll(
          List.filled(targetMels - melFrame.length, SILENCE_VALUE),
        );
      }

      corrected.add(melFrame);
    }

    return corrected;
  }

  /// High-quality audio resampling in isolate
  static List<double> _resampleAudioIsolate(Map<String, dynamic> params) {
    final List<double> audio = params['audio'];
    final int fromRate = params['fromRate'];
    final int toRate = params['toRate'];

    if (fromRate == toRate) return audio;

    final ratio = fromRate / toRate;
    final newLength = (audio.length / ratio).round();
    final resampled = <double>[];

    for (int i = 0; i < newLength; i++) {
      final sourceIndex = i * ratio;
      final index1 = sourceIndex.floor();
      final index2 = math.min(index1 + 1, audio.length - 1);
      final fraction = sourceIndex - index1;

      if (index1 < audio.length) {
        final sample1 = audio[index1];
        final sample2 = audio[index2];
        final interpolated = sample1 + (sample2 - sample1) * fraction;
        resampled.add(interpolated);
      }
    }

    return resampled;
  }

  Future<List<double>> convertAudioToSamples(
    Uint8List audioData,
    AudioFormat format,
  ) async {
    try {
      switch (format) {
        case AudioFormat.wav:
          return await _convertWAVToSamples(audioData);
        case AudioFormat.pcm16:
          return _convertPCM16ToSamples(audioData);
        case AudioFormat.pcm32:
          return _convertPCM32ToSamples(audioData);
        case AudioFormat.float32:
          return _convertFloat32ToSamples(audioData);
        default:
          throw InferenceException('Unsupported audio format: ${format.name}');
      }
    } catch (e) {
      throw InferenceException(
        'Failed to convert audio format ${format.name}: $e',
      );
    }
  }

  /// Convert WAV file to samples with proper header parsing
  Future<List<double>> _convertWAVToSamples(Uint8List audioData) async {
    if (audioData.length < 44) {
      throw InferenceException(
        'Invalid WAV file: too small (${audioData.length} bytes)',
      );
    }

    try {
      final header = await _parseWAVHeader(audioData);
      print(
        '   WAV Info: ${header['channels']} channels, ${header['sampleRate']} Hz, ${header['bitsPerSample']} bits',
      );

      final pcmData = audioData.sublist(header['dataOffset'] ?? 44);

      if (header['bitsPerSample'] == 16) {
        return _convertPCM16ToSamples(pcmData, header['channels'] ?? 1);
      } else if (header['bitsPerSample'] == 32) {
        return _convertPCM32ToSamples(pcmData, header['channels'] ?? 1);
      } else {
        throw InferenceException(
          'Unsupported WAV bit depth: ${header['bitsPerSample']}',
        );
      }
    } catch (e) {
      throw InferenceException('Failed to parse WAV file: $e');
    }
  }

  /// Parse WAV header with comprehensive validation
  Future<Map<String, int>> _parseWAVHeader(Uint8List data) async {
    final byteData = ByteData.sublistView(data);

    // Check RIFF header
    final riff = String.fromCharCodes(data.sublist(0, 4));
    if (riff != 'RIFF') {
      throw InferenceException(
        'Invalid WAV file: missing RIFF header (found: $riff)',
      );
    }

    // Check file size
    final fileSize = byteData.getUint32(4, Endian.little);
    if (fileSize + 8 != data.length) {
      print(
        '⚠️ Warning: WAV file size mismatch (header: ${fileSize + 8}, actual: ${data.length})',
      );
    }

    // Check WAVE format
    final wave = String.fromCharCodes(data.sublist(8, 12));
    if (wave != 'WAVE') {
      throw InferenceException(
        'Invalid WAV file: not WAVE format (found: $wave)',
      );
    }

    // Find fmt chunk
    int offset = 12;
    Map<String, int>? fmtData;

    while (offset < data.length - 8) {
      final chunkId = String.fromCharCodes(data.sublist(offset, offset + 4));
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          throw InferenceException('Invalid fmt chunk size: $chunkSize');
        }

        final audioFormat = byteData.getUint16(offset + 8, Endian.little);
        if (audioFormat != 1) {
          // PCM
          throw InferenceException(
            'Unsupported audio format: $audioFormat (only PCM supported)',
          );
        }

        fmtData = {
          'channels': byteData.getUint16(offset + 10, Endian.little),
          'sampleRate': byteData.getUint32(offset + 12, Endian.little),
          'bitsPerSample': byteData.getUint16(offset + 22, Endian.little),
        };

        offset += 8 + chunkSize;
        break;
      } else {
        offset += 8 + chunkSize;
      }
    }

    if (fmtData == null) {
      throw InferenceException('WAV file missing fmt chunk');
    }

    // Find data chunk
    while (offset < data.length - 8) {
      final chunkId = String.fromCharCodes(data.sublist(offset, offset + 4));
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);

      if (chunkId == 'data') {
        fmtData['dataOffset'] = offset + 8;
        fmtData['dataSize'] = chunkSize;
        break;
      }

      offset += 8 + chunkSize;
    }

    if (!fmtData.containsKey('dataOffset')) {
      throw InferenceException('WAV file missing data chunk');
    }

    return fmtData;
  }

  /// Convert PCM16 to normalized float samples
  List<double> _convertPCM16ToSamples(Uint8List pcmData, [int channels = 1]) {
    final samples = <double>[];
    final bytesPerSample = 2 * channels;

    for (
      int i = 0;
      i < pcmData.length - (bytesPerSample - 1);
      i += bytesPerSample
    ) {
      if (channels == 1) {
        final sample = (pcmData[i] | (pcmData[i + 1] << 8));
        final signed = sample > 32767 ? sample - 65536 : sample;
        samples.add(signed / 32768.0);
      } else {
        // Convert stereo to mono by averaging channels
        final left = (pcmData[i] | (pcmData[i + 1] << 8));
        final right = (pcmData[i + 2] | (pcmData[i + 3] << 8));

        final leftSigned = left > 32767 ? left - 65536 : left;
        final rightSigned = right > 32767 ? right - 65536 : right;

        samples.add((leftSigned + rightSigned) / (2.0 * 32768.0));
      }
    }

    return samples;
  }

  /// Convert PCM32 to normalized float samples
  List<double> _convertPCM32ToSamples(Uint8List pcmData, [int channels = 1]) {
    final samples = <double>[];
    final byteData = ByteData.sublistView(pcmData);
    final bytesPerSample = 4 * channels;

    for (
      int i = 0;
      i < pcmData.length - (bytesPerSample - 1);
      i += bytesPerSample
    ) {
      if (channels == 1) {
        final sample = byteData.getInt32(i, Endian.little);
        samples.add(sample / 2147483648.0);
      } else {
        final left = byteData.getInt32(i, Endian.little);
        final right = byteData.getInt32(i + 4, Endian.little);
        samples.add((left + right) / (2.0 * 2147483648.0));
      }
    }

    return samples;
  }

  /// Convert Float32 samples
  List<double> _convertFloat32ToSamples(Uint8List audioData) {
    final samples = <double>[];
    final byteData = ByteData.sublistView(audioData);

    for (int i = 0; i < audioData.length - 3; i += 4) {
      samples.add(byteData.getFloat32(i, Endian.little));
    }

    return samples;
  }

  /// Run inference with proper error handling and tensor management
  Future<List> _runInference(List<double> input) async {
    try {
      if (_interpreter == null) {
        throw InferenceException('Interpreter not initialized');
      }

      // Validate input size matches expected model input
      final expectedInputSize = _inputShape!.reduce((a, b) => a * b);
      if (input.length != expectedInputSize) {
        throw InferenceException(
          'Input size mismatch: expected $expectedInputSize, got ${input.length}. '
          'Expected shape: $_inputShape',
        );
      }

      // Prepare input tensor with correct shape
      final inputTensor = input.reshape(_inputShape!);

      // Prepare output tensor with correct shape
      final outputShape = _outputShape!;
      final outputSize = outputShape.reduce((a, b) => a * b);

      // Create properly shaped output tensor
      List output;
      if (outputShape.length == 2) {
        output = List.generate(
          outputShape[0],
          (_) => List.filled(outputShape[1], 0.0),
        );
      } else {
        output = List.filled(outputSize, 0.0).reshape(outputShape);
      }

      print('🔧 Running inference with:');
      print('   Input shape: $_inputShape (${input.length} elements)');
      print('   Output shape: $_outputShape (${outputSize} elements)');

      // Run inference with comprehensive error handling
      try {
        _interpreter!.run(inputTensor, output);
        print('✅ Inference completed successfully');
      } catch (e) {
        final errorMessage = e.toString().toLowerCase();

        if (errorMessage.contains('gather index out of bounds')) {
          throw InferenceException(
            'Model input/output shape mismatch. Expected input shape: $_inputShape, '
            'provided: ${inputTensor.shape}. This usually indicates incompatible model or preprocessing. '
            'Error: $e',
          );
        } else if (errorMessage.contains('failed precondition') ||
            errorMessage.contains('bad state')) {
          throw InferenceException(
            'Model execution failed due to tensor shape or data type mismatch. '
            'Input shape: $_inputShape, Output shape: $_outputShape. '
            'Ensure your model expects float32 input and the preprocessing matches the model requirements. '
            'Error: $e',
          );
        } else if (errorMessage.contains('invalid argument')) {
          throw InferenceException(
            'Invalid tensor data provided to model. Check input data format and range. '
            'Error: $e',
          );
        } else {
          throw InferenceException('Inference execution failed: $e');
        }
      }

      return output;
    } catch (e) {
      print('❌ Inference error: $e');
      throw InferenceException('Inference failed: $e');
    }
  }

  /// Post-process model output to text with comprehensive decoding
  Future<String> _postprocessOutput(List output) async {
    try {
      if (output.isEmpty) {
        return 'No output from model';
      }

      final logits = output[0];
      if (logits is! List) {
        return 'Invalid output format: expected List, got ${logits.runtimeType}';
      }

      // Decode based on model type
      switch (_modelType) {
        case ASRModelType.whisper:
          return await _decodeWhisperOutput(logits);
        case ASRModelType.wav2vec2:
          return await _decodeWav2Vec2Output(logits);
        case ASRModelType.deepspeech:
          return await _decodeDeepSpeechOutput(logits);
        default:
          return await _decodeGenericOutput(logits);
      }
    } catch (e, stackTrace) {
      print('❌ Output decoding error: $e');
      print('Stack trace: $stackTrace');
      return 'Error decoding output: $e';
    }
  }

  /// Decode Whisper model output with proper token handling - COMPLETELY FIXED
  Future<String> _decodeWhisperOutput(dynamic logits) async {
    try {
      final tokenIds = <int>[];

      if (logits is List<List>) {
        // Sequence of logits - take argmax for each timestep
        for (final timestepLogits in logits) {
          List<double> doubleLogits;
          if (timestepLogits is List<double>) {
            doubleLogits = timestepLogits;
          } else if (timestepLogits is List<num>) {
            doubleLogits = timestepLogits.map((e) => e.toDouble()).toList();
          } else if (timestepLogits is List<int>) {
            doubleLogits = timestepLogits.map((e) => e.toDouble()).toList();
          } else {
            // Handle dynamic list
            doubleLogits =
                (timestepLogits as List)
                    .map((e) => (e as num).toDouble())
                    .toList();
          }
          final maxIndex = _argmax(doubleLogits);
          tokenIds.add(maxIndex);
        }
      } else if (logits is List<double>) {
        // Single sequence - decode greedily
        final doubleLogits = logits;
        final vocabSize = _vocabulary?.length ?? 51865; // Whisper vocab size

        for (int i = 0; i < doubleLogits.length; i += vocabSize) {
          final slice = doubleLogits.sublist(
            i,
            math.min(i + vocabSize, doubleLogits.length),
          );
          final maxIndex = _argmax(slice);
          tokenIds.add(maxIndex);
        }
      } else if (logits is List<num>) {
        // Handle List<num>
        final doubleLogits = logits.map((e) => e.toDouble()).toList();
        final vocabSize = _vocabulary?.length ?? 51865;

        for (int i = 0; i < doubleLogits.length; i += vocabSize) {
          final slice = doubleLogits.sublist(
            i,
            math.min(i + vocabSize, doubleLogits.length),
          );
          final maxIndex = _argmax(slice);
          tokenIds.add(maxIndex);
        }
      } else if (logits is List<int>) {
        // Already token IDs
        tokenIds.addAll(logits);
      } else {
        // Handle dynamic list by converting to double
        final dynamicList = logits as List;
        final doubleLogits = <double>[];

        for (final item in dynamicList) {
          if (item is num) {
            doubleLogits.add(item.toDouble());
          } else {
            doubleLogits.add(0.0); // fallback for non-numeric values
          }
        }

        final vocabSize = _vocabulary?.length ?? 51865;

        for (int i = 0; i < doubleLogits.length; i += vocabSize) {
          final slice = doubleLogits.sublist(
            i,
            math.min(i + vocabSize, doubleLogits.length),
          );
          final maxIndex = _argmax(slice);
          tokenIds.add(maxIndex);
        }
      }

      print(
        '🔍 Decoded ${tokenIds.length} tokens: ${tokenIds.take(10).toList()}',
      );

      // Decode tokens to text
      return await _decodeTokens(tokenIds);
    } catch (e, stackTrace) {
      print('❌ Whisper decoding error: $e');
      print('Stack trace: $stackTrace');
      return 'Error decoding Whisper output: $e';
    }
  }

  /// Decode Wav2Vec2 output with CTC decoding - FIXED VERSION
  Future<String> _decodeWav2Vec2Output(dynamic logits) async {
    try {
      List<double> doubleLogits;

      if (logits is List<double>) {
        doubleLogits = logits;
      } else if (logits is List<num>) {
        doubleLogits = logits.map((e) => e.toDouble()).toList();
      } else if (logits is List<int>) {
        doubleLogits = logits.map((e) => e.toDouble()).toList();
      } else {
        // Handle dynamic list safely
        final dynamicList = logits as List;
        doubleLogits = <double>[];

        for (final item in dynamicList) {
          if (item is num) {
            doubleLogits.add(item.toDouble());
          } else {
            doubleLogits.add(0.0);
          }
        }
      }

      return await _performCTCDecoding(doubleLogits);
    } catch (e) {
      return 'Error decoding Wav2Vec2 output: $e';
    }
  }

  /// Decode DeepSpeech output - FIXED VERSION
  Future<String> _decodeDeepSpeechOutput(dynamic logits) async {
    try {
      List<double> doubleLogits;

      if (logits is List<double>) {
        doubleLogits = logits;
      } else if (logits is List<num>) {
        doubleLogits = logits.map((e) => e.toDouble()).toList();
      } else if (logits is List<int>) {
        doubleLogits = logits.map((e) => e.toDouble()).toList();
      } else {
        // Handle dynamic list safely
        final dynamicList = logits as List;
        doubleLogits = <double>[];

        for (final item in dynamicList) {
          if (item is num) {
            doubleLogits.add(item.toDouble());
          } else {
            doubleLogits.add(0.0);
          }
        }
      }

      return await _performCTCDecoding(doubleLogits);
    } catch (e) {
      return 'Error decoding DeepSpeech output: $e';
    }
  }

  /// Generic output decoding - FIXED VERSION
  Future<String> _decodeGenericOutput(dynamic logits) async {
    try {
      List<double> doubleLogits;

      if (logits is List<double>) {
        doubleLogits = logits;
      } else if (logits is List<num>) {
        doubleLogits = logits.map((e) => e.toDouble()).toList();
      } else if (logits is List<int>) {
        doubleLogits = logits.map((e) => e.toDouble()).toList();
      } else {
        // Handle dynamic list safely
        final dynamicList = logits as List;
        doubleLogits = <double>[];

        for (final item in dynamicList) {
          if (item is num) {
            doubleLogits.add(item.toDouble());
          } else {
            doubleLogits.add(0.0);
          }
        }
      }

      final maxIndex = _argmax(doubleLogits);
      final confidence = doubleLogits[maxIndex];

      if (_vocabulary != null && maxIndex < _vocabulary!.length) {
        final token = _vocabulary![maxIndex];
        return token ?? 'Unknown token $maxIndex';
      } else {
        return 'Detected class: $maxIndex (confidence: ${confidence.toStringAsFixed(3)})';
      }
    } catch (e) {
      return 'Error decoding generic output: $e';
    }
  }

  /// Perform CTC decoding with proper blank handling
  Future<String> _performCTCDecoding(List<double> logits) async {
    final chars = <String>[];
    String lastChar = '';
    const int numClasses = 29; // 26 letters + space + blank + apostrophe

    for (int i = 0; i < logits.length; i += numClasses) {
      final slice = logits.sublist(i, math.min(i + numClasses, logits.length));
      final maxIndex = _argmax(slice);

      String currentChar = '';
      if (maxIndex == 0) {
        currentChar = ''; // blank
      } else if (maxIndex == 27) {
        currentChar = ' ';
      } else if (maxIndex == 28) {
        currentChar = "'";
      } else if (maxIndex > 0 && maxIndex < 27) {
        currentChar = String.fromCharCode(96 + maxIndex);
      }

      // CTC rule: don't repeat consecutive characters
      if (currentChar.isNotEmpty && currentChar != lastChar) {
        chars.add(currentChar);
      }
      lastChar = currentChar;
    }

    return chars.join('').trim();
  }

  /// Find argmax of a list with NaN handling
  int _argmax(List<double> values) {
    if (values.isEmpty) return 0;

    int maxIndex = 0;
    double maxValue = values[0];

    for (int i = 1; i < values.length; i++) {
      if (!values[i].isNaN && !values[i].isInfinite && values[i] > maxValue) {
        maxValue = values[i];
        maxIndex = i;
      }
    }

    return maxIndex;
  }

  /// Decode token IDs to text using vocabulary with comprehensive filtering - ENHANCED
  Future<String> _decodeTokens(List<int> tokenIds) async {
    if (_vocabulary == null || _vocabulary!.isEmpty) {
      // For small vocabularies, try to interpret tokens directly
      if (tokenIds.isNotEmpty) {
        final words = <String>[];
        for (final tokenId in tokenIds) {
          if (tokenId > 0 && tokenId < 27) {
            // Convert to letters a-z
            words.add(String.fromCharCode(96 + tokenId));
          } else if (tokenId == 27) {
            words.add(' ');
          } else if (tokenId == 28) {
            words.add("'");
          }
        }
        final result = words.join('').trim();
        return result.isEmpty ? 'No speech detected' : result;
      }
      return 'Token IDs: ${tokenIds.take(20).join(', ')}${tokenIds.length > 20 ? '...' : ''}';
    }

    final words = <String>[];
    final specialTokens = {
      '<pad>',
      '<blank>',
      '<unk>',
      '<s>',
      '</s>',
      '<|startoftranscript|>',
      '<|endoftext|>',
      '<|notimestamps|>',
      '<|nospeech|>',
      '<|silence|>',
    };

    for (int tokenId in tokenIds) {
      if (tokenId >= 0 && tokenId < _vocabulary!.length) {
        final word = _vocabulary![tokenId];
        if (word != null && !specialTokens.contains(word.toLowerCase())) {
          // Clean up the word
          final cleanWord = word.trim();
          if (cleanWord.isNotEmpty) {
            words.add(cleanWord);
          }
        }
      }
    }

    final result = words.join(' ').trim();

    // Handle empty result
    if (result.isEmpty) {
      if (tokenIds.every(
        (id) =>
            id == 0 ||
            (id < _vocabulary!.length &&
                specialTokens.contains(_vocabulary![id]?.toLowerCase())),
      )) {
        return 'No speech detected';
      } else {
        return 'Unable to decode tokens: ${tokenIds.take(10).join(', ')}';
      }
    }

    return result;
  }

  /// Start recording audio with comprehensive error handling
  Future<void> startRecording({bool streamingMode = false}) async {
    if (_isRecording) {
      throw InferenceException('Already recording');
    }

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw InferenceException('Microphone permission not granted');
      }

      _isStreamingMode = streamingMode;
      _audioBuffer.clear();

      final tempDir = await getTemporaryDirectory();
      final audioPath =
          '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: SAMPLE_RATE,
          bitRate: 256000,
          numChannels: 1,
        ),
        path: audioPath,
      );

      _isRecording = true;
      print('🎤 Started recording (streaming: $_isStreamingMode)');
    } catch (e) {
      throw InferenceException('Failed to start recording: $e');
    }
  }

  /// Stop recording and get transcription
  Future<String> stopRecording() async {
    if (!_isRecording) {
      throw InferenceException('Not currently recording');
    }

    try {
      final audioPath = await _audioRecorder.stop();
      _isRecording = false;

      if (audioPath == null) {
        throw InferenceException('Failed to save audio recording');
      }

      print('🎤 Stopped recording, transcribing...');

      final audioFile = File(audioPath);
      final audioBytes = await audioFile.readAsBytes();

      final transcription = await transcribeAudio(
        audioBytes,
        format: AudioFormat.wav,
      );

      try {
        await audioFile.delete();
      } catch (e) {
        print('Warning: Failed to delete temp file: $e');
      }

      return transcription;
    } catch (e) {
      _isRecording = false;
      throw InferenceException('Failed to stop recording: $e');
    }
  }

  Stream<String> startStreamingTranscription() async* {
    if (!_isModelLoaded || _interpreter == null) {
      throw InferenceException('ASR model not loaded');
    }

    _isStreamingMode = true;
    _isRecording = true;

    try {
      // Check microphone permission
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw InferenceException('Microphone permission not granted');
      }

      print('🎤 Starting optimized streaming transcription...');

      final tempDir = await getTemporaryDirectory();
      const chunkDuration = Duration(
        milliseconds: 3000,
      ); // 3 second chunks for better accuracy

      while (_isStreamingMode && _isRecording) {
        final chunkPath =
            '${tempDir.path}/stream_${DateTime.now().millisecondsSinceEpoch}.wav';

        try {
          // Start recording chunk
          await _audioRecorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: SAMPLE_RATE,
              bitRate: 256000,
              numChannels: 1,
            ),
            path: chunkPath,
          );

          // Wait for chunk duration
          await Future.delayed(chunkDuration);

          if (!_isStreamingMode) break;

          // Stop and process chunk
          final recordedPath = await _audioRecorder.stop();

          if (recordedPath != null && _isStreamingMode) {
            final audioFile = File(recordedPath);

            if (await audioFile.exists()) {
              final audioBytes = await audioFile.readAsBytes();

              // Process chunk if it has sufficient data
              if (audioBytes.length > 16000) {
                // At least 16KB for 3 seconds
                try {
                  final transcription = await transcribeAudio(
                    audioBytes,
                    format: AudioFormat.wav,
                  );

                  // Emit if transcription is meaningful
                  if (isValidTranscription(transcription)) {
                    print('🎤 Streaming result: "$transcription"');
                    yield transcription;
                  }
                } catch (e) {
                  print('❌ Chunk processing error: $e');
                  // Continue streaming despite processing errors
                }
              }

              // Clean up
              try {
                await audioFile.delete();
              } catch (e) {
                print('Warning: Failed to delete chunk file: $e');
              }
            }
          }

          // Brief pause before next chunk
          if (_isStreamingMode) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        } catch (e) {
          print('❌ Streaming chunk error: $e');
          await Future.delayed(const Duration(milliseconds: 1000));
          continue;
        }
      }
    } catch (e) {
      _isStreamingMode = false;
      _isRecording = false;
      throw InferenceException('Streaming transcription failed: $e');
    } finally {
      _isStreamingMode = false;
      _isRecording = false;
      print('🎤 Streaming transcription ended');
    }
  }

  bool isValidTranscription(String transcription) {
    if (transcription.trim().isEmpty) return false;
    if (transcription.trim() == "...") return false;
    if (transcription.toLowerCase() == "no speech detected") return false;
    if (transcription.toLowerCase().contains("error")) return false;
    if (transcription.trim().length < 2) return false;

    // Check for common meaningless outputs
    final meaninglessPatterns = ["...", "   ", "null", "undefined", "unknown"];

    final lowerTranscription = transcription.toLowerCase().trim();
    for (final pattern in meaninglessPatterns) {
      if (lowerTranscription == pattern) return false;
    }

    return true;
  }

  Future<void> stopStreamingTranscription() async {
    print('🎤 Stopping streaming transcription...');

    _isStreamingMode = false;

    if (_isRecording) {
      try {
        await _audioRecorder.stop();
      } catch (e) {
        print('Warning: Error stopping recording: $e');
      }
      _isRecording = false;
    }

    print('✅ Streaming stopped');
  }

  Future<bool> testMicrophoneAccess() async {
    try {
      return await _audioRecorder.hasPermission();
    } catch (e) {
      print('❌ Microphone test failed: $e');
      return false;
    }
  }

  /// Transcribe audio file from path
  Future<String> transcribeFile(String audioFilePath) async {
    try {
      final audioFile = File(audioFilePath);
      if (!await audioFile.exists()) {
        throw InferenceException('Audio file not found: $audioFilePath');
      }

      final audioBytes = await audioFile.readAsBytes();
      final extension = audioFilePath.toLowerCase().split('.').last;

      AudioFormat format;
      switch (extension) {
        case 'wav':
          format = AudioFormat.wav;
          break;
        case 'pcm':
          format = AudioFormat.pcm16;
          break;
        default:
          format = AudioFormat.wav;
      }

      return await transcribeAudio(audioBytes, format: format);
    } catch (e) {
      throw InferenceException('Failed to transcribe file: $e');
    }
  }

  /// Update performance metrics
  void _updatePerformanceMetrics(
    int preprocessTime,
    int inferenceTime,
    int postprocessTime,
  ) {
    _performanceMetrics['totalInferences'] =
        (_performanceMetrics['totalInferences'] ?? 0) + 1;
    _performanceMetrics['totalPreprocessingTime'] =
        (_performanceMetrics['totalPreprocessingTime'] ?? 0) + preprocessTime;
    _performanceMetrics['totalInferenceTime'] =
        (_performanceMetrics['totalInferenceTime'] ?? 0) + inferenceTime;
    _performanceMetrics['totalPostprocessingTime'] =
        (_performanceMetrics['totalPostprocessingTime'] ?? 0) + postprocessTime;
  }

  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    final totalInferences = _performanceMetrics['totalInferences'] ?? 0;
    if (totalInferences == 0) return {'message': 'No inferences performed yet'};

    return {
      'totalInferences': totalInferences,
      'averagePreprocessingTime':
          (_performanceMetrics['totalPreprocessingTime']! / totalInferences)
              .round(),
      'averageInferenceTime':
          (_performanceMetrics['totalInferenceTime']! / totalInferences)
              .round(),
      'averagePostprocessingTime':
          (_performanceMetrics['totalPostprocessingTime']! / totalInferences)
              .round(),
      'averageTotalTime':
          ((_performanceMetrics['totalPreprocessingTime']! +
                      _performanceMetrics['totalInferenceTime']! +
                      _performanceMetrics['totalPostprocessingTime']!) /
                  totalInferences)
              .round(),
    };
  }

  /// Analyze model structure with comprehensive validation
  Future<void> _analyzeModelStructure() async {
    try {
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      if (inputTensors.isEmpty) {
        throw InferenceException('Model has no input tensors');
      }

      if (outputTensors.isEmpty) {
        throw InferenceException('Model has no output tensors');
      }

      _inputShape = inputTensors[0].shape;
      _outputShape = outputTensors[0].shape;

      print('📊 Model Analysis:');
      for (int i = 0; i < inputTensors.length; i++) {
        print(
          '   Input $i: ${inputTensors[i].shape} (${inputTensors[i].type})',
        );
      }
      for (int i = 0; i < outputTensors.length; i++) {
        print(
          '   Output $i: ${outputTensors[i].shape} (${outputTensors[i].type})',
        );
      }

      // Validate tensor types
      if (inputTensors[0].type.toString() != 'TfLiteType.float32') {
        print(
          '⚠️ Warning: Input tensor is not float32: ${inputTensors[0].type}',
        );
      }
    } catch (e) {
      throw InferenceException('Failed to analyze model structure: $e');
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
    } else if (lowerPath.contains('conformer')) {
      return ASRModelType.conformer;
    } else if (lowerPath.contains('speecht5')) {
      return ASRModelType.speechT5;
    } else if (lowerPath.contains('speech') || lowerPath.contains('asr')) {
      return ASRModelType.speechRecognition;
    }

    // Try to detect from model structure
    if (_inputShape != null && _outputShape != null) {
      final totalInputSize = _inputShape!.reduce((a, b) => a * b);
      if (totalInputSize == 240000 || // 80 * 3000
          (_inputShape!.length >= 3 &&
              _inputShape![1] == 80 &&
              _inputShape![2] == 3000)) {
        return ASRModelType.whisper;
      }
    }

    return ASRModelType.whisper; // Default to Whisper
  }

  //Configure model-specific settings
  void _configureModelSpecificSettings() {
    switch (_modelType) {
      case ASRModelType.whisper:
        _modelConfig = ModelConfig(
          sampleRate: 16000,
          nMels: 80,
          nFFT: 400,
          hopLength: 160,
          maxAudioLength: 480000,
          usePreemphasis: false,
          normalizeAudio: true,
        );
        break;
      case ASRModelType.wav2vec2:
        _modelConfig = ModelConfig(
          sampleRate: 16000,
          nMels: 40,
          nFFT: 512,
          hopLength: 256,
          maxAudioLength: 320000,
          usePreemphasis: false,
          normalizeAudio: true,
        );
        break;
      default:
        _modelConfig = ModelConfig(
          sampleRate: 16000,
          nMels: 80,
          nFFT: 400,
          hopLength: 160,
          maxAudioLength: 480000,
          usePreemphasis: false,
          normalizeAudio: true,
        );
    }
  }

  // Validate model compatibility
  Future<void> _validateModelCompatibility() async {
    if (_inputShape == null || _outputShape == null) {
      throw InferenceException('Could not determine model input/output shapes');
    }

    final inputSize = _inputShape!.reduce((a, b) => a * b);
    if (inputSize < 1000) {
      print('Warning: Input size seems small for audio model: $inputSize');
    }

    if (_inputShape![0] != 1) {
      print('Warning: Expected batch size 1, got ${_inputShape![0]}');
    }

    // Validate Whisper-specific requirements
    if (_modelType == ASRModelType.whisper) {
      if (inputSize != 240000) {
        print(
          '⚠️ Warning: Whisper model input size is ${inputSize}, expected 240000',
        );
      }
    }

    print('✅ Model compatibility validated');
  }

  Future<List<double>> preprocessAudioSamples(List<double> audioSamples) async {
    return await compute(_preprocessAudioForWhisperIsolate, audioSamples);
  }

  Future<String> inferChunk(List<double> melFrames) async {
    final output = await _runInference(melFrames);
    return await _decodeWhisperOutput(output);
  }

  Future<void> _loadVocabulary() async {
    const assetPath = 'assets/models/vocab.json';
    const remoteUrl =
        'https://huggingface.co/openai/whisper-tiny/resolve/main/vocab.json';

    String jsonStr;
    try {
      jsonStr = await rootBundle.loadString(assetPath);
    } catch (_) {
      final resp = await http.get(Uri.parse(remoteUrl));
      if (resp.statusCode != 200) {
        throw Exception(
          'Failed to download vocab.json (HTTP ${resp.statusCode})',
        );
      }
      jsonStr = resp.body;
    }
    final Map<String, dynamic> rawMap =
        json.decode(jsonStr) as Map<String, dynamic>;

    final vocab = <int, String>{};
    rawMap.forEach((token, idDynamic) {
      final id =
          (idDynamic is int) ? idDynamic : int.parse(idDynamic.toString());
      vocab[id] = token;
    });
    _vocabulary = vocab;
    final count = _vocabulary!.length;
    print('📚 Loaded vocabulary: $count tokens');
  }

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
    // Stop any ongoing recording
    if (_isRecording) {
      try {
        await _audioRecorder.stop();
      } catch (e) {
        print('Warning: Error stopping recording: $e');
      }
      _isRecording = false;
      _isStreamingMode = false;
    }

    // Close interpreter
    if (_interpreter != null) {
      _interpreter!.close();
      _interpreter = null;
    }

    // Clear state
    _isModelLoaded = false;
    _currentModelPath = null;
    _modelType = null;
    _vocabulary = null;
    _inputShape = null;
    _outputShape = null;
    _audioBuffer.clear();
    _componentsInitialized = false;

    // Clear performance metrics
    _performanceMetrics.clear();

    print('🎤 TFLite ASR model unloaded');
  }

  @override
  bool get isModelLoaded => _isModelLoaded;

  // Getters
  bool get isRecording => _isRecording;
  ASRModelType? get modelType => _modelType;
  String? get currentModelPath => _currentModelPath;
  Map<int, String>? get vocabulary => _vocabulary;
  List<int>? get inputShape => _inputShape;
  List<int>? get outputShape => _outputShape;
  int get sampleRate => SAMPLE_RATE;
}

// Supporting classes and enums
enum ASRModelType {
  whisper,
  wav2vec2,
  deepspeech,
  conformer,
  speechT5,
  speechRecognition,
  generic,
}

enum AudioFormat { wav, pcm16, pcm32, float32, mp3, flac, m4a }

class ModelConfig {
  final int sampleRate;
  final int nMels;
  final int nFFT;
  final int hopLength;
  final int maxAudioLength;
  final bool usePreemphasis;
  final bool normalizeAudio;

  ModelConfig({
    required this.sampleRate,
    required this.nMels,
    required this.nFFT,
    required this.hopLength,
    required this.maxAudioLength,
    required this.usePreemphasis,
    required this.normalizeAudio,
  });
}

class ASRConfig {
  final int sampleRate;
  final int bitRate;
  final int maxTokens;
  final bool verbose;

  const ASRConfig({
    this.sampleRate = 16000,
    this.bitRate = 256000,
    this.maxTokens = 448,
    this.verbose = false,
  });

  factory ASRConfig.defaultConfig() => const ASRConfig();

  factory ASRConfig.mobile() => const ASRConfig(
    sampleRate: 16000,
    bitRate: 128000,
    maxTokens: 224,
    verbose: false,
  );
}
