import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../core/inference/tflite_asr_engine.dart';
import '../core/config.dart';
import '../exceptions/llm_toolkit_exceptions.dart';

class ASRService {
  TFLiteASREngine? _asrEngine;
  bool _isInitialized = false;
  String? _currentModelPath;
  ASRModelType? _currentModelType;

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isStreamingMode = false;

  // Streaming
  StreamController<String>? _transcriptionController;
  Timer? _streamingTimer;
  List<double> _audioBuffer = [];

  // Configuration
  ASRConfig _config = ASRConfig.defaultConfig();

  /// Initialize ASR service with a model
  Future<void> initialize(String modelPath, {ASRConfig? config}) async {
    try {
      print('🎤 Initializing ASR Service...');

      _config = config ?? ASRConfig.defaultConfig();
      _asrEngine = TFLiteASREngine();

      // Convert ASRConfig to InferenceConfig for compatibility
      final inferenceConfig = InferenceConfig(
        promptFormat: 'asr',
        maxTokens: _config.maxTokens,
        verbose: _config.verbose,
      );

      await _asrEngine!.loadModel(modelPath, inferenceConfig);

      _isInitialized = true;
      _currentModelPath = modelPath;
      _currentModelType = _asrEngine!.modelType;

      print('✅ ASR Service initialized successfully');
      print('   Model: ${modelPath.split('/').last}');
      print('   Type: ${_currentModelType?.name}');
    } catch (e) {
      await dispose();
      throw InferenceException('Failed to initialize ASR service: $e');
    }
  }

  Future<String> processAudioChunk(Uint8List audioBytes) async {
    _checkInitialized();

    try {
      if (_asrEngine == null) {
        throw InferenceException('ASR engine not available');
      }

      final audioSamples = await _asrEngine!.convertAudioToSamples(
        audioBytes,
        AudioFormat.wav,
      );

      if (audioSamples.isEmpty) {
        return '';
      }
      final melFrames = await _asrEngine!.preprocessAudioSamples(audioSamples);

      // Use inferChunk for fast processing
      return await _asrEngine!.inferChunk(melFrames);
    } catch (e) {
      throw InferenceException('Failed to process audio chunk: $e');
    }
  }

  Future<String> transcribeFile(String audioFilePath) async {
    _checkInitialized();

    try {
      print(
        '🎤 Transcribing file with enhanced processing: ${audioFilePath.split('/').last}',
      );

      final audioFile = File(audioFilePath);
      if (!await audioFile.exists()) {
        throw InferenceException('Audio file not found: $audioFilePath');
      }

      final audioBytes = await audioFile.readAsBytes();
      final extension = audioFilePath.toLowerCase().split('.').last;

      // Determine format
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

      // Use enhanced transcription with chunking for longer files
      final fileSize = audioBytes.length;
      final estimatedDuration = fileSize / (16000 * 2); // Rough estimate

      if (estimatedDuration > 15.0) {
        // Use chunked transcription for longer files
        return await _asrEngine!.transcribeAudioChunked(
          audioBytes,
          format: format,
          sampleRate: _config.sampleRate,
          useChunking: true,
        );
      } else {
        // Use enhanced direct transcription
        return await _asrEngine!.transcribeAudio(
          audioBytes,
          format: format,
          sampleRate: _config.sampleRate,
        );
      }
    } catch (e) {
      throw InferenceException('Failed to transcribe file: $e');
    }
  }

  /// Transcribe audio bytes directly
  Future<String> transcribeBytes(
    Uint8List audioBytes, {
    AudioFormat format = AudioFormat.pcm16,
    int sampleRate = 16000,
  }) async {
    _checkInitialized();

    try {
      print(
        '🎤 Transcribing ${audioBytes.length} bytes of ${format.name} audio',
      );
      return await _asrEngine!.transcribeAudio(
        audioBytes,
        format: format,
        sampleRate: sampleRate,
      );
    } catch (e) {
      throw InferenceException('Failed to transcribe audio bytes: $e');
    }
  }

  /// Start recording audio
  Future<void> startRecording({bool streamingMode = false}) async {
    _checkInitialized();

    if (_isRecording) {
      throw InferenceException('Already recording');
    }

    try {
      // Check microphone permission
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw InferenceException('Microphone permission not granted');
      }

      _isStreamingMode = streamingMode;
      _audioBuffer.clear();

      // Get temporary directory for audio file
      final tempDir = await getTemporaryDirectory();
      final audioPath =
          '${tempDir.path}/asr_recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      // Configure recording
      final recordConfig = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: _config.sampleRate,
        bitRate: _config.bitRate,
        numChannels: 1, // Mono for ASR
      );

      await _audioRecorder.start(recordConfig, path: audioPath);
      _isRecording = true;

      print('🎤 Started recording (streaming: $_isStreamingMode)');

