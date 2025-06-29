import '../config.dart';

abstract class BaseInferenceEngine {
  Future<void> loadModel(String modelPath, InferenceConfig config);
  Stream<String> generateText(String prompt, GenerationParams params);
  Future<List<double>> generateEmbedding(String text);
  Future<void> unloadModel();
  bool get isModelLoaded;
}
