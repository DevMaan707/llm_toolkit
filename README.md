# 🚀 LLM Toolkit for Flutter

A comprehensive Flutter SDK for running Large Language Models (LLMs) locally on mobile and desktop devices. Supports multiple inference engines including Gemma (TFLite) and Llama (GGUF) with integrated model discovery, download, and chat capabilities.

## ✨ Features

### 🎯 Multi-Engine Support
- **Gemma Engine**: TFLite models with GPU acceleration
- **Llama Engine**: GGUF models with CPU/GPU hybrid processing
- **Auto-Detection**: Automatic engine selection based on model format

### 🔍 Model Discovery & Management
- **HuggingFace Integration**: Search and download models directly
- **Format Support**: GGUF, TFLite, GGML formats
- **Smart Filtering**: Filter by size, compatibility, and popularity
- **Progress Tracking**: Real-time download progress with resumption

### 💬 Chat & Inference
- **Streaming Generation**: Real-time token streaming
- **Multimodal Support**: Text + image input (Gemma models)
- **Configurable Parameters**: Temperature, top-K, context size
- **Memory Management**: Optimized for mobile devices

### 🛠️ Developer Tools
- **Debug Console**: Real-time logging and diagnostics
- **Performance Monitoring**: Memory usage and generation metrics
- **Error Handling**: Comprehensive exception handling
- **Native Library Checks**: Automatic compatibility validation

## 📱 Screenshots

<div align="center">
  <img src="screenshots/model_browser.png" width="250" alt="Model Browser"/>
  <img src="screenshots/chat_interface.png" width="250" alt="Chat Interface"/>
  <img src="screenshots/debug_console.png" width="250" alt="Debug Console"/>
</div>

## 🚀 Quick Start

### 1. Add Dependency

```yaml
dependencies:
  llm_toolkit:
    git:
      url: https://github.com/DevMaan707/llm_toolkit.git
      ref: main
  flutter_gemma: ^0.2.4
  llama_cpp_dart: ^0.1.5
```

### 2. Initialize SDK

```dart
import 'package:llm_toolkit/llm_toolkit.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Initialize LLM Toolkit
    LLMToolkit.instance.initialize(
      huggingFaceApiKey: 'your_hf_token', // Optional
      defaultConfig: InferenceConfig.mobile(),
    );

    return MaterialApp(
      home: YourHomeScreen(),
    );
  }
}
```

### 3. Search & Download Models

```dart
// Search for models
final models = await LLMToolkit.instance.searchModels(
  'gemma 2b',
  limit: 10,
  onlyCompatible: true,
);

// Download a model
final modelPath = await LLMToolkit.instance.downloadModel(
  models.first,
  'model.tflite',
  onProgress: (progress) {
    print('Download: ${(progress * 100).toInt()}%');
  },
);
```

### 4. Load & Generate

```dart
// Load model
await LLMToolkit.instance.loadModel(
  modelPath,
  config: InferenceConfig.mobile(),
);

// Generate text
LLMToolkit.instance.generateText(
  'Tell me about Flutter development',
  params: GenerationParams.creative(),
).listen((token) {
  print(token); // Stream of generated tokens
});
```

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   LLM Toolkit   │    │  Model Providers │    │ Inference Mgr   │
│   (Main SDK)    ├────┤  - HuggingFace   ├────┤ - Gemma Engine  │
│                 │    │  - Local Files   │    │ - Llama Engine  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   UI Widgets    │    │  Model Detector  │    │ Config Manager  │
│ - Model Browser │    │ - Format Detection│    │ - Engine Config │
│ - Chat Interface│    │ - Compatibility  │    │ - Parameters    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🔧 Configuration

### Inference Configurations

```dart
// Mobile optimized
final mobileConfig = InferenceConfig.mobile();

// Desktop optimized
final desktopConfig = InferenceConfig.desktop();

// Multimodal (image + text)
final multimodalConfig = InferenceConfig.multimodal(
  maxTokens: 4096,
  maxNumImages: 1,
);

// Custom configuration
final customConfig = InferenceConfig(
  promptFormat: 'chatml',
  maxTokens: 2048,
  nCtx: 4096,
  preferredBackend: PreferredBackend.gpu,
);
```