      // Start streaming transcription if enabled
      if (_isStreamingMode) {
        _startStreamingTranscription();
      }
    } catch (e) {
      _isRecording = false;
      throw InferenceException('Failed to start recording: $e');
    }
  }

  /// Stop recording and get transcription
  Future<String> stopRecording() async {
    _checkInitialized();

    if (!_isRecording) {
      throw InferenceException('Not currently recording');
    }

    try {
      // Stop streaming if active
      _stopStreamingTranscription();

      final audioPath = await _audioRecorder.stop();
      _isRecording = false;

      if (audioPath == null) {
        throw InferenceException('Failed to save audio recording');
      }

      print('🎤 Stopped recording, transcribing...');

      // Read and transcribe the audio file
      final audioFile = File(audioPath);
      final audioBytes = await audioFile.readAsBytes();

      final transcription = await transcribeBytes(
        audioBytes,
        format: AudioFormat.pcm16, // WAV files contain PCM16 data
        sampleRate: _config.sampleRate,
      );

      // Clean up temp file
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
    _checkInitialized();

    if (_transcriptionController != null &&
        !_transcriptionController!.isClosed) {
      await _transcriptionController!.close();
    }

    _transcriptionController = StreamController<String>.broadcast();
    _isStreamingMode = true;

    try {
      // Check microphone permission
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw InferenceException('Microphone permission not granted');
      }

      print('🎤 Starting continuous streaming transcription...');

      // Start the continuous streaming process
      _startContinuousStreaming();

      // Yield chunks from the controller
      await for (final chunk in _transcriptionController!.stream) {
        if (!_isStreamingMode) break;
        yield chunk;
      }
    } catch (e) {
      _isStreamingMode = false;
      _transcriptionController?.close();
      throw InferenceException('Failed to start streaming transcription: $e');
    }
  }

  Future _startContinuousStreaming() async {
    const chunkDuration = Duration(milliseconds: 6000); // 6 second chunks
    const overlapDuration = Duration(milliseconds: 1500); // 1.5 second overlap
    const minAudioThreshold =
        96000; // Minimum bytes for 6 seconds at 16kHz mono

    try {
      final tempDir = await getTemporaryDirectory();

      while (_isStreamingMode) {
        final recordingPath =
            '${tempDir.path}/stream_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';

        try {
          await _audioRecorder.start(
            RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: _config.sampleRate,
              bitRate: _config.bitRate,
              numChannels: 1,
            ),
            path: recordingPath,
          );

          await Future.delayed(chunkDuration);

          if (!_isStreamingMode) break;

          final recordedPath = await _audioRecorder.stop();

          if (recordedPath != null && _isStreamingMode) {
            final audioFile = File(recordedPath);
            if (await audioFile.exists()) {
              final audioBytes = await audioFile.readAsBytes();

              // Only process chunks with sufficient audio data
              if (audioBytes.length > minAudioThreshold) {
                try {
                  final result = await transcribeBytes(
                    audioBytes,
                    format: AudioFormat.wav,
                    sampleRate: _config.sampleRate,
                  );

                  if (TFLiteASREngine().isValidTranscription(result)) {
                    print('🎤 Streaming chunk result: "$result"');

                    if (_transcriptionController != null &&
                        !_transcriptionController!.isClosed) {
                      _transcriptionController!.add(result);
                    }
                  }
                } catch (e) {
                  print('❌ Error processing streaming chunk: $e');
                }
              } else {
                print(
                  '⚠️ Chunk too small, skipping (${audioBytes.length} bytes)',
                );
              }

              try {
                await audioFile.delete();
              } catch (e) {
                print('Warning: Failed to delete chunk file: $e');
              }
            }
          }

          if (_isStreamingMode) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          print('❌ Error in streaming chunk cycle: $e');
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
    } catch (e) {
      print('❌ Fatal streaming error: $e');
      _isStreamingMode = false;
      _transcriptionController?.addError(e);
    } finally {
      print('🎤 Enhanced streaming loop ended');
    }
  }

  /// Stop streaming transcription - enhanced version
  Future<void> stopStreamingTranscription() async {
    print('🎤 Stopping streaming transcription...');

    _isStreamingMode = false;

    // Stop any ongoing recording
    if (_isRecording) {
      try {
        await _audioRecorder.stop();
        _isRecording = false;
      } catch (e) {
        print('Warning: Error stopping recording: $e');
      }
    }

    // Close the transcription controller
    if (_transcriptionController != null &&
        !_transcriptionController!.isClosed) {
      _transcriptionController!.close();
    }
    _transcriptionController = null;

    print('✅ Streaming transcription stopped');
  }

  Future<String> recordAndTranscribe(Duration duration) async {
    _checkInitialized();

    try {
      await startRecording();

      // Wait for the specified duration
      await Future.delayed(duration);

      return await stopRecording();
    } catch (e) {
      // Ensure recording is stopped even if there's an error
      if (_isRecording) {
        try {
          await stopRecording();
        } catch (_) {}
      }
      throw InferenceException('Failed to record and transcribe: $e');
    }
  }

  Future<String> recordWithVAD({
    Duration maxDuration = const Duration(seconds: 30),
    Duration silenceTimeout = const Duration(seconds: 3),
    double silenceThreshold = 0.01,
  }) async {
    _checkInitialized();

    try {
      await startRecording();

      final startTime = DateTime.now();
      DateTime lastVoiceActivity = DateTime.now();

      // Monitor for voice activity
      while (DateTime.now().difference(startTime) < maxDuration) {
        await Future.delayed(const Duration(milliseconds: 100));

        final currentTime = DateTime.now();
        if (currentTime.difference(lastVoiceActivity) > silenceTimeout) {
          print('🎤 Silence detected, stopping recording');
          break;
        }
        if (_isRecording) {
          lastVoiceActivity = currentTime;
        }
      }

      return await stopRecording();
    } catch (e) {
      if (_isRecording) {
        try {
          await stopRecording();
        } catch (_) {}
      }
      throw InferenceException('Failed to record with VAD: $e');
    }
  }

  /// Internal method to handle streaming transcription
  void _startStreamingTranscription() {
    if (!_isStreamingMode || _transcriptionController == null) return;

    _streamingTimer = Timer.periodic(
      Duration(milliseconds: _config.streamingIntervalMs),
      (timer) async {
        if (!_isRecording || _transcriptionController == null) {
          timer.cancel();
          return;
        }

        try {
          await _processStreamingChunk();
        } catch (e) {
          _transcriptionController?.addError(e);
        }
      },
    );
  }

  /// Process a chunk of streaming audio
  Future<void> _processStreamingChunk() async {
    if (!_isRecording || _transcriptionController == null) return;

    try {
      // Get current recording path
      final tempDir = await getTemporaryDirectory();

      // Stop current recording temporarily to get audio data
      final currentPath = await _audioRecorder.stop();
      if (currentPath != null) {
        final audioFile = File(currentPath);
        if (await audioFile.exists()) {
          final audioBytes = await audioFile.readAsBytes();

          // Only process if we have enough audio data
          if (audioBytes.length > 1024) {
            // At least 1KB of audio
            try {
              final partialTranscription = await transcribeBytes(
                audioBytes,
                format: AudioFormat.pcm16,
                sampleRate: _config.sampleRate,
              );

              if (partialTranscription.trim().isNotEmpty) {
                _transcriptionController?.add(partialTranscription);
              }
            } catch (e) {
              print('Chunk transcription error: $e');
            }
          }

          // Clean up temp file
          await audioFile.delete();
        }
      }

      // Restart recording if still in streaming mode
      if (_isStreamingMode && _isRecording) {
        final newPath =
            '${tempDir.path}/asr_streaming_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _audioRecorder.start(
          RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: _config.sampleRate,
            bitRate: _config.bitRate,
            numChannels: 1,
          ),
          path: newPath,
        );
      }
    } catch (e) {
      print('Streaming chunk processing error: $e');
    }
  }

  /// Stop streaming transcription
  void _stopStreamingTranscription() {
    _streamingTimer?.cancel();
    _streamingTimer = null;
    _isStreamingMode = false;

    _transcriptionController?.close();
    _transcriptionController = null;
  }

  /// Get supported audio formats
  List<AudioFormat> getSupportedFormats() {
    return [AudioFormat.pcm16, AudioFormat.pcm32, AudioFormat.float32];
  }

  /// Get model information
  Map<String, dynamic> getModelInfo() {
    if (!_isInitialized || _asrEngine == null) {
      return {'initialized': false};
    }

    return {
      'initialized': true,
      'modelPath': _currentModelPath,
      'modelType': _currentModelType?.name,
      'supportedFormats': getSupportedFormats().map((f) => f.name).toList(),
    };
  }

  /// Get current recording status
  Map<String, dynamic> getRecordingStatus() {
    return {
      'isRecording': _isRecording,
      'isStreamingMode': _isStreamingMode,
      'hasPermission': _audioRecorder.hasPermission(),
      'config': {
        'sampleRate': _config.sampleRate,
        'bitRate': _config.bitRate,
        'streamingInterval': _config.streamingIntervalMs,
        'maxTokens': _config.maxTokens,
        'confidenceThreshold': _config.confidenceThreshold,
      },
    };
  }

  /// Update ASR configuration
  void updateConfig(ASRConfig config) {
    _config = config;
    print('🎤 ASR configuration updated');
  }

  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return {
      'modelLoaded': _isInitialized,
      'modelType': _currentModelType?.name ?? 'Unknown',
      'averageLatency': 'N/A', // Would need to track this
      'totalTranscriptions': 'N/A', // Would need to track this
      'errorRate': 'N/A', // Would need to track this
    };
  }

  /// Test microphone access
  Future<bool> testMicrophoneAccess() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        return false;
      }

      // Try a quick recording test
      final tempDir = await getTemporaryDirectory();
      final testPath = '${tempDir.path}/mic_test.wav';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: testPath,
      );

      await Future.delayed(const Duration(milliseconds: 500));

      final recordedPath = await _audioRecorder.stop();

      if (recordedPath != null) {
        final testFile = File(recordedPath);
        final exists = await testFile.exists();
        if (exists) {
          await testFile.delete();
        }
        return exists;
      }

      return false;
    } catch (e) {
      print('Microphone test failed: $e');
      return false;
    }
  }

  /// Check if service is initialized
  void _checkInitialized() {
    if (!_isInitialized || _asrEngine == null) {
      throw InferenceException('ASR service not initialized');
    }
  }

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  bool get isStreamingMode => _isStreamingMode;
  ASRModelType? get modelType => _currentModelType;
  String? get currentModelPath => _currentModelPath;
  ASRConfig get config => _config;

  /// Dispose resources
  Future<void> dispose() async {
    print('🎤 Disposing ASR Service...');

    // Stop any ongoing operations
    _stopStreamingTranscription();

    if (_isRecording) {
      try {
        await _audioRecorder.stop();
      } catch (e) {
        print('Warning: Error stopping recording during dispose: $e');
      }
      _isRecording = false;
    }

    // Dispose ASR engine
    if (_asrEngine != null) {
      await _asrEngine!.unloadModel();
      _asrEngine = null;
    }

    // Reset state
    _isInitialized = false;
    _currentModelPath = null;
    _currentModelType = null;
    _isStreamingMode = false;
    _audioBuffer.clear();

    print('✅ ASR Service disposed');
  }
}

