# LLM Toolkit

A comprehensive Flutter SDK for on-device Large Language Models, Speech Recognition, and RAG (Retrieval-Augmented Generation) capabilities.

## 🚀 Features

- **Multi-Engine Support**: Llama (GGUF), Gemma (TFLite), Generic TFLite models
- **Speech Recognition**: TFLite ASR with Whisper support
- **Model Discovery**: Search and download models from Hugging Face
- **RAG Support**: Retrieval-Augmented Generation with embeddings
- **Streaming Inference**: Real-time text generation and speech transcription
- **Cross-Platform**: iOS, Android, Windows, macOS, Linux
- **Memory Optimized**: Adaptive configurations for mobile devices

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  llm_toolkit: ^1.0.0

  # Required dependencies
  flutter_gemma: ^0.2.0
  llama_cpp_dart: ^0.1.0
  tflite_flutter: ^0.10.0
  record: ^5.0.0
  path_provider: ^2.0.0
  dio: ^5.0.0
  fftea: ^2.0.0
```

## 🔧 Setup

### Android
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

### iOS
Add to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for speech recognition</string>
```

## 🚀 Quick Start

### 1. Initialize the Toolkit

```dart
import 'package:llm_toolkit/llm_toolkit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize with optional Hugging Face API key
  LLMToolkit.instance.initialize(
    huggingFaceApiKey: 'your_hf_token_here', // Optional
    defaultConfig: InferenceConfig.mobile(),
  );

  runApp(MyApp());
}
```

### 2. Search and Download Models

```dart
class ModelManager {
  Future<void> searchAndDownloadModel() async {
    try {
      // Search for models
      final models = await LLMToolkit.instance.searchModels(
        'Llama 3.2 1B',
        limit: 10,
        onlyCompatible: true,
      );

      print('Found ${models.length} models');

      if (models.isNotEmpty) {
        final model = models.first;
        final ggufFiles = model.ggufFiles;

        if (ggufFiles.isNotEmpty) {
          // Download the model
          final modelPath = await LLMToolkit.instance.downloadModel(
            model,
            ggufFiles.first.filename,
            onProgress: (progress) {
              print('Download progress: ${(progress * 100).toInt()}%');
            },
          );

          print('Model downloaded to: $modelPath');
        }
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
```

## 💬 Text Generation

### Basic Text Generation

```dart
class TextGenerationExample {
  Future<void> basicGeneration() async {
    try {
      // Load a GGUF model (automatically detects Llama engine)
      await LLMToolkit.instance.loadModel(
        '/path/to/your/model.gguf',
        config: InferenceConfig.mobile(),
      );

      // Generate text with streaming
      final prompt = "What is artificial intelligence?";

      await for (final chunk in LLMToolkit.instance.generateText(
        prompt,
        params: GenerationParams.balanced(),
      )) {
        print(chunk); // Print each token as it's generated
      }

    } catch (e) {
      print('Generation error: $e');
    }
  }

  Future<void> customGeneration() async {
    // Custom generation parameters
    final params = GenerationParams.custom(
      maxTokens: 1000,
      temperature: 0.8,
      topP: 0.9,
      topK: 40,
      repeatPenalty: 1.1,
    );

    await for (final chunk in LLMToolkit.instance.generateText(
      "Write a short story about a robot:",
      params: params,
    )) {
      // Handle each generated token
      setState(() {
        generatedText += chunk;
      });
    }
  }
}
```

### Chat Interface

```dart
class ChatExample {
  InferenceModel? chatInstance;

  Future<void> setupChat() async {
    // Load Gemma model for chat
    await LLMToolkit.instance.loadModel(
      '/path/to/gemma-model.tflite',
      config: InferenceConfig.mobile(),
    );

    // Create chat instance
    chatInstance = await LLMToolkit.instance.createChatInstance(
      temperature: 0.7,
      topK: 30,
    );
  }

  Future<String> sendMessage(String message) async {
    if (chatInstance == null) return '';

    final session = await chatInstance!.createSession();

    // Add user message
    await session.addQueryChunk(
      Message.text(text: message, isUser: true)
    );

    String response = '';
    await for (final chunk in session.getResponseAsync()) {
      response += chunk;
    }

    await session.close();
    return response;
  }
}
```

### Multimodal Generation (Gemma with Images)