### Generation Parameters

```dart
// Creative generation
final creativeParams = GenerationParams.creative();

// Precise generation
final preciseParams = GenerationParams.precise();

// Custom parameters
final customParams = GenerationParams(
  temperature: 0.8,
  topK: 40,
  maxTokens: 512,
  stopSequences: ['</s>', '\n\n'],
);
```

## 📚 Examples

### Complete Chat Implementation

```dart
class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final userMessage = ChatMessage(
      text: _controller.text,
      isUser: true,
    );

    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
    });

    final prompt = _controller.text;
    _controller.clear();

    final aiMessage = ChatMessage(text: '', isUser: false);
    setState(() => _messages.add(aiMessage));

    // Stream generation
    LLMToolkit.instance.generateText(
      prompt,
      params: GenerationParams.creative(),
    ).listen(
      (token) {
        setState(() => aiMessage.text += token);
      },
      onDone: () => setState(() => _isGenerating = false),
      onError: (error) {
        setState(() {
          aiMessage.text = 'Error: $error';
          _isGenerating = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) =>
                ChatBubble(message: _messages[index]),
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }
}
```

### Multimodal Generation

```dart
// Generate response with image
Stream<String> generateWithImage(String prompt, String imagePath) {
  return LLMToolkit.instance.generateMultimodalResponse(
    prompt,
    [imagePath],
    params: GenerationParams(temperature: 0.7),
  );
}

// Usage
generateWithImage(
  'What do you see in this image?',
  '/path/to/image.jpg',
).listen((token) {
  print(token);
});
```

### Model Management

```dart
class ModelManager {
  // Search with filters
  static Future<List<ModelInfo>> searchSmallModels() {
    return LLMToolkit.instance.searchModels(
      'gemma 2b',
      format: ModelFormat.tflite,
      limit: 5,
      onlyCompatible: true,
    );
  }

  // Download with progress
  static Future<String> downloadWithProgress(
    ModelInfo model,
    String filename,
  ) async {
    return LLMToolkit.instance.downloadModel(
      model,
      filename,
      onProgress: (progress) {
        print('Progress: ${(progress * 100).toInt()}%');
      },
    );
  }

  // Load optimal model
  static Future<void> loadOptimalModel(String modelPath) async {
    final config = await _getOptimalConfig();
    await LLMToolkit.instance.loadModel(modelPath, config: config);
  }

  static Future<InferenceConfig> _getOptimalConfig() async {
    // Auto-detect optimal configuration based on device
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final totalMemoryMB = deviceInfo.systemFeatures.length * 512; // Rough estimate

    if (totalMemoryMB < 3000) {
      return InferenceConfig.mobile();
    } else {
      return InferenceConfig.desktop();
    }
  }
}
```

## 🔍 Debugging & Diagnostics

### Debug Console

```dart
// Enable debug mode
LlamaInferenceEngine.setDebugMode(true);

// Get debug status
final status = llamaEngine.getDebugStatus();
print('Model loaded: ${status['isModelLoaded']}');

// Print debug info
llamaEngine.printDebugInfo();

// Check native libraries
final available = await LlamaInferenceEngine.checkNativeLibrariesAvailable();
print('Native libs available: $available');
```

### Performance Monitoring

```dart
// Memory recommendations
final recommendations = await LlamaInferenceEngine.getModelRecommendations();
print('Recommended quantization: ${recommendations['recommendedQuantization']}');
print('Recommended context size: ${recommendations['recommendedNCtx']}');
```

## 🎯 Supported Models

### Gemma Models (TFLite)
- ✅ Gemma 2B/7B IT (Instruction Tuned)
- ✅ Gemma 2 variants
- ✅ Gemma Nano (multimodal)
- ✅ DeepSeek models
- ✅ Phi-3 models

### Llama Models (GGUF)
- ✅ Llama 2/3 (all sizes)
- ✅ Code Llama
- ✅ Mistral models
- ✅ Qwen models
- ✅ Any GGUF compatible model