/// ASR Configuration class
class ASRConfig {
  final int sampleRate;
  final int bitRate;
  final int streamingIntervalMs;
  final int maxTokens;
  final bool verbose;
  final double confidenceThreshold;
  final bool enableVAD;
  final Duration vadSilenceTimeout;
  final double vadSilenceThreshold;

  const ASRConfig({
    this.sampleRate = 16000,
    this.bitRate = 256000,
    this.streamingIntervalMs = 500,
    this.maxTokens = 1024,
    this.verbose = false,
    this.confidenceThreshold = 0.5,
    this.enableVAD = false,
    this.vadSilenceTimeout = const Duration(seconds: 3),
    this.vadSilenceThreshold = 0.01,
  });

  factory ASRConfig.defaultConfig() => const ASRConfig();

  // Fixed the factory constructor syntax
  factory ASRConfig.highQuality() => const ASRConfig(
    sampleRate: 16000,
    bitRate: 320000,
    streamingIntervalMs: 250, // Fixed: use colon instead of equals
    maxTokens: 2048,
    confidenceThreshold: 0.7,
    verbose: true,
  );

  factory ASRConfig.lowLatency() => const ASRConfig(
    sampleRate: 16000,
    bitRate: 128000,
    streamingIntervalMs: 100,
    maxTokens: 512,
    confidenceThreshold: 0.3,
  );

