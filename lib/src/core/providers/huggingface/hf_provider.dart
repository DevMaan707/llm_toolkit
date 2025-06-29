import 'package:dio/dio.dart' as Dio;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../../../llm_toolkit.dart';
import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../base_provider.dart';
import '../../model_info.dart';
import '../../search_query.dart';

class HuggingFaceProvider extends BaseModelProvider {
  final Dio.Dio _dio;
  final String? _apiKey;

  HuggingFaceProvider({String? apiKey})
    : _apiKey = apiKey,
      _dio = Dio.Dio(
        Dio.BaseOptions(
          baseUrl: 'https://huggingface.co/api',
          headers: apiKey != null ? {'Authorization': 'Bearer $apiKey'} : {},
          connectTimeout: Duration(seconds: 30),
          receiveTimeout: Duration(seconds: 30),
        ),
      );

  @override
  Future<List<ModelInfo>> searchModels(SearchQuery query) async {
    try {
      print('Searching for: ${query.searchTerm}');

      // Search for both GGUF and TFLite models
      final searches = [
        '${query.searchTerm} gguf',
        '${query.searchTerm} tflite',
        query.searchTerm, // Also search without format suffix
      ];

      List<ModelInfo> allModels = [];

      for (String searchTerm in searches) {
        try {
          final response = await _dio.get(
            '/models',
            queryParameters: {
              'search': searchTerm,
              'sort': 'downloads',
              'direction': -1,
              'limit': query.limit,
            },
          );

          print(
            'API Response status: ${response.statusCode} for "$searchTerm"',
          );
          print('Found ${(response.data as List).length} total models');

          if (response.data == null || response.data is! List) {
            continue;
          }

          // Get detailed info for each model
          for (final modelData in (response.data as List).take(
            query.limit ~/ searches.length,
          )) {
            try {
              final modelId = modelData['id'] as String;

              // Skip if we already have this model
              if (allModels.any((m) => m.id == modelId)) continue;

              final detailResponse = await _dio.get('/models/$modelId');
              final modelInfo = _parseModelInfo(detailResponse.data);

              // Accept both GGUF and TFLite models
              if (modelInfo.ggufFiles.isNotEmpty ||
                  modelInfo.tfliteFiles.isNotEmpty) {
                allModels.add(modelInfo);
                print(
                  '✅ Added ${modelInfo.name} with ${modelInfo.files.length} files',
                );
              }
            } catch (e) {
              print('Error fetching details for model: $e');
              continue;
            }
          }
        } catch (e) {
          print('Search failed for "$searchTerm": $e');
          continue;
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

      print('Found ${sortedModels.length} compatible models total');
      return sortedModels.take(query.limit).toList();
    } catch (e) {
      print('Search error: $e');
      throw ModelProviderException('Failed to search models: $e');
    }
  }

  @override
  Future<ModelInfo> getModelDetails(String modelId) async {
    try {
      final response = await _dio.get('/models/$modelId');
      return _parseModelInfo(response.data);
    } catch (e) {
      throw ModelProviderException('Failed to get model details: $e');
    }
  }

  @override
  Future<String> downloadModel(
    String modelId,
    String filename, {
    ProgressCallback? onProgress,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final sanitizedModelId = modelId.replaceAll('/', '_');
    final modelPath = '${modelsDir.path}/${sanitizedModelId}_$filename';
    final modelFile = File(modelPath);

    if (await modelFile.exists()) {
      return modelPath;
    }

    try {
      final downloadUrl =
          'https://huggingface.co/$modelId/resolve/main/$filename';

      print('Starting download from: $downloadUrl');

      await _dio.download(
        downloadUrl,
        modelPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            final progress = received / total;
            print('Download progress: ${(progress * 100).toInt()}%');
            onProgress(progress);
          }
        },
        options: Dio.Options(
          receiveTimeout: Duration(hours: 2),
          sendTimeout: Duration(minutes: 30),
          headers: _apiKey != null ? {'Authorization': 'Bearer $_apiKey'} : {},
        ),
      );

      return modelPath;
    } catch (e) {
      if (await modelFile.exists()) {
        await modelFile.delete();
      }
      throw ModelProviderException('Failed to download model: $e');
    }
  }

  @override
  Future<bool> isModelCompatible(String modelId, String filename) async {
    final lowerFilename = filename.toLowerCase();
    return lowerFilename.endsWith('.gguf') ||
        lowerFilename.endsWith('.ggml') ||
        lowerFilename.endsWith('.tflite');
  }

  ModelInfo _parseModelInfo(Map<String, dynamic> json) {
    final filesData = json['siblings'] as List? ?? json['files'] as List? ?? [];

    final files =
        filesData.where((file) => file['rfilename'] != null).map((file) {
          final filename = file['rfilename'] as String;
          final size =
              (file['size'] as num?)?.toInt() ??
              (file['filesize'] as num?)?.toInt() ??
              (file['lfs']?['size'] as num?)?.toInt() ??
              0;

          return ModelFile(
            filename: filename,
            size: size,
            downloadUrl:
                'https://huggingface.co/${json['id']}/resolve/main/$filename',
          );
        }).toList();

    return ModelInfo(
      id: json['id'] ?? '',
      name: (json['id'] as String?)?.split('/').last ?? 'Unknown Model',
      description: json['description'] ?? 'No description available',
      tags: List<String>.from(json['tags'] ?? []),
      downloads: json['downloads'] as int? ?? 0,
      files: files,
      provider: 'huggingface',
    );
  }
}
