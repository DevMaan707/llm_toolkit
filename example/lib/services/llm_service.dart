import 'package:flutter/foundation.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/app_models.dart';
import '../utils/logger.dart';
import '../data/recommended_models.dart';
import 'package:llm_toolkit/src/core/inference/llama_engine.dart';

class LLMService extends ChangeNotifier {
  final AppLogger _logger = AppLogger();

  // State
  List<ModelInfo> _searchModels = [];
  List<LocalModel> _downloadedModels = [];
  List<RecommendedModel> _recommendedModels = [];
  String? _loadedModelPath;
  String? _selectedModelName;
  InferenceEngineType? _activeEngine;
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  final Set<String> _downloadedModelFiles = {};
  DeviceInfo? _deviceInfo;
  bool _isLoading = false;
  bool _isSearching = false;
  String _lastSearchQuery = '';

  // Getters
  List<ModelInfo> get searchModels => _searchModels;
  List<LocalModel> get downloadedModels => _downloadedModels;
  List<RecommendedModel> get recommendedModels => _recommendedModels;
  String? get loadedModelPath => _loadedModelPath;
  String? get selectedModelName => _selectedModelName;
  InferenceEngineType? get activeEngine => _activeEngine;
  Map<String, double> get downloadProgress => _downloadProgress;
  Map<String, bool> get isDownloading => _isDownloading;
  Set<String> get downloadedModelFiles => _downloadedModelFiles;
  DeviceInfo? get deviceInfo => _deviceInfo;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get hasLoadedModel => _loadedModelPath != null;
  AppLogger get logger => _logger;

