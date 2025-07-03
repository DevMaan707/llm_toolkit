import 'dart:async';
import 'dart:io';
import 'dart:math' as Math;
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import '../../exceptions/llm_toolkit_exceptions.dart';
import '../config.dart';
import 'base_inference_engine.dart';

class LlamaInferenceEngine extends BaseInferenceEngine {
  LlamaParent? _llamaParent;
  bool _isModelLoaded = false;
  String? _currentModelPath;
  static bool? _nativeLibrariesAvailable;

  static bool _debugMode = true;
  static const String _debugPrefix = '[LLAMA_ENGINE]';

  static void _debugLog(String message, {String? level}) {
    if (!_debugMode) return;

    final timestamp = DateTime.now().toIso8601String();
    final logLevel = level ?? 'INFO';
    print('$timestamp $_debugPrefix [$logLevel] $message');
  }

  static void _debugError(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    _debugLog('ERROR: $message', level: 'ERROR');
    if (error != null) {
      _debugLog('Error details: $error', level: 'ERROR');
    }
    if (stackTrace != null) {
      _debugLog('Stack trace:\n$stackTrace', level: 'ERROR');
    }
  }

  static void _debugSuccess(String message) {
    _debugLog('✅ $message', level: 'SUCCESS');
  }

  static void _debugWarning(String message) {
    _debugLog('⚠️  $message', level: 'WARNING');
  }

  static void setDebugMode(bool enabled) {
    _debugMode = enabled;
    _debugLog('Debug mode ${enabled ? 'ENABLED' : 'DISABLED'}');
  }

  static Future<Map<String, int>> getMemoryInfo() async {
    try {
      final file = File('/proc/meminfo');
      final content = await file.readAsString();

      final memTotal = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(content);
      final memAvailable = RegExp(
        r'MemAvailable:\s+(\d+)\s+kB',
      ).firstMatch(content);

      return {
        'totalMB': int.parse(memTotal?.group(1) ?? '0') ~/ 1024,
        'availableMB': int.parse(memAvailable?.group(1) ?? '0') ~/ 1024,
      };
    } catch (e) {
      _debugWarning('Could not read memory info: $e');
      return {'totalMB': 0, 'availableMB': 0};
    }
  }

  static Future<bool> validateGGUFFile(String modelPath) async {
    try {
      final file = File(modelPath);
      if (!await file.exists()) {
        _debugError('Model file does not exist: $modelPath');
        return false;
      }

      final fileSize = await file.length();
      _debugLog(
        'Model file size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB',
      );

      if (fileSize < 1024 * 1024) {
        _debugError('Model file appears to be too small: $fileSize bytes');
        return false;
      }

      final bytes = await file.openRead(0, 8).first;
      final magic = String.fromCharCodes(bytes.take(4));

      if (magic != 'GGUF') {
        _debugError('Invalid GGUF magic number: $magic (expected: GGUF)');
        return false;
      }

      final fileName = modelPath.split('/').last.toLowerCase();
      final problematicQuants = [];

      for (String problematicQuant in problematicQuants) {
        if (fileName.contains(problematicQuant)) {
          _debugWarning(
            'WARNING: Detected potentially unstable quantization: $problematicQuant',
          );
          _debugWarning(
            'This quantization is known to cause crashes on some devices',
          );
          _debugWarning('Recommended alternatives: Q4_K_M, Q4_0, Q5_K_M');

          throw InferenceException(
            'Unstable quantization detected: ${problematicQuant.toUpperCase()}\n'
            'This quantization causes crashes on Android.\n'
            'Recommended alternatives: Q4_K_M, Q4_0, Q5_K_M',
          );
        }
      }

      _debugSuccess('GGUF file validation passed');
      return true;
    } catch (e) {
      _debugError('Error validating GGUF file', e);
      return false;
    }
  }

