import 'model_info.dart';
import 'search_query.dart';

abstract class BaseModelProvider {
  Future<List<ModelInfo>> searchModels(SearchQuery query);
  Future<ModelInfo> getModelDetails(String modelId);
  Future<String> downloadModel(
    String modelId,
    String filename, {
    ProgressCallback? onProgress,
  });
  Future<bool> isModelCompatible(String modelId, String filename);
}

typedef ProgressCallback = void Function(double progress);