  Future<void> initialize() async {
    _logger.info('🚀 Initializing LLM Service...');
    try {
      LLMToolkit.instance.initialize(
        huggingFaceApiKey: '..',
        defaultConfig: InferenceConfig.mobile(),
      );

      await _loadDeviceInfo();
      await loadDownloadedModels();
      _loadRecommendedModels();
      await _loadFeaturedModels();

      _logger.success('✅ LLM Service initialized successfully');
    } catch (e, stackTrace) {
      _logger.error('❌ Failed to initialize LLM Service', e);
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> searchModelsFN(String query) async {
    if (query.trim().isEmpty) {
      await _loadFeaturedModels();
      return;
    }

    if (query == _lastSearchQuery && _searchModels.isNotEmpty) {
      return; // Don't search again for the same query
    }

    _lastSearchQuery = query;
    _setSearching(true);
    _logger.info('🔍 Searching models for: "$query"');

    try {
      final models = await LLMToolkit.instance.searchModels(query, limit: 15);
      _searchModels = models;
      _logger.success('✅ Found ${models.length} models for "$query"');

      if (models.isEmpty) {
        _logger.warning('⚠️ No models found for "$query"');
      }
    } catch (e) {
      _logger.error('❌ Failed to search models for "$query"', e);
      _searchModels = [];
    } finally {
      _setSearching(false);
    }
  }

  Future<void> searchRecommendedModel(RecommendedModel recommended) async {
    _logger.info('🔍 Searching recommended model: ${recommended.name}');
    _setSearching(true);

    try {
      final models = await LLMToolkit.instance.searchModels(
        recommended.searchTerm,
        limit: 5,
      );

      if (models.isNotEmpty) {
        _searchModels = models;
        _lastSearchQuery = recommended.searchTerm;
        _logger.success(
          '✅ Found ${models.length} models for ${recommended.name}',
        );
      } else {
        _logger.warning('⚠️ No models found for ${recommended.name}');
      }
    } catch (e) {
      _logger.error(
        '❌ Error searching recommended model ${recommended.name}',
        e,
      );
    } finally {
      _setSearching(false);
    }
  }

  Future<void> downloadAndLoadModel(ModelInfo model, String filename) async {
    final downloadKey = '${model.id}_$filename';
    _logger.info('⬇️ Starting download: ${model.name} - $filename');

    try {
      _isDownloading[downloadKey] = true;
      _downloadProgress[downloadKey] = 0.0;
      notifyListeners();

      final stopwatch = Stopwatch()..start();
      final modelPath = await LLMToolkit.instance.downloadModel(
        model,
        filename,
        onProgress: (progress) {
          _downloadProgress[downloadKey] = progress;
          notifyListeners();

          if (progress == 1.0) {
            stopwatch.stop();
            _logger.info(
              '✅ Download completed in ${stopwatch.elapsedMilliseconds}ms',
            );
          }
        },
      );

      final sanitizedModelId = model.id.replaceAll('/', '_');
      final downloadedFileName = '${sanitizedModelId}_$filename';
      _downloadedModelFiles.add(downloadedFileName);

      _isDownloading[downloadKey] = false;
      _downloadProgress[downloadKey] = 1.0;

      _logger.info('🔄 Loading model into memory...');
      await _loadModelWithConfig(modelPath, model.name);
      await loadDownloadedModels();

      _logger.success('✅ Model downloaded and loaded successfully');
    } catch (e) {
      _isDownloading[downloadKey] = false;
      _downloadProgress[downloadKey] = 0.0;
      _logger.error('❌ Failed to download/load model', e);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> loadLocalModel(LocalModel model) async {
    _logger.info('🔄 Loading local model: ${model.name}');
    try {
      await _loadModelWithConfig(model.path, model.name);
      _logger.success('✅ Local model loaded successfully');
    } catch (e) {
      _logger.error('❌ Failed to load local model', e);
      rethrow;
    }
  }

  Future<String?> browseAndLoadModel() async {
    _logger.info('📂 Opening file browser...');

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf', 'tflite'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;

        _logger.info('📁 Selected file: $fileName');

        // Copy to models directory
        final appDir = await getApplicationDocumentsDirectory();
        final modelsDir = Directory('${appDir.path}/models');
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }

        final targetPath = '${modelsDir.path}/$fileName';
        final sourceFile = File(filePath);
        await sourceFile.copy(targetPath);

        _logger.info('📋 Copied model to: $targetPath');

        // Load the model
        await _loadModelWithConfig(targetPath, fileName);

        // Refresh downloaded models list
        await loadDownloadedModels();

        _logger.success('✅ Model browsed and loaded successfully');
        return targetPath;
      } else {
        _logger.info('📂 File selection cancelled');
        return null;
      }
    } catch (e) {
      _logger.error('❌ Error browsing/loading model', e);
      rethrow;
    }
  }

  Future<void> deleteLocalModel(LocalModel model) async {
    try {
      await File(model.path).delete();
      await loadDownloadedModels();

      // If this was the loaded model, clear the loaded state
      if (_loadedModelPath == model.path) {
        _loadedModelPath = null;
        _selectedModelName = null;
        _activeEngine = null;
        notifyListeners();
      }

      _logger.success('✅ Model deleted successfully');
    } catch (e) {
      _logger.error('❌ Error deleting model', e);
      rethrow;
    }
  }

  bool isModelDownloaded(String modelId, String filename) {
    final sanitizedModelId = modelId.replaceAll('/', '_');
    final expectedFileName = '${sanitizedModelId}_$filename';
    return _downloadedModelFiles.contains(expectedFileName);
  }

  Stream<String> generateText(String prompt, {GenerationParams? params}) {
    if (!hasLoadedModel) {
      throw Exception('No model loaded');
    }

    _logger.info(
      '💬 Generating text for prompt: "${prompt.substring(0, prompt.length > 50 ? 50 : prompt.length)}..."',
    );

    return LLMToolkit.instance.generateText(
      prompt,
      params: params ?? GenerationParams.creative(),
    );
  }

  // Make this method public
  Future<void> loadDownloadedModels() async {
    _logger.info('📁 Loading downloaded models...');

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${appDir.path}/models');

      List<LocalModel> localModels = [];

      if (await modelsDir.exists()) {
        final files = await modelsDir.list().toList();

        for (final file in files) {
          if (file is File &&
              (file.path.endsWith('.gguf') || file.path.endsWith('.tflite'))) {
            final fileName = file.path.split('/').last;
            final fileSize = await file.length();
            final lastModified = await file.lastModified();
            final engine = ModelDetector.instance.detectEngine(fileName);

            _downloadedModelFiles.add(fileName);

            localModels.add(
              LocalModel(
                name: fileName,
                path: file.path,
                size: _formatFileSize(fileSize),
                lastModified: lastModified,
                engine: engine,
              ),
            );
          }
        }
      }

      _downloadedModels = localModels;
      _logger.success('✅ Found ${localModels.length} downloaded models');
    } catch (e) {
      _logger.error('❌ Error loading downloaded models', e);
    }
    notifyListeners();
  }

