import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:llm_toolkit/src/core/inference/llama_engine.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LLM Toolkit Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      home: ModelBrowserScreen(),
    );
  }
}

class RecommendedModel {
  final String name;
  final String description;
  final String searchTerm;
  final String quantization;
  final String size;
  final InferenceEngineType engine;
  final String category;
  final bool isStable;

  RecommendedModel({
    required this.name,
    required this.description,
    required this.searchTerm,
    required this.quantization,
    required this.size,
    required this.engine,
    required this.category,
    this.isStable = true,
  });
}

class LocalModel {
  final String name;
  final String path;
  final String size;
  final DateTime lastModified;
  final InferenceEngineType engine;

  LocalModel({
    required this.name,
    required this.path,
    required this.size,
    required this.lastModified,
    required this.engine,
  });
}

class ModelBrowserScreen extends StatefulWidget {
  @override
  _ModelBrowserScreenState createState() => _ModelBrowserScreenState();
}

class _ModelBrowserScreenState extends State<ModelBrowserScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Search tab state
  List<ModelInfo> _searchModels = [];
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Recommended models with enhanced categories
  final List<RecommendedModel> _recommendedModels = [
    // Small & Fast Models
    RecommendedModel(
      name: 'Phi-3-mini 3.8B',
      description:
          'Microsoft\'s efficient small model, perfect for mobile devices with excellent instruction following',
      searchTerm: 'microsoft/Phi-3-mini Q4_K_M',
      quantization: 'Q4_K_M',
      size: '~2.4GB',
      engine: InferenceEngineType.llama,
      category: 'Small & Fast',
      isStable: true,
    ),
    RecommendedModel(
      name: 'Gemma 2B IT (TFLite)',
      description:
          'Google\'s instruction-tuned model optimized for mobile inference',
      searchTerm: 'google/gemma-2b tflite',
      quantization: 'INT4',
      size: '~1.4GB',
      engine: InferenceEngineType.gemma,
      category: 'Small & Fast',
      isStable: true,
    ),
    RecommendedModel(
      name: 'Qwen2-1.5B',
      description:
          'Alibaba\'s multilingual model with great performance-to-size ratio',
      searchTerm: 'Qwen/Qwen2-1.5B Q4_K_M',
      quantization: 'Q4_K_M',
      size: '~1.2GB',
      engine: InferenceEngineType.llama,
      category: 'Small & Fast',
      isStable: true,
    ),

    // Balanced Models
    RecommendedModel(
      name: 'Llama 3.2 3B',
      description:
          'Meta\'s latest efficient model with excellent capabilities and safety',
      searchTerm: 'meta-llama/Llama-3.2-3B Q4_K_M',
      quantization: 'Q4_K_M',
      size: '~2.0GB',
      engine: InferenceEngineType.llama,
      category: 'Balanced',
      isStable: true,
    ),
    RecommendedModel(
      name: 'Mistral 7B v0.3',
      description:
          'High-quality general purpose model with strong reasoning capabilities',
      searchTerm: 'mistralai/Mistral-7B-v0.3 Q4_K_M',
      quantization: 'Q4_K_M',
      size: '~4.1GB',
      engine: InferenceEngineType.llama,
      category: 'Balanced',
      isStable: true,
    ),

    // Code Models
    RecommendedModel(
      name: 'CodeLlama 7B',
      description:
          'Specialized for code generation, debugging, and programming assistance',
      searchTerm: 'codellama/CodeLlama-7b Q4_K_M',
      quantization: 'Q4_K_M',
      size: '~4.1GB',
      engine: InferenceEngineType.llama,
      category: 'Code',
      isStable: true,
    ),
    RecommendedModel(
      name: 'DeepSeek Coder 1.3B',
      description:
          'Compact but powerful coding assistant with multi-language support',
      searchTerm: 'deepseek-ai/deepseek-coder-1.3b Q4_K_M',
      quantization: 'Q4_K_M',
      size: '~0.8GB',
      engine: InferenceEngineType.llama,
      category: 'Code',
      isStable: true,
    ),

    // Multimodal Models
    RecommendedModel(
      name: 'Gemma 3 Nano Vision',
      description:
          'Vision-language model for image understanding and description',
      searchTerm: 'google/gemma-3-nano tflite',
      quantization: 'INT4',
      size: '~2.8GB',
      engine: InferenceEngineType.gemma,
      category: 'Multimodal',
      isStable: true,
    ),
  ];

  // Downloaded models
  List<LocalModel> _downloadedModels = [];

  // General state
  String? _loadedModelPath;
  String? _selectedModelName;
  InferenceEngineType? _activeEngine;
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  final Set<String> _downloadedModelFiles = {};

  // Debug state
  bool _debugMode = true;
  final List<String> _debugLogs = [];
  bool _showDebugPanel = false;

  // Device info
  Map<String, dynamic> _deviceInfo = {};
  Map<String, dynamic> _memoryRecommendations = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeToolkit();
    _loadDeviceInfo();
    _loadDownloadedModels();
    _loadFeaturedModels();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _initializeToolkit() {
    _logDebug('🚀 Initializing LLM Toolkit...', category: 'INIT');

    try {
      LLMToolkit.instance.initialize(
        huggingFaceApiKey: '..', //your hf token
        defaultConfig: InferenceConfig.mobile(),
      );
      _logDebug('✅ LLM Toolkit initialized successfully', category: 'INIT');
    } catch (e) {
      _logError('❌ Failed to initialize LLM Toolkit', e, category: 'INIT');
    }
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final androidInfo = await deviceInfoPlugin.androidInfo;
      final memoryInfo = await LlamaInferenceEngine.getMemoryInfo();
      final recommendations =
          await LlamaInferenceEngine.getModelRecommendations();

      setState(() {
        _deviceInfo = {
          'brand': androidInfo.brand,
          'model': androidInfo.model,
          'version': androidInfo.version.release,
          'sdkInt': androidInfo.version.sdkInt,
          'totalMemoryMB': memoryInfo['totalMB'],
          'availableMemoryMB': memoryInfo['availableMB'],
        };
        _memoryRecommendations = recommendations;
      });

      _logDebug(
        '📱 Device: ${androidInfo.brand} ${androidInfo.model}',
        category: 'DEVICE',
      );
      _logDebug(
        '💾 Memory: ${memoryInfo['availableMB']}MB available',
        category: 'DEVICE',
      );
    } catch (e) {
      _logError('❌ Failed to load device info', e, category: 'DEVICE');
    }
  }

  void _logDebug(
    String message, {
    String category = 'DEBUG',
    Map<String, dynamic>? data,
  }) {
    if (!_debugMode) return;

    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final logMessage = '[$timestamp] [$category] $message';

    setState(() {
      _debugLogs.add(logMessage);
      if (_debugLogs.length > 100) {
        _debugLogs.removeAt(0);
      }
    });

    developer.log(
      message,
      name: 'llm_toolkit.$category',
      error: data?.toString(),
    );
    print(logMessage);
  }

  void _logError(String message, dynamic error, {String category = 'ERROR'}) {
    _logDebug('$message: $error', category: category);
  }

  Future<void> _loadDownloadedModels() async {
    _logDebug('📁 Loading downloaded models...', category: 'MODELS');

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

      setState(() {
        _downloadedModels = localModels;
      });

      _logDebug(
        '✅ Found ${localModels.length} downloaded models',
        category: 'MODELS',
      );
    } catch (e) {
      _logError('❌ Error loading downloaded models', e, category: 'MODELS');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  Future<void> _browseAndLoadModel() async {
    _logDebug('📂 Opening file browser...', category: 'BROWSE');

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf', 'tflite'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;

        _logDebug('📁 Selected file: $fileName', category: 'BROWSE');
        _showSnackBar('Loading model: $fileName');

        // Copy to models directory
        final appDir = await getApplicationDocumentsDirectory();
        final modelsDir = Directory('${appDir.path}/models');
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }

        final targetPath = '${modelsDir.path}/$fileName';
        final sourceFile = File(filePath);
        await sourceFile.copy(targetPath);

        _logDebug('📋 Copied model to: $targetPath', category: 'BROWSE');

        // Load the model
        await _loadModelWithProperConfig(targetPath, fileName);

        setState(() {
          _loadedModelPath = targetPath;
          _selectedModelName = fileName;
          _activeEngine = LLMToolkit.instance.activeEngine;
        });

        // Refresh downloaded models list
        await _loadDownloadedModels();

        _showSnackBar('✅ Model loaded successfully!', isSuccess: true);
      } else {
        _logDebug('📂 File selection cancelled', category: 'BROWSE');
      }
    } catch (e) {
      _logError('❌ Error browsing/loading model', e, category: 'BROWSE');
      _showSnackBar('❌ Error loading model: $e', isError: true);
    }
  }

  Future<void> _loadFeaturedModels() async {
    _logDebug('🔍 Loading featured models...', category: 'SEARCH');
    setState(() => _isSearching = true);

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
          _logDebug('🔍 Searching for: $searchTerm', category: 'SEARCH');
          final models = await LLMToolkit.instance.searchModels(
            searchTerm,
            limit: 3,
          );
          allModels.addAll(models);
          _logDebug(
            '✅ Found ${models.length} models for "$searchTerm"',
            category: 'SEARCH',
          );
        } catch (e) {
          _logError('❌ Error searching for $searchTerm', e, category: 'SEARCH');
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

      setState(() => _searchModels = sortedModels.take(15).toList());

      if (_searchModels.isEmpty) {
        _showSnackBar(
          'No compatible models found. Try searching manually.',
          isError: true,
        );
      } else {
        _showSnackBar(
          'Loaded ${_searchModels.length} models successfully',
          isSuccess: true,
        );
      }
    } catch (e) {
      _logError('❌ Error loading featured models', e, category: 'SEARCH');
      _showSnackBar('Error loading models: $e', isError: true);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _searchModelsFn() async {
    if (_searchQuery.trim().isEmpty) {
      _loadFeaturedModels();
      return;
    }

    _logDebug('🔍 Starting search for: "$_searchQuery"', category: 'SEARCH');
    setState(() => _isSearching = true);

    try {
      final models = await LLMToolkit.instance.searchModels(
        _searchQuery,
        limit: 15,
      );
      setState(() => _searchModels = models);

      if (models.isEmpty) {
        _showSnackBar('No models found for "$_searchQuery"', isError: true);
      }
    } catch (e) {
      _logError('❌ Error searching models', e, category: 'SEARCH');
      _showSnackBar('Error searching models: $e', isError: true);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _searchRecommendedModel(RecommendedModel recommended) async {
    _logDebug(
      '🔍 Searching recommended: ${recommended.name}',
      category: 'RECOMMENDED',
    );
    setState(() => _isSearching = true);

    try {
      final models = await LLMToolkit.instance.searchModels(
        recommended.searchTerm,
        limit: 5,
      );

      if (models.isNotEmpty) {
        setState(() => _searchModels = models);
        _tabController.animateTo(0); // Switch to search tab
        _showSnackBar('Found ${models.length} models for ${recommended.name}');
      } else {
        _showSnackBar('No models found for ${recommended.name}', isError: true);
      }
    } catch (e) {
      _logError(
        '❌ Error searching recommended model',
        e,
        category: 'RECOMMENDED',
      );
      _showSnackBar('Error searching ${recommended.name}: $e', isError: true);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _loadLocalModel(LocalModel localModel) async {
    _logDebug('🔄 Loading local model: ${localModel.name}', category: 'LOCAL');
    _showSnackBar('Loading model into memory...');

    try {
      await _loadModelWithProperConfig(localModel.path, localModel.name);

      setState(() {
        _loadedModelPath = localModel.path;
        _selectedModelName = localModel.name;
        _activeEngine = LLMToolkit.instance.activeEngine;
      });

      _showSnackBar('✅ Model loaded successfully!', isSuccess: true);
    } catch (e) {
      _logError('❌ Error loading local model', e, category: 'LOCAL');
      _showSnackBar('❌ Error loading model: $e', isError: true);
    }
  }

  Future<void> _deleteLocalModel(LocalModel localModel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Delete Model'),
            content: Text(
              'Are you sure you want to delete "${localModel.name}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await File(localModel.path).delete();
        await _loadDownloadedModels();
        _showSnackBar('Model deleted successfully', isSuccess: true);
      } catch (e) {
        _showSnackBar('Error deleting model: $e', isError: true);
      }
    }
  }

  Future<void> _downloadAndLoadModel(ModelInfo model, String filename) async {
    final downloadKey = '${model.id}_$filename';
    _logDebug(
      '⬇️ Starting download: ${model.name} - $filename',
      category: 'DOWNLOAD',
    );

    try {
      setState(() {
        _isDownloading[downloadKey] = true;
        _downloadProgress[downloadKey] = 0.0;
      });

      _showSnackBar('Starting download: ${model.name}');

      final stopwatch = Stopwatch()..start();
      final modelPath = await LLMToolkit.instance.downloadModel(
        model,
        filename,
        onProgress: (progress) {
          setState(() {
            _downloadProgress[downloadKey] = progress;
          });

          if (progress == 1.0) {
            stopwatch.stop();
            _logDebug(
              '✅ Download completed in ${stopwatch.elapsedMilliseconds}ms',
              category: 'DOWNLOAD',
            );
          }
        },
      );

      final sanitizedModelId = model.id.replaceAll('/', '_');
      final downloadedFileName = '${sanitizedModelId}_$filename';
      _downloadedModelFiles.add(downloadedFileName);

      setState(() {
        _isDownloading[downloadKey] = false;
        _downloadProgress[downloadKey] = 1.0;
      });

      _logDebug('🔄 Starting model loading process...', category: 'LOAD');
      _showSnackBar('Loading model into memory...');

      await _loadModelWithProperConfig(modelPath, model.name);

      setState(() {
        _loadedModelPath = modelPath;
        _selectedModelName = model.name;
        _activeEngine = LLMToolkit.instance.activeEngine;
      });

      // Refresh downloaded models
      await _loadDownloadedModels();

      _logDebug(
        '✅ Model fully loaded and ready for inference',
        category: 'LOAD',
      );
      _showSnackBar('✅ Model loaded successfully!', isSuccess: true);
    } catch (e) {
      setState(() {
        _isDownloading[downloadKey] = false;
        _downloadProgress[downloadKey] = 0.0;
      });
      _logError('❌ Download/Load failed', e, category: 'DOWNLOAD');
      _showSnackBar('❌ Error: $e', isError: true);
    }
  }

  Future<void> _loadModelWithProperConfig(
    String modelPath,
    String modelName,
  ) async {
    _logDebug('🔧 Configuring model: $modelPath', category: 'LOAD');

    try {
      final engineType = ModelDetector.instance.detectEngine(modelPath);
      _logDebug('🎯 Detected engine: ${engineType.name}', category: 'LOAD');

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
        // Use conservative settings based on device memory
        final availableMemory = _deviceInfo['availableMemoryMB'] ?? 2048;
        int nCtx = availableMemory < 2048 ? 1024 : 2048;

        config = InferenceConfig(nCtx: nCtx, verbose: false);
      }

      _logDebug(
        '🚀 Loading model with ${engineType.name} engine...',
        category: 'LOAD',
      );
      final loadStopwatch = Stopwatch()..start();

      await LLMToolkit.instance.loadModel(modelPath, config: config);

      loadStopwatch.stop();
      _logDebug(
        '✅ Model loaded successfully in ${loadStopwatch.elapsedMilliseconds}ms',
        category: 'LOAD',
      );
    } catch (e) {
      _logError('❌ Model loading failed', e, category: 'LOAD');
      throw Exception('Failed to load model: $e');
    }
  }

  bool _isModelDownloaded(String modelId, String filename) {
    final sanitizedModelId = modelId.replaceAll('/', '_');
    final expectedFileName = '${sanitizedModelId}_$filename';
    return _downloadedModelFiles.contains(expectedFileName);
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    bool isSuccess = false,
    Duration? duration,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error
                  : isSuccess
                  ? Icons.check_circle
                  : Icons.info,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor:
            isError
                ? Colors.red.shade600
                : isSuccess
                ? Colors.green.shade600
                : Colors.blue.shade600,
        duration: duration ?? Duration(seconds: isError ? 4 : 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildLoadedModelStatus() {
    if (_loadedModelPath == null) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade100, Colors.green.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check, color: Colors.white, size: 24),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Model Ready',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '$_selectedModelName (${_activeEngine?.name})',
                  style: TextStyle(color: Colors.green.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatScreen()),
              );
            },
            icon: Icon(Icons.chat_bubble, size: 18),
            label: Text('Chat', style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        // Search Bar
        Container(
          margin: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search models (GGUF, TFLite, gemma, llama, phi)...',
              prefixIcon: Icon(Icons.search, color: Colors.blue.shade600),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey.shade600),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _loadFeaturedModels();
                        },
                      )
                      : IconButton(
                        icon: Icon(Icons.tune, color: Colors.blue.shade600),
                        onPressed: () => _searchModelsFn(),
                      ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
            onSubmitted: (value) => _searchModelsFn(),
          ),
        ),

        // Browse Button
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16),
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _browseAndLoadModel,
            icon: Icon(Icons.folder_open, size: 20),
            label: Text(
              'Browse & Load Model from Device',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade600,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16),
              elevation: 3,
            ),
          ),
        ),

        SizedBox(height: 16),

        // Models List
        Expanded(
          child:
              _isSearching
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.blue.shade600),
                        SizedBox(height: 16),
                        Text(
                          'Loading models...',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                  : _searchModels.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No models found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Try searching for different terms',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    itemCount: _searchModels.length,
                    itemBuilder:
                        (context, index) =>
                            _buildModelCard(_searchModels[index]),
                  ),
        ),
      ],
    );
  }

  Widget _buildRecommendedTab() {
    final categories =
        _recommendedModels.map((m) => m.category).toSet().toList();

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        // Device Info Card
        if (_deviceInfo.isNotEmpty) _buildDeviceInfoCard(),

        SizedBox(height: 16),

        Text(
          'Recommended Models for Your Device',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'These models are tested and optimized for Android devices',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
        SizedBox(height: 24),

        ...categories.map((category) {
          final categoryModels =
              _recommendedModels.where((m) => m.category == category).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                    fontSize: 18,
                  ),
                ),
              ),
              SizedBox(height: 12),
              ...categoryModels.map(
                (model) => _buildRecommendedModelCard(model),
              ),
              SizedBox(height: 24),
            ],
          );
        }).toList(),
      ],
    );
  }

  Widget _buildDeviceInfoCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.phone_android,
                  color: Colors.blue.shade600,
                  size: 24,
                ),
                SizedBox(width: 12),
                Text(
                  'Device Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device: ${_deviceInfo['brand']} ${_deviceInfo['model']}',
                      ),
                      Text(
                        'Android: ${_deviceInfo['version']} (API ${_deviceInfo['sdkInt']})',
                      ),
                      Text(
                        'Memory: ${_deviceInfo['availableMemoryMB']}MB / ${_deviceInfo['totalMemoryMB']}MB',
                      ),
                    ],
                  ),
                ),
                if (_memoryRecommendations.isNotEmpty)
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _memoryRecommendations['memoryStatus'] ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Recommended: ${_memoryRecommendations['recommendedQuantization']}',
                          style: TextStyle(
                            color: Colors.green.shade600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendedModelCard(RecommendedModel model) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors:
                          model.engine == InferenceEngineType.gemma
                              ? [Colors.blue.shade300, Colors.blue.shade600]
                              : [Colors.green.shade300, Colors.green.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    model.engine == InferenceEngineType.gemma
                        ? Icons.psychology
                        : Icons.memory,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              model.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          if (model.isStable)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'STABLE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              model.quantization,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              model.size,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              model.description,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _searchRecommendedModel(model),
                  icon: Icon(Icons.search, size: 16),
                  label: Text('Find Models'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadedTab() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.storage, color: Colors.blue.shade600, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Downloaded Models',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    Text(
                      '${_downloadedModels.length} models available',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _loadDownloadedModels,
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              _downloadedModels.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No downloaded models',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Download models from the Search tab',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    itemCount: _downloadedModels.length,
                    itemBuilder:
                        (context, index) =>
                            _buildLocalModelCard(_downloadedModels[index]),
                  ),
        ),
      ],
    );
  }

  Widget _buildLocalModelCard(LocalModel model) {
    final isCurrentlyLoaded = _loadedModelPath == model.path;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors:
                          model.engine == InferenceEngineType.gemma
                              ? [Colors.blue.shade300, Colors.blue.shade600]
                              : [Colors.green.shade300, Colors.green.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    model.engine == InferenceEngineType.gemma
                        ? Icons.psychology
                        : Icons.memory,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.storage,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            model.size,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 12),
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '${model.lastModified.day}/${model.lastModified.month}/${model.lastModified.year}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors:
                                model.engine == InferenceEngineType.gemma
                                    ? [
                                      Colors.blue.shade50,
                                      Colors.blue.shade100,
                                    ]
                                    : [
                                      Colors.green.shade50,
                                      Colors.green.shade100,
                                    ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                model.engine == InferenceEngineType.gemma
                                    ? Colors.blue.shade200
                                    : Colors.green.shade200,
                          ),
                        ),
                        child: Text(
                          '${model.engine.name.toUpperCase()} Engine',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color:
                                model.engine == InferenceEngineType.gemma
                                    ? Colors.blue.shade700
                                    : Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrentlyLoaded)
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check, color: Colors.white, size: 16),
                  ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _deleteLocalModel(model),
                  icon: Icon(
                    Icons.delete,
                    size: 16,
                    color: Colors.red.shade600,
                  ),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: Colors.red.shade600),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed:
                      isCurrentlyLoaded ? null : () => _loadLocalModel(model),
                  icon: Icon(
                    isCurrentlyLoaded ? Icons.check : Icons.play_arrow,
                    size: 16,
                  ),
                  label: Text(
                    isCurrentlyLoaded ? 'Loaded' : 'Load',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isCurrentlyLoaded ? Colors.grey : Colors.green.shade600,
                    foregroundColor: Colors.white,
                    elevation: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(ModelInfo model) {
    final predictedEngine = ModelDetector.instance.detectEngine(
      model.compatibleFiles.isNotEmpty
          ? model.compatibleFiles.first.filename
          : model.name,
    );

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  predictedEngine == InferenceEngineType.gemma
                      ? [Colors.blue.shade300, Colors.blue.shade600]
                      : [Colors.green.shade300, Colors.green.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            predictedEngine == InferenceEngineType.gemma
                ? Icons.psychology
                : Icons.memory,
            color: Colors.white,
            size: 24,
          ),
        ),
        title: Text(
          model.name,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.download, size: 14, color: Colors.grey.shade600),
                SizedBox(width: 4),
                Text(
                  '${_formatNumber(model.downloads)} downloads',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors:
                          predictedEngine == InferenceEngineType.gemma
                              ? [Colors.blue.shade50, Colors.blue.shade100]
                              : [Colors.green.shade50, Colors.green.shade100],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          predictedEngine == InferenceEngineType.gemma
                              ? Colors.blue.shade200
                              : Colors.green.shade200,
                    ),
                  ),
                  child: Text(
                    '${predictedEngine.name.toUpperCase()} Engine',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color:
                          predictedEngine == InferenceEngineType.gemma
                              ? Colors.blue.shade700
                              : Colors.green.shade700,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                if (model.ggufFiles.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'GGUF',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                if (model.tfliteFiles.isNotEmpty) ...[
                  SizedBox(width: 4),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'TFLite',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    model.description.isNotEmpty
                        ? model.description
                        : 'No description available',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.folder, color: Colors.blue.shade600, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Available Files (${model.compatibleFiles.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                if (model.compatibleFiles.isEmpty)
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: Colors.orange.shade600,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No compatible files available',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...model.compatibleFiles
                      .take(5)
                      .map((file) => _buildFileCard(model, file)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(ModelInfo model, ModelFile file) {
    final downloadKey = '${model.id}_${file.filename}';
    final isDownloaded = _isModelDownloaded(model.id, file.filename);
    final isCurrentlyDownloading = _isDownloading[downloadKey] ?? false;
    final downloadProgress = _downloadProgress[downloadKey] ?? 0.0;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              isDownloaded
                  ? [Colors.green.shade50, Colors.green.shade100]
                  : [Colors.grey.shade50, Colors.grey.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDownloaded ? Colors.green.shade300 : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file,
                          size: 16,
                          color:
                              isDownloaded
                                  ? Colors.green.shade600
                                  : Colors.grey.shade600,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            file.filename,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color:
                                  isDownloaded
                                      ? Colors.green.shade800
                                      : Colors.grey.shade800,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                file.fileType == 'GGUF'
                                    ? Colors.green.shade100
                                    : Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            file.fileType,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color:
                                  file.fileType == 'GGUF'
                                      ? Colors.green.shade700
                                      : Colors.blue.shade700,
                            ),
                          ),
                        ),
                        if (isDownloaded) ...[
                          SizedBox(width: 6),
                          Container(
                            padding: EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.storage,
                          size: 12,
                          color: Colors.grey.shade600,
                        ),
                        SizedBox(width: 4),
                        Text(
                          file.size > 0 ? file.sizeFormatted : 'Size unknown',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              if (isCurrentlyDownloading)
                Container(
                  width: 120,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Downloading',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${(downloadProgress * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: downloadProgress,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              else if (isDownloaded)
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final appDir = await getApplicationDocumentsDirectory();
                      final sanitizedModelId = model.id.replaceAll('/', '_');
                      final modelPath =
                          '${appDir.path}/models/${sanitizedModelId}_${file.filename}';

                      _logDebug(
                        '🔄 Loading existing model: ${file.filename}',
                        category: 'LOAD',
                      );
                      _showSnackBar('Loading model into memory...');

                      await _loadModelWithProperConfig(modelPath, model.name);

                      setState(() {
                        _loadedModelPath = modelPath;
                        _selectedModelName = model.name;
                        _activeEngine = LLMToolkit.instance.activeEngine;
                      });

                      _showSnackBar(
                        '✅ Model loaded successfully!',
                        isSuccess: true,
                      );
                    } catch (e) {
                      _logError(
                        '❌ Error loading existing model',
                        e,
                        category: 'LOAD',
                      );
                      _showSnackBar('❌ Error loading model: $e', isError: true);
                    }
                  },
                  icon: Icon(Icons.play_arrow, size: 16),
                  label: Text(
                    'Load',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    elevation: 2,
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _downloadAndLoadModel(model, file.filename),
                  icon: Icon(Icons.download, size: 16),
                  label: Text(
                    'Download',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    elevation: 2,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  Widget _buildDebugControls() {
    return Container(
      margin: EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.bug_report, color: Colors.orange.shade600, size: 20),
          SizedBox(width: 8),
          Text(
            'Debug Mode',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade700,
            ),
          ),
          Spacer(),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _showDebugPanel = !_showDebugPanel;
              });
            },
            icon: Icon(
              _showDebugPanel ? Icons.visibility_off : Icons.visibility,
              size: 16,
            ),
            label: Text(_showDebugPanel ? 'Hide Logs' : 'Show Logs'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'LLM Model Browser',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: Icon(Icons.search), text: 'Search'),
            Tab(icon: Icon(Icons.star), text: 'Recommended'),
            Tab(icon: Icon(Icons.storage), text: 'Downloaded'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Debug Panel
          if (_showDebugPanel)
            Container(
              height: 200,
              margin: EdgeInsets.all(16),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Debug Logs',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _debugLogs.clear();
                          });
                        },
                        icon: Icon(Icons.clear, color: Colors.white, size: 16),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _debugLogs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _debugLogs[index],
                          style: TextStyle(
                            color: Colors.green.shade300,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Loaded Model Status
          _buildLoadedModelStatus(),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSearchTab(),
                _buildRecommendedTab(),
                _buildDownloadedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Chat Screen and other components
class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    final userMessage = ChatMessage(text: _controller.text, isUser: true);
    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
    });

    final prompt = _controller.text;
    _controller.clear();

    final aiMessage = ChatMessage(text: '', isUser: false);
    setState(() => _messages.add(aiMessage));

    developer.log('Starting chat generation', name: 'llm_toolkit.CHAT');
    developer.log('User prompt: $prompt', name: 'llm_toolkit.CHAT');

    LLMToolkit.instance
        .generateText(prompt, params: GenerationParams.creative())
        .listen(
          (token) {
            setState(() {
              aiMessage.text += token;
            });
          },
          onDone: () {
            setState(() => _isGenerating = false);
            developer.log(
              'Chat generation completed',
              name: 'llm_toolkit.CHAT',
            );
          },
          onError: (error) {
            setState(() {
              aiMessage.text = 'Error: $error';
              _isGenerating = false;
            });
            developer.log(
              'Chat generation error: $error',
              name: 'llm_toolkit.CHAT',
            );
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat'),
            Text(
              'Engine: ${LLMToolkit.instance.activeEngine?.name ?? 'None'}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ChatBubble(message: message);
              },
            ),
          ),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    maxLines: null,
                  ),
                ),
                SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _isGenerating ? null : _sendMessage,
                  mini: true,
                  backgroundColor:
                      _isGenerating ? Colors.grey : Colors.blue.shade600,
                  child:
                      _isGenerating
                          ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                          : Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class ChatMessage {
  String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 8,
          left: message.isUser ? 48 : 0,
          right: message.isUser ? 0 : 48,
        ),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blue.shade600 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: message.isUser ? Radius.circular(4) : null,
            bottomLeft: message.isUser ? null : Radius.circular(4),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
