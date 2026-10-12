import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llm_toolkit/llm_toolkit.dart';

import '../models/app_models.dart';
import '../utils/logger.dart';

class ASRServiceWrapper extends ChangeNotifier {
  final AppLogger _logger = AppLogger();
  ASRService? _asrService;

  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isStreaming = false;
  String? _selectedModelPath;
  String? _selectedModelName;
  String _transcriptionResult = '';

  bool _shouldStopStreaming = false;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get isStreaming => _isStreaming;
  String? get selectedModelPath => _selectedModelPath;
  String? get selectedModelName => _selectedModelName;
  String get transcriptionResult => _transcriptionResult;
  AppLogger get logger => _logger;

  /// Initialize ASR with selected model
  Future<void> initializeASR(String modelPath, String modelName) async {
    _logger.info('🎤 Initializing ASR with model: $modelName');
    _setProcessing(true);

    try {
      await _asrService?.dispose();
      _asrService = ASRService(config: const ASRConfig.mobile());
      await _asrService!.initialize(modelPath);

      _selectedModelPath = modelPath;
      _selectedModelName = modelName;
      _isInitialized = true;
      _logger.success('✅ ASR service initialized successfully');
    } catch (e) {
      _logger.error('❌ Failed to initialize ASR service', e);
      _isInitialized = false;
      rethrow;
    } finally {
      _setProcessing(false);
    }
  }

  /// Start recording audio
  Future<void> startRecording() async {
    if (!_isInitialized || _asrService == null) {
      throw Exception('ASR service not initialized');
    }
    try {
      _logger.info('🎤 Starting audio recording...');
      await _asrService!.startRecording();
      _isRecording = true;
      _transcriptionResult = '';
      notifyListeners();
      _logger.success('✅ Recording started');
    } catch (e) {
      _logger.error('❌ Failed to start recording', e);
      rethrow;
    }
  }

  /// Stop recording and get transcription
  Future<void> stopRecording() async {
    if (!_isInitialized || _asrService == null || !_isRecording) {
      return;
    }
    try {
      _logger.info('🎤 Stopping recording and transcribing...');
      _setProcessing(true);

      final result = await _asrService!.stopRecording();

      _transcriptionResult = result;
      _isRecording = false;

      if (result.trim().isEmpty || result.trim() == "...") {
        _logger.warning(
          '⚠️ ASR output is empty or "...". Check model compatibility.',
        );
      } else {
        _logger.success('✅ Transcription completed');
      }
      notifyListeners();
    } catch (e) {
      _logger.error('❌ Failed to stop recording or transcribe', e);
      _isRecording = false;
      rethrow;
    } finally {
      _setProcessing(false);
    }
  }

  /// Transcribe audio file
  Future<void> transcribeFile(String filePath) async {
    if (!_isInitialized || _asrService == null) {
      throw Exception('ASR service not initialized');
    }
    try {
      _logger.info('🎤 Transcribing file: ${filePath.split('/').last}');
      _setProcessing(true);

      final result = await _asrService!.transcribeFile(filePath);
      _transcriptionResult = result;

      if (result.trim().isEmpty || result.trim() == "...") {
        _logger.warning(
          '⚠️ ASR file output is empty or "...". Check model compatibility.',
        );
      } else {
        _logger.success('✅ File transcription completed');
      }
      notifyListeners();
    } catch (e) {
      _logger.error('❌ Failed to transcribe file', e);
      rethrow;
    } finally {
      _setProcessing(false);
    }
  }

  /// Start live streaming transcription
  Stream<String> startStreamingTranscription() async* {
    if (!_isInitialized || _asrService == null) {
      throw Exception('ASR service not initialized');
    }

    _logger.info('🎤 Starting live streaming transcription...');
    _isStreaming = true;
    _isRecording = true;
    _shouldStopStreaming = false;
    _transcriptionResult = '';
    notifyListeners();

    try {
      // Use the ASR service's streaming method
      await for (final chunk in _asrService!.startStreamingTranscription()) {
        if (_shouldStopStreaming) break;

        _transcriptionResult += '$chunk ';
        notifyListeners();
        yield chunk;
      }
    } catch (e) {
      _logger.error('❌ Streaming transcription failed', e);
      rethrow;
    } finally {
      _isStreaming = false;
      _isRecording = false;
      notifyListeners();
    }
  }

  /// Stop streaming transcription
  Future<void> stopStreamingTranscription() async {
    _logger.info('🎤 Stopping streaming transcription...');

    _shouldStopStreaming = true;

    // Stop the ASR service streaming
    if (_asrService != null) {
      try {
        await _asrService!.stopStreamingTranscription();
      } catch (e) {
        _logger.error('❌ Error stopping ASR service streaming', e);
      }
    }

    _isStreaming = false;
    _isRecording = false;
    notifyListeners();

    _logger.info('🎤 Streaming transcription stopped successfully');
  }

  /// Test microphone access
  Future<bool> testMicrophoneAccess() async {
    try {
      final service = _asrService;
      if (service != null) return await service.testMicrophoneAccess();
      final probe = ASRService();
      try {
        return await probe.testMicrophoneAccess();
      } finally {
        await probe.dispose();
      }
    } catch (e) {
      _logger.error('❌ Microphone test failed', e);
      return false;
    }
  }

  /// Get available TFLite models for ASR
  List<LocalModel> getAvailableASRModels(List<LocalModel> downloadedModels) {
    return downloadedModels
        .where((model) => model.path.toLowerCase().endsWith('.tflite'))
        .toList();
  }

  /// Clear transcription result
  void clearResult() {
    _transcriptionResult = '';
    notifyListeners();
  }

  void _setProcessing(bool processing) {
    _isProcessing = processing;
    notifyListeners();
  }

  @override
  void dispose() {
    _shouldStopStreaming = true;
    _asrService?.dispose();
    _logger.dispose();
    super.dispose();
  }
}
