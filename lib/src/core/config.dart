import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';

class InferenceConfig {
  final String promptFormat;

  // Gemma-specific configurations
  final ModelType? modelType;
  final PreferredBackend? preferredBackend;
  final int? maxTokens;
  final bool? supportImage;
  final int? maxNumImages;

  // Llama-specific configurations
  final int? nCtx;
  final bool? verbose;

  const InferenceConfig({
    this.promptFormat = 'chatml',
    this.modelType,
    this.preferredBackend,
    this.maxTokens,
    this.supportImage,
    this.maxNumImages,
    this.nCtx,
    this.verbose,
  });

  factory InferenceConfig.defaultConfig() => const InferenceConfig();

  factory InferenceConfig.mobile() => const InferenceConfig(
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 512,
    supportImage: false,
    nCtx: 2048,
    verbose: false,
  );

  factory InferenceConfig.desktop() => const InferenceConfig(
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 1024,
    supportImage: false,
    nCtx: 4096,
    verbose: false,
  );

  // Use only available ModelType values
  factory InferenceConfig.multimodal({
    ModelType? modelType,
    int? maxTokens,
    int? maxNumImages,
  }) => InferenceConfig(
    modelType:
        modelType ?? ModelType.gemmaIt, // Only available option for multimodal
    preferredBackend: PreferredBackend.gpu,
    maxTokens: maxTokens ?? 4096,
    supportImage: true,
    maxNumImages: maxNumImages ?? 1,
  );

  factory InferenceConfig.deepSeek({int? maxTokens}) => InferenceConfig(
    modelType: ModelType.deepSeek, // For DeepSeek models specifically
    preferredBackend: PreferredBackend.gpu,
    maxTokens: maxTokens ?? 1024,
    supportImage: false,
  );
}

// lib/src/core/config.dart - Update your GenerationParams
class GenerationParams {
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? repeatPenalty;
  final List<String>? stopSequences;
  final int? seed;
  final bool? stream;

  const GenerationParams({
    this.maxTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.repeatPenalty,
    this.stopSequences,
    this.seed,
    this.stream,
  });

  static GenerationParams creative() => const GenerationParams(
    maxTokens: 2048,
    temperature: 0.8,
    topP: 0.9,
    topK: 40,
    repeatPenalty: 1.1,
    stream: true,
  );

  static GenerationParams balanced() => const GenerationParams(
    maxTokens: 1024,
    temperature: 0.7,
    topP: 0.85,
    topK: 30,
    repeatPenalty: 1.05,
    stream: true,
  );

  static GenerationParams precise() => const GenerationParams(
    maxTokens: 512,
    temperature: 0.3,
    topP: 0.7,
    topK: 20,
    repeatPenalty: 1.0,
    stream: true,
  );

  static GenerationParams longForm() => const GenerationParams(
    maxTokens: 4096,
    temperature: 0.7,
    topP: 0.9,
    topK: 35,
    repeatPenalty: 1.05,
    stream: true,
  );

  static GenerationParams custom({
    int maxTokens = 2048,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 30,
    double repeatPenalty = 1.05,
    List<String>? stopSequences,
  }) => GenerationParams(
    maxTokens: maxTokens,
    temperature: temperature,
    topP: topP,
    topK: topK,
    repeatPenalty: repeatPenalty,
    stopSequences: stopSequences,
    stream: true,
  );
}