  static Future<bool> checkNativeLibrariesAvailable() async {
    _debugLog('Starting native libraries availability check...');

    if (_nativeLibrariesAvailable != null) {
      _debugLog('Using cached result: $_nativeLibrariesAvailable');
      return _nativeLibrariesAvailable!;
    }

    try {
      _debugLog('Setting library path to: libllama.so');

      try {
        Llama.libraryPath = "libllama.so";
        _nativeLibrariesAvailable = true;
        _debugSuccess('Native libraries are available');
      } catch (e) {
        _debugError('Library availability test failed', e);
        _nativeLibrariesAvailable = false;
      }
    } catch (e, stackTrace) {
      _debugError('Native libraries check failed', e, stackTrace);
      _nativeLibrariesAvailable = false;
    }

    return _nativeLibrariesAvailable!;
  }

  @override
  Future<void> loadModel(String modelPath, InferenceConfig config) async {
    _debugLog('=== STARTING MODEL LOAD (ISOLATE MODE) ===');
    _debugLog('Model path: $modelPath');
    _debugLog('Config: nCtx=${config.nCtx}, verbose=${config.verbose}');

    _debugLog('Step 1: Pre-flight validation...');
    final memInfo = await getMemoryInfo();
    _debugLog(
      'Available memory: ${memInfo['availableMB']}MB / ${memInfo['totalMB']}MB',
    );

    if (memInfo['availableMB']! < 512) {
      _debugWarning(
        'Low memory detected: ${memInfo['availableMB']}MB available',
      );
      throw InferenceException(
        'Insufficient memory available (${memInfo['availableMB']}MB). '
        'Please close other apps and try again.',
      );
    }

    final isValid = await validateGGUFFile(modelPath);
    if (!isValid) {
      throw InferenceException('Invalid or corrupted GGUF file: $modelPath');
    }

    if (_llamaParent != null) {
      _debugLog('Disposing existing model...');
      await unloadModel();
    }

    try {
      _debugLog('Step 2: Creating model parameters...');
      final availableMB = memInfo['availableMB']!;
      int safeNCtx;

      if (availableMB < 1024) {
        safeNCtx = 512;
      } else if (availableMB < 2048) {
        safeNCtx = 1024;
      } else {
        safeNCtx = 2048;
      }

      final requestedNCtx = config.nCtx ?? 2048;
      final finalNCtx = Math.min(requestedNCtx, safeNCtx);

      // Create model parameters for isolate (correct API)
      final modelParams =
          ModelParams()
            ..nGpuLayers = 0
            ..useMemoryLock = false
            ..useMemorymap = true
            ..vocabOnly = false;

      _debugSuccess('Model parameters configured');

      _debugLog('Step 3: Creating context parameters...');
      final contextParams =
          ContextParams()
            ..nPredict = 512
            ..nCtx = finalNCtx
            ..nBatch = Math.min(256, finalNCtx ~/ 4)
            ..nThreads = 2
            ..ropeFreqBase = 10000.0
            ..ropeFreqScale = 1.0;

      _debugLog('Context parameters (memory-optimized):');
      _debugLog('  - nBatch: ${contextParams.nBatch}');
      _debugLog(
        '  - nCtx: ${contextParams.nCtx} (requested: $requestedNCtx, safe: $safeNCtx)',
      );
      _debugLog('  - nThreads: ${contextParams.nThreads}');
      _debugLog('  - ropeFreqBase: ${contextParams.ropeFreqBase}');
      _debugLog('  - ropeFreqScale: ${contextParams.ropeFreqScale}');

      _debugLog('Step 4: Creating sampling parameters...');
      final samplingParams =
          SamplerParams()
            ..temp = 0.7
            ..topK = 64
            ..topP = 0.95
            ..penaltyRepeat = 1.1;

      _debugSuccess('Sampling parameters configured');

      _debugLog('Step 5: Creating LlamaLoad command...');
      final loadCommand = LlamaLoad(
        path: modelPath,
        modelParams: modelParams,
        contextParams: contextParams,
        samplingParams: samplingParams,
        format: ChatMLFormat(),
      );

      _debugLog('Step 6: Initializing LlamaParent (isolate)...');
      _debugLog('Using isolate for maximum stability...');
      _debugLog('This may take several minutes for large models...');

      final stopwatch = Stopwatch()..start();

      try {
        _llamaParent = LlamaParent(loadCommand);
        await _llamaParent!.init();

        stopwatch.stop();
        _debugSuccess(
          'LlamaParent initialized in ${stopwatch.elapsedMilliseconds}ms',
        );
      } catch (e) {
        stopwatch.stop();
        _debugError('Failed to initialize LlamaParent', e);

        if (e.toString().contains('file') || e.toString().contains('path')) {
          throw InferenceException(
            'Model file not found or inaccessible: $modelPath. '
            'Please ensure the model file exists and is readable.',
          );
        } else if (e.toString().contains('format') ||
            e.toString().contains('gguf')) {
          throw InferenceException(
            'Invalid model format or corrupted GGUF file. '
            'Please re-download the model and try again.',
          );
        } else if (e.toString().contains('memory') ||
            e.toString().contains('allocation')) {
          throw InferenceException(
            'Insufficient memory to load model. Try:\n'
            '1. Close other apps to free memory\n'
            '2. Use a smaller model (Q4_K_M or smaller)\n'
            '3. Reduce context size to 512 or lower\n'
            '4. Restart your device to free system memory',
          );
        } else {
          throw InferenceException(
            'Failed to load model: $e\n\n'
            'Common solutions:\n'
            '1. Try a smaller or different quantization (Q4_K_M recommended)\n'
            '2. Ensure sufficient device memory (>2GB recommended)\n'
            '3. Re-download the model file\n'
            '4. Restart the app and try again',
          );
        }
      }

      _isModelLoaded = true;
      _currentModelPath = modelPath;

      _debugSuccess('=== MODEL LOAD COMPLETE (ISOLATE) ===');
      _debugLog('Model ready for inference in isolated environment');
      final finalMemInfo = await getMemoryInfo();
      _debugLog(
        'Available memory after load: ${finalMemInfo['availableMB']}MB',
      );
    } catch (e, stackTrace) {
      _debugError('=== MODEL LOAD FAILED ===', e, stackTrace);
      await unloadModel();
      _isModelLoaded = false;
      _currentModelPath = null;

      if (e is InferenceException) {
        rethrow;
      } else {
        throw InferenceException('Failed to load Llama model: $e');
      }
    }
  }