```dart
class MultimodalExample {
  Future<void> analyzeImage() async {
    // Load multimodal Gemma model
    await LLMToolkit.instance.loadModel(
      '/path/to/gemma-multimodal.tflite',
      config: InferenceConfig.multimodal(
        maxTokens: 2048,
        maxNumImages: 1,
      ),
    );

    // Generate response with image
    final imagePaths = ['/path/to/image.jpg'];
    final prompt = "What do you see in this image?";

    await for (final chunk in LLMToolkit.instance.generateMultimodalResponse(
      prompt,
      imagePaths,
      params: GenerationParams.creative(),
    )) {
      print(chunk);
    }
  }
}
```

## 🎤 Speech Recognition (ASR)

### Basic Speech Recognition

```dart
import 'package:llm_toolkit/src/services/asr_service.dart';

class SpeechExample {
  final ASRService _asrService = ASRService();

  Future<void> setupASR() async {
    // Initialize with Whisper model
    await _asrService.initialize(
      '/path/to/whisper-model.tflite',
      config: ASRConfig.mobile(),
    );
  }

  Future<String> transcribeFile() async {
    // Transcribe audio file
    final transcription = await _asrService.transcribeFile(
      '/path/to/audio.wav'
    );
    return transcription;
  }

  Future<String> recordAndTranscribe() async {
    // Record for 10 seconds then transcribe
    final transcription = await _asrService.recordAndTranscribe(
      Duration(seconds: 10)
    );
    return transcription;
  }
}
```

### Real-time Speech Recognition

```dart
class RealtimeSpeechExample {
  final ASRService _asrService = ASRService();
  StreamSubscription<String>? _subscription;

  Future<void> startStreamingRecognition() async {
    await _asrService.initialize(
      '/path/to/whisper-model.tflite',
      config: ASRConfig.streaming(),
    );

    // Start streaming transcription
    _subscription = _asrService.startStreamingTranscription().listen(
      (transcription) {
        print('Real-time: $transcription');
        // Update UI with live transcription
      },
      onError: (error) {
        print('Streaming error: $error');
      },
    );
  }

  Future<void> stopStreamingRecognition() async {
    await _asrService.stopStreamingTranscription();
    _subscription?.cancel();
  }
}
```

### Voice Activity Detection (VAD)

```dart
class VADExample {
  Future<String> recordWithVAD() async {
    final asrService = ASRService();
    await asrService.initialize('/path/to/model.tflite');

    // Record with automatic silence detection
    final transcription = await asrService.recordWithVAD(
      maxDuration: Duration(seconds: 30),
      silenceTimeout: Duration(seconds: 3),
      silenceThreshold: 0.01,
    );

    return transcription;
  }
}
```

## 🔍 RAG (Retrieval-Augmented Generation)

### Setup RAG Engine

```dart
import 'package:llm_toolkit/src/core/rag/rag_engine.dart';
import 'package:llm_toolkit/src/core/rag/engines/llama_rag_engine.dart';

class RAGExample {
  late RagEngine ragEngine;

  Future<void> setupRAG() async {
    ragEngine = LlamaRagEngine(
      embeddingModelPath: '/path/to/embedding-model.gguf',
      llmModelPath: '/path/to/llm-model.gguf',
      libraryPath: 'libllama.so',
    );

    await ragEngine.initialize();
  }

  Future<void> addDocuments() async {
    // Add documents to the knowledge base
    await ragEngine.addDocument(
      'doc1',
      'Flutter is Google\'s UI toolkit for building natively compiled applications...',
      {'source': 'flutter_docs', 'category': 'framework'},
    );

    await ragEngine.addDocument(
      'doc2',
      'Dart is a client-optimized language for fast apps on any platform...',
      {'source': 'dart_docs', 'category': 'language'},
    );
  }

  Future<RagResponse> askQuestion(String question) async {
    final config = RagConfig(
      maxRelevantChunks: 3,
      maxTokens: 500,
      temperature: 0.7,
      similarityThreshold: 0.7,
    );

    final response = await ragEngine.query(question, config: config);

    print('Answer: ${response.answer}');
    print('Confidence: ${response.confidence}');
    print('Sources: ${response.relevantChunks.length}');

    return response;
  }
}
```

## 🛠 Advanced Configuration

### Engine-Specific Configurations