### Quantization Support
- **GGUF**: Q4_0, Q4_K_M, Q5_K_M, Q6_K, Q8_0
- **TFLite**: Native TensorFlow Lite quantization
- **Recommended**: Q4_K_M for best quality/size ratio

## ⚡ Performance Tips

### Memory Optimization
```dart
// Use smaller context for mobile
final mobileConfig = InferenceConfig(
  nCtx: 1024,        // Smaller context
  maxTokens: 512,    // Limit output
  verbose: false,    // Reduce logging
);

// Monitor memory usage
final memInfo = await LlamaInferenceEngine.getMemoryInfo();
print('Available: ${memInfo['availableMB']}MB');
```

### Model Selection
- **Mobile**: Use Q4_0 or Q4_K_M quantization
- **Desktop**: Use Q5_K_M or Q6_K for better quality
- **RAM < 4GB**: Stick to 2B/3B parameter models
- **RAM > 6GB**: 7B parameter models work well

### Generation Optimization
```dart
// Faster generation
final fastParams = GenerationParams(
  temperature: 0.1,  // More deterministic
  topK: 1,          // Greedy sampling
  maxTokens: 256,   // Shorter responses
);

// Balanced generation
final balancedParams = GenerationParams(
  temperature: 0.7,
  topK: 40,
  maxTokens: 512,
);
```

## 🛠️ Troubleshooting

### Common Issues

**Model not loading:**
```dart
// Check model file integrity
final isValid = await LlamaInferenceEngine.validateGGUFFile(modelPath);
if (!isValid) {
  print('Model file is corrupted, re-download required');
}
```

**Out of memory errors:**
```dart
// Use smaller models or reduce context
final safeConfig = InferenceConfig(
  nCtx: 512,         // Reduce context
  maxTokens: 256,    // Limit output
);
```

**Native library issues:**
```dart
// Check native library availability
final available = await LlamaInferenceEngine.checkNativeLibrariesAvailable();
if (!available) {
  print('Native libraries not found. Check app bundle.');
}
```

### Error Codes

| Error | Description | Solution |
|-------|-------------|----------|
| `InferenceException` | Model loading failed | Check model format and memory |
| `ModelProviderException` | Download/search failed | Check network and API keys |
| `DownloadException` | File download failed | Check storage space and network |
| `VectorStorageException` | RAG operations failed | Check database permissions |

## 📦 Dependencies

### Core Dependencies
```yaml
dependencies:
  flutter_gemma: ^0.2.4      # Gemma inference engine
  llama_cpp_dart: ^0.1.5     # Llama inference engine
  dio: ^5.3.2                # HTTP client
  path_provider: ^2.1.1      # File system access
```

### Optional Dependencies
```yaml
dependencies:
  device_info_plus: ^9.1.0   # Device information
  permission_handler: ^11.0.1 # Storage permissions
  shared_preferences: ^2.2.2  # Settings storage
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone repository
git clone https://github.com/DevMaan707/llm_toolkit.git

# Get dependencies
flutter pub get

# Run example app
cd example
flutter run
```

### Testing

```bash
# Run tests
flutter test

# Run integration tests
flutter test integration_test/
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Flutter Gemma](https://pub.dev/packages/flutter_gemma) - Gemma inference engine
- [Llama.cpp Dart](https://pub.dev/packages/llama_cpp_dart) - Llama inference engine
- [HuggingFace](https://huggingface.co) - Model repository and API
- [Google](https://ai.google.dev/gemma) - Gemma model family

## 📞 Support

- 📧 Email: support@llm-toolkit.dev
- 💬 Discord: [Join our community](https://discord.gg/llm-toolkit)
- 🐛 Issues: [GitHub Issues](https://github.com/DevMaan707/llm_toolkit/issues)
- 📖 Docs: [Full Documentation](https://docs.llm-toolkit.dev)

---

<div align="center">
  <p>Made with ❤️ for the Flutter community</p>
  <p>
    <a href="https://github.com/DevMaan707/llm_toolkit/stargazers">⭐ Star us on GitHub</a> •
    <a href="https://twitter.com/llm_toolkit">🐦 Follow on Twitter</a> •
    <a href="https://pub.dev/packages/llm_toolkit">📦 Pub.dev Package</a>
  </p>
</div>