  @override
  Stream<String> generateText(String prompt, GenerationParams params) async* {
    _debugLog('=== STARTING TEXT GENERATION (ISOLATE) ===');
    _debugLog('Prompt length: ${prompt.length} characters');

    if (!_isModelLoaded || _llamaParent == null) {
      _debugError('Cannot generate text: Model not loaded');
      throw InferenceException('Llama model not loaded');
    }

    try {
      _debugLog('Step 1: Setting up response stream...');

      int tokenCount = 0;
      final maxTokens = params.maxTokens ?? 4096;

      _debugLog('Step 2: Starting generation...');
      _debugLog('Max tokens: $maxTokens');
      _debugLog('Starting generation without stop conditions...');

      final stopwatch = Stopwatch()..start();
      _debugLog('Sending prompt to LlamaParent...');
      _llamaParent!.sendPrompt(prompt);
      _debugLog('Prompt sent successfully');

      await for (final response in _llamaParent!.stream) {
        final token = response.toString();
        if (token.isNotEmpty) {
          tokenCount++;
          _debugLog('Token $tokenCount: "$token"');
          yield token;
          if (tokenCount % 100 == 0) {
            _debugLog('Generated $tokenCount tokens so far...');
          }
          if (tokenCount >= maxTokens) {
            _debugLog('Reached max tokens: $tokenCount');
            break;
          }
        }
      }

      stopwatch.stop();
      _debugSuccess('=== GENERATION COMPLETE ===');
      _debugLog('Total tokens generated: $tokenCount');
      _debugLog('Generation time: ${stopwatch.elapsedMilliseconds}ms');
      if (stopwatch.elapsedMilliseconds > 0) {
        _debugLog(
          'Tokens per second: ${(tokenCount * 1000 / stopwatch.elapsedMilliseconds).toStringAsFixed(2)}',
        );
      }
    } catch (e, stackTrace) {
      _debugError('=== GENERATION FAILED ===', e, stackTrace);
      if (e is InferenceException) {
        rethrow;
      } else {
        throw InferenceException('Failed to generate text with Llama: $e');
      }
    }
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    _debugWarning('Embeddings not implemented in isolate mode');
    throw UnimplementedError('Embeddings not supported in isolate mode');
  }