```dart
class AdvancedConfig {
  // Llama/GGUF Configuration
  static InferenceConfig llamaConfig() => InferenceConfig(
    nCtx: 4096,        // Context length
    verbose: false,     // Debug output
  );

  // Gemma Configuration
  static InferenceConfig gemmaConfig() => InferenceConfig(
    modelType: ModelType.gemmaIt,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 2048,
    supportImage: false,
  );

  // TFLite Configuration
  static InferenceConfig tfliteConfig() => InferenceConfig(
    preferredBackend: PreferredBackend.cpu,
    maxTokens: 1024,
  );

  // ASR Configuration
  static ASRConfig asrConfig() => ASRConfig(
    sampleRate: 16000,
    bitRate: 256000,
    streamingIntervalMs: 500,
    maxTokens: 1024,
    confidenceThreshold: 0.7,
  );
}
```

### Memory Management

```dart
class MemoryManagement {
  Future<void> optimizeForDevice() async {
    // Get device memory info
    final recommendations = await LlamaInferenceEngine.getModelRecommendations();

    print('Available memory: ${recommendations['availableMemoryMB']}MB');
    print('Recommended quantization: ${recommendations['recommendedQuantization']}');
    print('Recommended context: ${recommendations['recommendedNCtx']}');

    // Configure based on device capabilities
    InferenceConfig config;
    if (recommendations['availableMemoryMB'] < 2048) {
      config = InferenceConfig(
        nCtx: 512,
        maxTokens: 256,
        verbose: false,
      );
    } else {
      config = InferenceConfig(
        nCtx: 2048,
        maxTokens: 1024,
        verbose: false,
      );
    }

    await LLMToolkit.instance.loadModel('/path/to/model.gguf', config: config);
  }
}
```

## 🔄 Model Management

### Model Detection and Loading

```dart
class ModelManagement {
  Future<void> autoLoadModel(String modelPath) async {
    // Automatic engine detection
    final engineType = ModelDetector.instance.detectEngine(modelPath);
    print('Detected engine: ${engineType.name}');

    // Load with appropriate configuration
    InferenceConfig config;
    switch (engineType) {
      case InferenceEngineType.llama:
        config = InferenceConfig(nCtx: 2048, verbose: false);
        break;
      case InferenceEngineType.gemma:
        config = InferenceConfig(
          modelType: ModelType.gemmaIt,
          preferredBackend: PreferredBackend.gpu,
        );
        break;
      case InferenceEngineType.tflite:
        config = InferenceConfig(preferredBackend: PreferredBackend.cpu);
        break;
      case InferenceEngineType.tfliteASR:
        // Use ASR service instead
        final asrService = ASRService();
        await asrService.initialize(modelPath);
        return;
      default:
        config = InferenceConfig.defaultConfig();
    }

    await LLMToolkit.instance.loadModel(modelPath, config: config);
  }

  Future<void> switchModels() async {
    // Unload current model
    await LLMToolkit.instance.dispose();

    // Load new model
    await LLMToolkit.instance.loadModel(
      '/path/to/new-model.gguf',
      config: InferenceConfig.mobile(),
    );
  }
}
```

## 📱 UI Components

### Download Progress Widget

```dart
class ModelDownloadScreen extends StatefulWidget {
  @override
  _ModelDownloadScreenState createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  double downloadProgress = 0.0;
  bool isDownloading = false;

  Future<void> downloadModel(ModelInfo model, ModelFile file) async {
    setState(() {
      isDownloading = true;
      downloadProgress = 0.0;
    });

    try {
      final modelPath = await LLMToolkit.instance.downloadModel(
        model,
        file.filename,
        onProgress: (progress) {
          setState(() {
            downloadProgress = progress;
          });
        },
      );

      // Auto-load the model after download
      await LLMToolkit.instance.loadModel(modelPath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model loaded successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Model Download')),
      body: Column(
        children: [
          if (isDownloading)
            LinearProgressIndicator(value: downloadProgress),
          // ... rest of UI
        ],
      ),
    );
  }
}
```

### Chat Interface

```dart
class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;

  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;

    // Add user message
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isGenerating = true;
    });

    // Clear input
    _controller.clear();

    try {
      String response = '';
      await for (final chunk in LLMToolkit.instance.generateText(
        text,
        params: GenerationParams.balanced(),
      )) {
        setState(() {
          response += chunk;
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last = ChatMessage(text: response, isUser: false);
          } else {
            _messages.add(ChatMessage(text: response, isUser: false));
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('LLM Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ListTile(
                  title: Text(message.text),
                  leading: Icon(
                    message.isUser ? Icons.person : Icons.smart_toy,
                  ),
                );
              },
            ),
          ),
          if (_isGenerating) LinearProgressIndicator(),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(hintText: 'Type a message...'),
                    onSubmitted: sendMessage,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () => sendMessage(_controller.text),
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
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}
```