  Future<void> _loadModelWithConfig(String modelPath, String modelName) async {
    _logger.info('🔧 Configuring model: $modelPath');

    try {
      final engineType = ModelDetector.instance.detectEngine(modelPath);
      _logger.info('🎯 Detected engine: ${engineType.name}');

      InferenceConfig config;
      if (engineType == InferenceEngineType.gemma) {
        final modelType = ModelDetector.instance.detectGemmaModelType(
          modelPath,
        );
        config = InferenceConfig(
          modelType: modelType,
          preferredBackend: PreferredBackend.gpu,
          maxTokens: 512,
          supportImage: false,
          maxNumImages: 1,
        );
      } else {
        final availableMemory = _deviceInfo?.availableMemoryMB ?? 2048;
        int nCtx = availableMemory < 2048 ? 1024 : 2048;
        config = InferenceConfig(nCtx: nCtx, verbose: false);
      }

      _logger.info('🚀 Loading model with ${engineType.name} engine...');
      final loadStopwatch = Stopwatch()..start();

      await LLMToolkit.instance.loadModel(modelPath, config: config);

      loadStopwatch.stop();
      _logger.success(
        '✅ Model loaded successfully in ${loadStopwatch.elapsedMilliseconds}ms',
      );

      _loadedModelPath = modelPath;
      _selectedModelName = modelName;
      _activeEngine = LLMToolkit.instance.activeEngine;
      notifyListeners();
    } catch (e) {
      _logger.error('❌ Model loading failed', e);
      throw Exception('Failed to load model: $e');
    }
  }

  Future<void> _loadFeaturedModels() async {
    _logger.info('🔍 Loading featured models...');
    _setSearching(true);

    try {
      final searches = [
        'MaziyarPanahi/gemma',
        'MaziyarPanahi/llama',
        'MaziyarPanahi/phi',
        'microsoft/phi',
        'lmstudio-community',
        'bartowski',
      ];

      List<ModelInfo> allModels = [];

      for (String searchTerm in searches) {
        try {
          _logger.info('🔍 Searching for: $searchTerm');
          final models = await LLMToolkit.instance.searchModels(
            searchTerm,
            limit: 3,
          );
          allModels.addAll(models);
          _logger.info('✅ Found ${models.length} models for "$searchTerm"');
        } catch (e) {
          _logger.error('❌ Error searching for $searchTerm', e);
        }
      }

      final uniqueModels = <String, ModelInfo>{};
      for (final model in allModels) {
        if (!uniqueModels.containsKey(model.id)) {
          uniqueModels[model.id] = model;
        }
      }

      final sortedModels =
          uniqueModels.values.toList()
            ..sort((a, b) => b.downloads.compareTo(a.downloads));

      _searchModels = sortedModels.take(15).toList();
      _logger.success('✅ Loaded ${_searchModels.length} featured models');
    } catch (e) {
      _logger.error('❌ Error loading featured models', e);
    } finally {
      _setSearching(false);
    }
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final androidInfo = await deviceInfoPlugin.androidInfo;
      final memoryInfo = await LlamaInferenceEngine.getMemoryInfo();
      final recommendations =
          await LlamaInferenceEngine.getModelRecommendations();

      _deviceInfo = DeviceInfo(
        brand: androidInfo.brand,
        model: androidInfo.model,
        version: androidInfo.version.release,
        sdkInt: androidInfo.version.sdkInt,
        totalMemoryMB: memoryInfo['totalMB'] ?? 0,
        availableMemoryMB: memoryInfo['availableMB'] ?? 0,
        memoryStatus: recommendations['memoryStatus'] ?? '',
        recommendedQuantization:
            recommendations['recommendedQuantization'] ?? '',
        recommendedNCtx: recommendations['recommendedNCtx'] ?? 1024,
      );

      _logger.info('📱 Device: ${androidInfo.brand} ${androidInfo.model}');
      _logger.info('💾 Memory: ${memoryInfo['availableMB']}MB available');
    } catch (e) {
      _logger.error('❌ Failed to load device info', e);
    }
    notifyListeners();
  }

  void _loadRecommendedModels() {
    _recommendedModels = RecommendedModelsData.getModels();
    _logger.info('📋 Loaded ${_recommendedModels.length} recommended models');
    notifyListeners();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  void _setSearching(bool searching) {
    _isSearching = searching;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  @override
  void dispose() {
    _logger.dispose();
    super.dispose();
  }
}
