import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import 'package:path_provider/path_provider.dart';
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

class ModelBrowserScreen extends StatefulWidget {
  @override
  _ModelBrowserScreenState createState() => _ModelBrowserScreenState();
}

class _ModelBrowserScreenState extends State<ModelBrowserScreen> {
  List<ModelInfo> _models = [];
  bool _isLoading = false;
  String? _loadedModelPath;
  String? _selectedModelName;
  InferenceEngineType? _activeEngine;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Download state management
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  final Set<String> _downloadedModels = {};

  // Debug state management
  bool _debugMode = true;
  final List<String> _debugLogs = [];
  bool _showDebugPanel = false;

  @override
  void initState() {
    super.initState();
    _initializeToolkit();
    _loadDownloadedModels();
    _loadFeaturedModels();
  }

  void _initializeToolkit() {
    _logDebug('🚀 Initializing LLM Toolkit...', category: 'INIT');

    try {
      LLMToolkit.instance.initialize(
        huggingFaceApiKey: '..',
        defaultConfig: InferenceConfig.mobile(),
      );
      _logDebug('✅ LLM Toolkit initialized successfully', category: 'INIT');
    } catch (e) {
      _logError('❌ Failed to initialize LLM Toolkit', e, category: 'INIT');
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
        _debugLogs.removeAt(0); // Keep only last 100 logs
      }
    });

    // Also log to developer console
    developer.log(
      message,
      name: 'llm_toolkit.$category',
      error: data != null ? data.toString() : null,
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

      if (await modelsDir.exists()) {
        final files = await modelsDir.list().toList();
        int modelCount = 0;

        for (final file in files) {
          if (file is File &&
              (file.path.endsWith('.gguf') || file.path.endsWith('.tflite'))) {
            final fileName = file.path.split('/').last;
            _downloadedModels.add(fileName);
            modelCount++;
          }
        }

        _logDebug('✅ Found $modelCount downloaded models', category: 'MODELS');
      } else {
        _logDebug('📁 Models directory does not exist yet', category: 'MODELS');
      }
    } catch (e) {
      _logError('❌ Error loading downloaded models', e, category: 'MODELS');
    }
  }

  bool _isModelDownloaded(String modelId, String filename) {
    final sanitizedModelId = modelId.replaceAll('/', '_');
    final expectedFileName = '${sanitizedModelId}_$filename';
    return _downloadedModels.contains(expectedFileName);
  }

  Future<void> _loadFeaturedModels() async {
    _logDebug('🔍 Loading featured models...', category: 'SEARCH');
    setState(() => _isLoading = true);

    try {
      final searches = [
        'MaziyarPanahi/gemma',
        'MaziyarPanahi/llama',
        'MaziyarPanahi/phi',
        'google/gemma tflite',
        'microsoft/phi tflite',
        'lmstudio-community',
        'bartowski',
      ];

      List<ModelInfo> allModels = [];
      int totalSearches = searches.length;
      int completedSearches = 0;

      for (String searchTerm in searches) {
        try {
          _logDebug('🔍 Searching for: $searchTerm', category: 'SEARCH');

          final models = await LLMToolkit.instance.searchModels(
            searchTerm,
            limit: 3,
          );

          allModels.addAll(models);
          completedSearches++;

          _logDebug(
            '✅ Found ${models.length} models for "$searchTerm" ($completedSearches/$totalSearches)',
            category: 'SEARCH',
          );
        } catch (e) {
          completedSearches++;
          _logError(
            '❌ Error searching for $searchTerm ($completedSearches/$totalSearches)',
            e,
            category: 'SEARCH',
          );
        }
      }

      // Remove duplicates and sort by downloads
      final uniqueModels = <String, ModelInfo>{};
      for (final model in allModels) {
        if (!uniqueModels.containsKey(model.id)) {
          uniqueModels[model.id] = model;
        }
      }

      final sortedModels =
          uniqueModels.values.toList()
            ..sort((a, b) => b.downloads.compareTo(a.downloads));

      setState(() => _models = sortedModels.take(15).toList());

      if (_models.isEmpty) {
        _logDebug('⚠️ No compatible models found', category: 'SEARCH');
        _showSnackBar(
          'No compatible models found. Try searching manually.',
          isError: true,
        );
      } else {
        _logDebug(
          '✅ Loaded ${_models.length} models successfully',
          category: 'SEARCH',
        );
        _showSnackBar(
          'Loaded ${_models.length} models successfully',
          isSuccess: true,
        );
      }
    } catch (e) {
      _logError('❌ Error loading featured models', e, category: 'SEARCH');
      _showSnackBar('Error loading models: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchModels() async {
    if (_searchQuery.trim().isEmpty) {
      _loadFeaturedModels();
      return;
    }

    _logDebug('🔍 Starting search for: "$_searchQuery"', category: 'SEARCH');
    setState(() => _isLoading = true);

    try {
      final models = await LLMToolkit.instance.searchModels(
        _searchQuery,
        limit: 15,
      );
      setState(() => _models = models);

      if (models.isEmpty) {
        _logDebug('⚠️ No models found for "$_searchQuery"', category: 'SEARCH');
        _showSnackBar('No models found for "$_searchQuery"', isError: true);
      } else {
        _logDebug(
          '✅ Found ${models.length} models for "$_searchQuery"',
          category: 'SEARCH',
        );
      }
    } catch (e) {
      _logError('❌ Error searching models', e, category: 'SEARCH');
      _showSnackBar('Error searching models: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
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
          } else if ((progress * 100).toInt() % 10 == 0) {
            _logDebug(
              '📊 Download progress: ${(progress * 100).toInt()}%',
              category: 'DOWNLOAD',
            );
          }
        },
      );

      final sanitizedModelId = model.id.replaceAll('/', '_');
      final downloadedFileName = '${sanitizedModelId}_$filename';
      _downloadedModels.add(downloadedFileName);

      setState(() {
        _isDownloading[downloadKey] = false;
        _downloadProgress[downloadKey] = 1.0;
      });

      _logDebug('🔄 Starting model loading process...', category: 'LOAD');
      _showSnackBar('Loading model into memory...');

      await _loadModelWithProperConfig(modelPath, model);

      setState(() {
        _loadedModelPath = modelPath;
        _selectedModelName = model.name;
        _activeEngine = LLMToolkit.instance.activeEngine;
      });

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
    ModelInfo model,
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
        _logDebug(
          '🔧 Gemma model type: ${modelType?.name ?? 'default'}',
          category: 'LOAD',
        );

        config = InferenceConfig(
          modelType: modelType,
          preferredBackend: PreferredBackend.gpu,
          maxTokens: 512,
          supportImage: false,
          maxNumImages: 1,
        );
      } else {
        _logDebug('🔧 Llama configuration: nCtx=2048', category: 'LOAD');
        config = InferenceConfig(nCtx: 2048, verbose: false);
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

  Future<void> _checkNativeLibraries() async {
    _logDebug(
      '🔍 Checking native libraries availability...',
      category: 'NATIVE',
    );

    try {
      final available =
          await LlamaInferenceEngine.checkNativeLibrariesAvailable();

      if (available) {
        _logDebug(
          '✅ Native libraries are available and working',
          category: 'NATIVE',
        );
        _showSnackBar('Native libraries: Available ✅', isSuccess: true);
      } else {
        _logDebug('❌ Native libraries are not available', category: 'NATIVE');
        _showSnackBar('Native libraries: Not Available ❌', isError: true);
      }
    } catch (e) {
      _logError('❌ Error checking native libraries', e, category: 'NATIVE');
      _showSnackBar('Error checking libraries: $e', isError: true);
    }
  }

  void _clearLogs() {
    setState(() {
      _debugLogs.clear();
    });
    _logDebug('🧹 Debug logs cleared', category: 'DEBUG');
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

  Widget _buildDebugControls() {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Debug Controls',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Spacer(),
                Switch(
                  value: _debugMode,
                  onChanged: (value) {
                    setState(() => _debugMode = value);
                    _logDebug(
                      'Debug mode ${value ? 'enabled' : 'disabled'}',
                      category: 'DEBUG',
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _checkNativeLibraries,
                  icon: Icon(Icons.check_circle, size: 16),
                  label: Text('Check Libraries'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _clearLogs,
                  icon: Icon(Icons.clear, size: 16),
                  label: Text('Clear Logs'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _showDebugPanel = !_showDebugPanel);
                  },
                  icon: Icon(
                    _showDebugPanel ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                  ),
                  label: Text(_showDebugPanel ? 'Hide Logs' : 'Show Logs'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            if (_showDebugPanel) ...[
              SizedBox(height: 16),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.terminal, color: Colors.green, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Debug Console (${_debugLogs.length} logs)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.all(8),
                        itemCount: _debugLogs.length,
                        reverse: true, // Show newest logs at bottom
                        itemBuilder: (context, index) {
                          final log = _debugLogs[_debugLogs.length - 1 - index];
                          Color textColor = Colors.green;

                          if (log.contains('[ERROR]'))
                            textColor = Colors.red;
                          else if (log.contains('[INIT]'))
                            textColor = Colors.blue;
                          else if (log.contains('[SEARCH]'))
                            textColor = Colors.yellow;
                          else if (log.contains('[DOWNLOAD]'))
                            textColor = Colors.orange;
                          else if (log.contains('[LOAD]'))
                            textColor = Colors.purple;
                          else if (log.contains('[NATIVE]'))
                            textColor = Colors.cyan;

                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              log,
                              style: TextStyle(
                                color: textColor,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

                      await _loadModelWithProperConfig(modelPath, model);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'LLM Model Browser',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade700, Colors.blue.shade900],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Debug Controls
                _buildDebugControls(),

                // Search Bar
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16),
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
                      hintText:
                          'Search models (GGUF, TFLite, gemma, llama, phi)...',
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.blue.shade600,
                      ),
                      suffixIcon:
                          _searchController.text.isNotEmpty
                              ? IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: Colors.grey.shade600,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                  _loadFeaturedModels();
                                },
                              )
                              : IconButton(
                                icon: Icon(
                                  Icons.tune,
                                  color: Colors.blue.shade600,
                                ),
                                onPressed: () => _searchModels(),
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
                    onSubmitted: (value) => _searchModels(),
                  ),
                ),

                // Loaded Model Status
                if (_loadedModelPath != null) ...[
                  SizedBox(height: 16),
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 16),
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
                          child: Icon(
                            Icons.check,
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
                                'Model Ready',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '$_selectedModelName (${_activeEngine?.name})',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(),
                              ),
                            );
                          },
                          icon: Icon(Icons.chat_bubble, size: 18),
                          label: Text(
                            'Chat',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            elevation: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                SizedBox(height: 16),
              ],
            ),
          ),

          // Models List
          if (_isLoading)
            SliverToBoxAdapter(
              child: Container(
                height: 300,
                child: Center(
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
                ),
              ),
            )
          else if (_models.isEmpty)
            SliverToBoxAdapter(
              child: Container(
                height: 300,
                child: Center(
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
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildModelCard(_models[index]),
                childCount: _models.length,
              ),
            ),

          // Bottom spacing
          SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton:
          _models.isNotEmpty && !_isLoading
              ? FloatingActionButton.extended(
                onPressed: _loadFeaturedModels,
                icon: Icon(Icons.refresh),
                label: Text(
                  'Refresh',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                elevation: 4,
              )
              : null,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// Chat Screen remains the same as in your original code...
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

    // Enhanced logging for chat generation
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
              'Engine: ${LLMToolkit.instance.activeEngine?.name}',
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
}

class ChatMessage {
  String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({required this.message});

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