## 🔧 Error Handling

### Comprehensive Error Handling

```dart
class ErrorHandling {
  Future<void> handleInferenceErrors() async {
    try {
      await LLMToolkit.instance.loadModel('/path/to/model.gguf');
    } on InferenceException catch (e) {
      if (e.message.contains('memory')) {
        // Handle memory issues
        print('Memory error: Try a smaller model or reduce context size');
      } else if (e.message.contains('file')) {
        // Handle file issues
        print('File error: Check model path and permissions');
      } else {
        print('Inference error: ${e.message}');
      }
    } on ModelProviderException catch (e) {
      print('Model provider error: ${e.message}');
    } on LLMToolkitException catch (e) {
      print('General toolkit error: ${e.message}');
    } catch (e) {
      print('Unexpected error: $e');
    }
  }

  Future<void> handleASRErrors() async {
    final asrService = ASRService();

    try {
      await asrService.initialize('/path/to/whisper-model.tflite');
    } on InferenceException catch (e) {
      if (e.message.contains('permission')) {
        print('Microphone permission required');
      } else if (e.message.contains('model')) {
        print('ASR model loading failed');
      } else {
        print('ASR error: ${e.message}');
      }
    }
  }
}
```

## 📊 Performance Monitoring

### Monitor Inference Performance

```dart
class PerformanceMonitoring {
  Future<void> monitorPerformance() async {
    // Llama engine debug info
    final llamaEngine = LlamaInferenceEngine();
    llamaEngine.printDebugInfo();

    final status = llamaEngine.getDebugStatus();
    print('Llama status: $status');

    // ASR performance metrics
    final asrService = ASRService();
    final metrics = asrService.getPerformanceMetrics();
    print('ASR metrics: $metrics');

    // Memory recommendations
    final recommendations = await LlamaInferenceEngine.getModelRecommendations();
    print('Memory recommendations: $recommendations');
  }
}
```

## 🚀 Production Best Practices

### 1. Resource Management

```dart
class ResourceManagement {
  @override
  void dispose() {
    // Always dispose resources
    LLMToolkit.instance.dispose();
    super.dispose();
  }

  Future<void> backgroundTask() async {
    try {
      // Your inference code
    } finally {
      // Ensure cleanup even if error occurs
      await LLMToolkit.instance.dispose();
    }
  }
}
```

### 2. Model Validation

```dart
class ModelValidation {
  Future<bool> validateModel(String modelPath) async {
    try {
      // Check if model file exists and is valid
      final isValid = await LlamaInferenceEngine.validateGGUFFile(modelPath);
      return isValid;
    } catch (e) {
      print('Model validation failed: $e');
      return false;
    }
  }
}
```

### 3. Progressive Loading

```dart
class ProgressiveLoading {
  Future<void> loadModelWithFallback(List<String> modelPaths) async {
    for (final modelPath in modelPaths) {
      try {
        await LLMToolkit.instance.loadModel(modelPath);
        print('Successfully loaded: $modelPath');
        return;
      } catch (e) {
        print('Failed to load $modelPath: $e');
        continue;
      }
    }
    throw Exception('No models could be loaded');
  }
}
```

## 📚 API Reference

### Core Classes

- **`LLMToolkit`**: Main singleton class for all operations
- **`InferenceConfig`**: Configuration for model loading
- **`GenerationParams`**: Parameters for text generation
- **`ASRService`**: Speech recognition service
- **`RagEngine`**: RAG functionality interface

### Configuration Classes

- **`ASRConfig`**: ASR-specific configuration
- **`RagConfig`**: RAG-specific configuration
- **`ModelInfo`**: Model metadata and files
- **`SearchQuery`**: Model search parameters

### Exception Classes

- **`LLMToolkitException`**: Base exception class
- **`InferenceException`**: Inference-related errors
- **`ModelProviderException`**: Model provider errors
- **`DownloadException`**: Download-related errors

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- 📧 Email: support@llmtoolkit.dev
- 💬 Discord: [Join our community](https://discord.gg/llmtoolkit)
- 📖 Documentation: [Full docs](https://docs.llmtoolkit.dev)
- 🐛 Issues: [GitHub Issues](https://github.com/yourorg/llm_toolkit/issues)

## 🙏 Acknowledgments

- Flutter Gemma team for multimodal support
- Llama.cpp community for GGUF inference
- Hugging Face for model hosting
- TensorFlow Lite team for mobile optimization

---

Built with ❤️ for the Flutter community
