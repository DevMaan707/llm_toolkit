import 'package:flutter/foundation.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import '../models/app_models.dart';
import '../utils/logger.dart';
import 'package:llm_toolkit/src/services/asr_service.dart';

class ASRServiceWrapper extends ChangeNotifier {
  final AppLogger _logger = AppLogger();
  ASRService? _asrService;

  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _selectedModelPath;
  String? _selectedModelName;
  String _transcriptionResult = '';

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  String? get selectedModelPath => _selectedModelPath;
  String? get selectedModelName => _selectedModelName;
  String get transcriptionResult => _transcriptionResult;
  AppLogger get logger => _logger;

  /// Initialize ASR with selected model
  Future<void> initializeASR(String modelPath, String modelName) async {
    _logger.info('🎤 Initializing ASR with model: $modelName');
    _setProcessing(true);

    try {
      _asrService = ASRService();
      final config = ASRConfig.mobile(); // Use mobile-optimized config
      await _asrService!.initialize(modelPath, config: config);

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
          '⚠️ ASR output is empty or "...". Check model compatibility, input audio, or try another model.',
        );
      } else {
        _logger.success(
          '✅ Transcription completed: "${result.substring(0, result.length > 50 ? 50 : result.length)}..."',
        );
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
          '⚠️ ASR file output is empty or "...". Check model compatibility or input file.',
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
    try {
      _logger.info('🎤 Starting live streaming transcription...');
      _isRecording = true;
      _transcriptionResult = '';
      notifyListeners();

      await for (final chunk in _asrService!.startStreamingTranscription()) {
        _transcriptionResult += chunk;
        notifyListeners();
        yield chunk;
      }
    } catch (e) {
      _logger.error('❌ Streaming transcription failed', e);
      _isRecording = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Stop streaming transcription
  Future<void> stopStreamingTranscription() async {
    if (_asrService != null) {
      await _asrService!.stopStreamingTranscription();
      _isRecording = false;
      notifyListeners();
      _logger.info('🎤 Stopped streaming transcription');
    }
  }

  /// Test microphone access
  Future<bool> testMicrophoneAccess() async {
    if (_asrService == null) {
      _asrService = ASRService();
    }
    try {
      return await _asrService!.testMicrophoneAccess();
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
    _asrService?.dispose();
    _logger.dispose();
    super.dispose();
  }
}