  @override
  Future<void> unloadModel() async {
    _debugLog('=== UNLOADING MODEL (ISOLATE) ===');

    if (_llamaParent != null) {
      _debugLog('Disposing LlamaParent...');
      try {
        _llamaParent!.dispose();
        _debugSuccess('LlamaParent disposed');
      } catch (e) {
        _debugError('Error disposing LlamaParent', e);
      }
      _llamaParent = null;
    }

    _isModelLoaded = false;
    _currentModelPath = null;
    _debugSuccess('Model unloaded successfully (isolate cleaned up)');

    final memInfo = await getMemoryInfo();
    _debugLog('Memory after unload: ${memInfo['availableMB']}MB available');
  }

  @override
  bool get isModelLoaded => _isModelLoaded;

  String? get currentModelPath => _currentModelPath;

  Map<String, dynamic> getDebugStatus() {
    return {
      'isModelLoaded': _isModelLoaded,
      'currentModelPath': _currentModelPath,
      'nativeLibrariesAvailable': _nativeLibrariesAvailable,
      'debugMode': _debugMode,
      'llamaParentExists': _llamaParent != null,
      'isolateMode': true,
    };
  }

  void printDebugInfo() {
    _debugLog('=== LLAMA ENGINE DEBUG INFO (ISOLATE) ===');
    final status = getDebugStatus();
    status.forEach((key, value) {
      _debugLog('$key: $value');
    });
    _debugLog('=== END DEBUG INFO ===');
  }

  static void resetNativeLibraryCheck() {
    _nativeLibrariesAvailable = null;
    _debugLog('Native library check cache cleared');
  }

  static Future<Map<String, dynamic>> getModelRecommendations() async {
    final memInfo = await getMemoryInfo();
    final availableMB = memInfo['availableMB']!;

    String recommendedQuantization;
    int recommendedNCtx;
    String memoryStatus;

    if (availableMB < 1024) {
      recommendedQuantization = 'Q4_0';
      recommendedNCtx = 512;
      memoryStatus = 'Low - Use smallest models only';
    } else if (availableMB < 2048) {
      recommendedQuantization = 'Q4_K_M';
      recommendedNCtx = 1024;
      memoryStatus = 'Medium - Use small to medium models';
    } else if (availableMB < 4096) {
      recommendedQuantization = 'Q4_K_M or Q5_K_M';
      recommendedNCtx = 2048;
      memoryStatus = 'Good - Use medium models';
    } else {
      recommendedQuantization = 'Q5_K_M or Q6_K';
      recommendedNCtx = 4096;
      memoryStatus = 'Excellent - Use large models';
    }

    return {
      'availableMemoryMB': availableMB,
      'memoryStatus': memoryStatus,
      'recommendedQuantization': recommendedQuantization,
      'recommendedNCtx': recommendedNCtx,
      'isolateMode': true,
      'warningMessage':
          availableMB < 1024
              ? 'Warning: Very low memory. Close other apps before loading models.'
              : null,
    };
  }
}
