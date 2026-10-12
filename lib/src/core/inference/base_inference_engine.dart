import 'dart:typed_data';

import '../config.dart';

/// What a loaded model can do. Engines advertise these so the toolkit can
/// route requests (e.g. a RAG pipeline needs [embeddings] and [textGeneration]
/// from possibly different engines loaded at the same time).
enum ModelCapability {
  textGeneration,
  vision,
  audioInput,
  embeddings,
  speechToText,
  textToSpeech,
  imageGeneration,
  videoGeneration,
}

/// Base contract for every engine. Capabilities are exposed by additionally
/// implementing the matching interface below ([TextGenerator], [Embedder], ...).
abstract class InferenceEngine {
  /// Stable identifier used for registration, e.g. `llama`, `litert`, `asr`.
  String get id;

  Set<ModelCapability> get capabilities;

  bool get isModelLoaded;

  String? get currentModelPath;

  Future<void> loadModel(String modelPath, InferenceConfig config);

  Future<void> unloadModel();
}

/// Plain text completion / streaming generation.
abstract interface class TextGenerator {
  Stream<String> generateText(String prompt, GenerationParams params);
}

/// Engines with a native chat API (own template handling, KV cache reuse).
/// Chat sessions prefer this over formatting a prompt themselves.
abstract interface class ChatGenerator {
  Stream<String> generateChat(List<ChatTurn> messages, GenerationParams params);
}

/// Text embeddings.
abstract interface class Embedder {
  int? get embeddingDimensions;
  Future<List<double>> embed(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
}

/// Prompt + images (vision language models).
abstract interface class VisionGenerator {
  Stream<String> generateWithImages(
    String prompt,
    List<Uint8List> images,
    GenerationParams params,
  );
}

/// Speech to text.
abstract interface class SpeechRecognizer {
  /// [audio] is a WAV file or raw PCM16 mono bytes.
  Future<String> transcribe(Uint8List audio);
}

/// Text to speech. Returns WAV bytes.
abstract interface class SpeechSynthesizer {
  Future<Uint8List> synthesize(String text, {String? voice});
}

/// Image generation (diffusion and similar). Returns encoded image bytes.
abstract interface class ImageGenerator {
  Future<Uint8List> generateImage(ImageGenerationRequest request);
}

/// Video generation. Emits encoded frames/chunks as they become available.
abstract interface class VideoGenerator {
  Stream<Uint8List> generateVideo(VideoGenerationRequest request);
}

/// One message in a chat transcript passed to a [ChatGenerator].
class ChatTurn {
  final String role; // system | user | assistant | tool
  final String content;
  final List<Uint8List> images;

  const ChatTurn(this.role, this.content, {this.images = const []});
}

class ImageGenerationRequest {
  final String prompt;
  final String? negativePrompt;
  final int width;
  final int height;
  final int steps;
  final double guidanceScale;
  final int? seed;

  const ImageGenerationRequest({
    required this.prompt,
    this.negativePrompt,
    this.width = 512,
    this.height = 512,
    this.steps = 20,
    this.guidanceScale = 7.5,
    this.seed,
  });
}

class VideoGenerationRequest {
  final String prompt;
  final Uint8List? initImage;
  final int width;
  final int height;
  final int frames;
  final int fps;
  final int? seed;

  const VideoGenerationRequest({
    required this.prompt,
    this.initImage,
    this.width = 512,
    this.height = 512,
    this.frames = 16,
    this.fps = 8,
    this.seed,
  });
}
