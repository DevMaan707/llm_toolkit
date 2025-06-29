import 'package:llm_toolkit/llm_toolkit.dart';
import '../models/app_models.dart';

class RecommendedModelsData {
  static List<RecommendedModel> getModels() {
    return [
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
        features: ['Fast inference', 'Low memory', 'Instruction tuned'],
        difficulty: 'Easy',
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
        features: ['Mobile optimized', 'Very fast', 'Low power'],
        difficulty: 'Easy',
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
        features: ['Multilingual', 'Compact', 'Efficient'],
        difficulty: 'Easy',
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
        features: ['Latest model', 'Safety focused', 'Good reasoning'],
        difficulty: 'Medium',
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
        features: ['Strong reasoning', 'General purpose', 'Well tested'],
        difficulty: 'Medium',
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
        features: ['Code generation', 'Multi-language', 'Debugging help'],
        difficulty: 'Medium',
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
        features: ['Compact', 'Fast coding', 'Multiple languages'],
        difficulty: 'Easy',
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
        features: ['Vision + Text', 'Image analysis', 'Mobile ready'],
        difficulty: 'Advanced',
      ),
    ];
  }
}