  factory ASRConfig.mobile() => const ASRConfig(
    sampleRate: 16000,
    bitRate: 192000,
    streamingIntervalMs: 500,
    maxTokens: 1024,
    confidenceThreshold: 0.5,
    enableVAD: true,
    vadSilenceTimeout: Duration(seconds: 2),
  );

  factory ASRConfig.streaming() => const ASRConfig(
    sampleRate: 16000,
    bitRate: 256000,
    streamingIntervalMs: 200,
    maxTokens: 1024,
    confidenceThreshold: 0.4,
    enableVAD: true,
  );

  ASRConfig copyWith({
    int? sampleRate,
    int? bitRate,
    int? streamingIntervalMs,
    int? maxTokens,
    bool? verbose,
    double? confidenceThreshold,
    bool? enableVAD,
    Duration? vadSilenceTimeout,
    double? vadSilenceThreshold,
  }) {
    return ASRConfig(
      sampleRate: sampleRate ?? this.sampleRate,
      bitRate: bitRate ?? this.bitRate,
      streamingIntervalMs: streamingIntervalMs ?? this.streamingIntervalMs,
      maxTokens: maxTokens ?? this.maxTokens,
      verbose: verbose ?? this.verbose,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      enableVAD: enableVAD ?? this.enableVAD,
      vadSilenceTimeout: vadSilenceTimeout ?? this.vadSilenceTimeout,
      vadSilenceThreshold: vadSilenceThreshold ?? this.vadSilenceThreshold,
    );
  }
}
