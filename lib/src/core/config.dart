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

class GenerationParams {
  final int? maxTokens;
  final List<String>? stopSequences;

  // Gemma-specific parameters
  final double? temperature;
  final int? randomSeed;
  final int? topK;

  const GenerationParams({
    this.maxTokens,
    this.stopSequences,
    this.temperature,
    this.randomSeed,
    this.topK,
  });

  factory GenerationParams.defaultParams() => const GenerationParams();

  factory GenerationParams.creative() =>
      const GenerationParams(temperature: 1.0, topK: 40, randomSeed: 42);

  factory GenerationParams.precise() =>
      const GenerationParams(temperature: 0.1, topK: 1, randomSeed: 1);
}
