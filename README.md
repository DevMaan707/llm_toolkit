# LLM Toolkit

On-device AI for Flutter: run LLMs, vision models, speech recognition and embeddings locally, find and download models, and build chat, RAG and tool-calling apps on top — with no server.

## Features

| Area | What you get |
|---|---|
| **Engines** | `llama` (GGUF via llama.cpp), `litert` (Gemma and others via LiteRT-LM / `flutter_edge_ai`), `asr` (Whisper TFLite). Engines are plugins: implement a capability interface and `registerEngine` it. |
| **Capabilities** | text generation, chat, vision, embeddings, speech-to-text, plus extension points for text-to-speech, **image generation** and **video generation** engines |
| **Model discovery** | Hugging Face (filters, quantisation and size parsing, "best file for my RAM"), Ollama, local folders |
| **Downloads** | resumable (HTTP Range), pause/cancel, speed/ETA, SHA-256 verification, on-disk `ModelStore` |
| **Chat** | `ChatSession` with history, context trimming, regenerate/undo, usage stats, prompt templates (ChatML, Llama 3, Gemma, Mistral, Phi-3, Qwen, DeepSeek), JSON save/restore |
| **Structured output** | JSON-schema builder, robust JSON extraction/repair, validation with retry |
| **Tools** | function-calling definitions, call parsing, an agent loop (`ToolRunner`) |
| **RAG** | chunkers (sentence, paragraph, recursive, markdown), in-memory and file-backed vector stores, hybrid BM25 + vector, MMR, cited answers |
| **Speech** | Whisper preprocessing, VAD, streaming transcription with overlap de-duplication |

Platforms follow the underlying runtimes: Android, iOS, macOS, Linux and Windows (engine support varies).

## Install

```yaml
dependencies:
  llm_toolkit: ^0.1.0
```

Android needs `INTERNET` (downloads) and `RECORD_AUDIO` (speech); iOS needs `NSMicrophoneUsageDescription`. LiteRT requires Android `minSdk 30`. The llama engine loads llama.cpp through `llama_cpp_dart`; see its README for bundling native libraries, or pass `extra: {'libraryPath': ...}` in `InferenceConfig`.

## Quick start

```dart
final toolkit = LLMToolkit.instance
  ..initialize(huggingFaceApiKey: 'hf_...'); // key optional

// 1. Find and download a model
final models = await toolkit.searchModels('qwen2.5 1.5b instruct', formats: {ModelFormat.gguf});
final file = models.first.recommendedFileFor(3 << 30)!;
final path = await toolkit.downloadModel(models.first, file.filename,
    onProgress: (p) => print('${(p * 100).round()}%'));

// 2. Load it (engine is picked from the file)
await toolkit.loadModel(path, config: const InferenceConfig.mobile());

// 3. Chat
final chat = toolkit.createChat(systemPrompt: 'You are concise.');
await for (final token in chat.send('Why is the sky blue?')) {
  stdout.write(token);
}
print(chat.lastUsage); // tokens/sec, time to first token, ...
```

## Structured output and tools

```dart
final schema = JsonSchema.object(properties: {
  'city': JsonSchema.string(),
  'temperature_c': JsonSchema.number(),
}, required: ['city', 'temperature_c']);

final data = await generateStructured<Map<String, dynamic>>(
  engine, prompt: 'Weather in Paris, as JSON', schema: schema);
```

```dart
final runner = ToolRunner(chat, [
  ToolDefinition(
    name: 'get_time',
    description: 'Current time',
    handler: (args) async => DateTime.now().toIso8601String(),
  ),
]);
final result = await runner.run('What time is it?');
```

## RAG

Load an embedding GGUF (for example `nomic-embed-text`) next to your chat model — several models can be loaded at once.

```dart
await toolkit.loadModel(embeddingPath);
await toolkit.loadModel(chatPath);

final rag = toolkit.createRagPipeline(
  store: FileVectorStore(Directory(dir)),
);
await rag.addDocument(RagDocument(id: 'manual', text: manualText));
final answer = await rag.answer('How do I reset the device?');
answer.stream.listen(stdout.write); // answer.sources holds the citations
```

## Speech recognition

```dart
await toolkit.loadModel(whisperTflitePath);
final text = await toolkit.transcribe(wavBytes);

final asr = ASRService();                     // microphone, VAD, streaming
await asr.initialize(whisperTflitePath);
asr.startStreamingTranscription().listen(print);
```

## Small devices

`LlamaEngine` plans each load from the GGUF header (layers, KV heads, sliding window, quantisation) and the memory the OS reports free. With `InferenceConfig.optimizeForDevice` (default) it picks the context size, KV cache precision (`f16`, then `q8_0`, then `q4_0` only when memory demands it), flash attention (needed for a quantised V cache), batch sizes and performance-core thread count, memory-maps the weights, and logs the plan. Anything you set explicitly (`contextSize`, `kvCacheType`, `flashAttention`, `batchSize`, `ubatchSize`, `threads`, `useMmap`, `useMlock`) wins; a requested context that cannot fit even with a `q4_0` cache is still reduced to avoid an out-of-memory kill.

```dart
final plan = await LlamaEngine.planFor(path); // before loading, e.g. for a UI warning
print(plan); // ctx, KV type, estimated MB, reasons and warnings
```

`q8_0` KV roughly halves cache memory with negligible quality loss; `q4_0` costs quality on some tasks. KV quantisation saves memory, not speed. Speculative/multi-token-prediction decoding is not available in the `llama_cpp_dart` binding. Memory figures are estimates (about 10%); free memory is only readable on Android and Linux. If the model embeds a chat template, `LlamaEngine.chatTemplate` exposes it and a matching built-in prompt format (ChatML, Gemma, Alpaca) is chosen when no family or `chatFormat` is set.

## Image, video and other models

On-device diffusion/video runtimes are not bundled. The toolkit defines `ImageGenerator`, `VideoGenerator` and `SpeechSynthesizer` and routes `toolkit.generateImage(...)`, `generateVideo(...)` and `synthesizeSpeech(...)` to any engine you register:

```dart
class MyDiffusionEngine implements InferenceEngine, ImageGenerator { /* ... */ }
toolkit.registerEngine(MyDiffusionEngine());
await toolkit.loadModel(path, engineId: 'my-diffusion');
final png = await toolkit.generateImage(const ImageGenerationRequest(prompt: 'a lighthouse'));
```

## Any model: local or remote

On-device GGUF runs through llama.cpp, so any architecture it supports (Qwen, DeepSeek, Kimi, Llama, Gemma, Mistral, Phi, GLM, SmolLM, LFM, Granite, ...) loads. Prompt templates exist for all of those families and are chosen from the model name or the template embedded in the GGUF (`PromptTemplate.forModelName`, `PromptTemplate.fromGgufTemplate`).

Models too big for a phone (Kimi K2, DeepSeek-V3, GPT-class) or served on your LAN work through the same API:

```dart
await toolkit.useRemote(RemoteModelPresets.deepSeek, model: 'deepseek-chat', apiKey: key);
await toolkit.useRemote(RemoteModelPresets.openRouter, model: 'moonshotai/kimi-k2', apiKey: key);
await toolkit.useOllama(model: 'qwen3:8b', baseUrl: 'http://192.168.1.20:11434');

final chat = toolkit.createChat(); // identical from here on
```

`OpenAiCompatibleEngine` also provides embeddings, vision, and (opt-in) speech and image endpoints, so remote Whisper/TTS/diffusion servers plug into `transcribe`, `synthesizeSpeech` and `generateImage`.

## Android native libraries

`llama_cpp_dart` does not ship llama.cpp binaries, and its C bindings only match one llama.cpp revision (0.2.2 is generated against `4ffc47c`); a newer `libllama.so` has different struct layouts and will misbehave. `scripts/build_android_libs.sh` builds exactly the pinned revision (including `libmtmd.so`, which the package loads by default on Android) with the NDK:

```bash
ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/27.2.12479018 scripts/build_android_libs.sh arm64-v8a x86_64
```

The output goes to `example/android/app/src/main/jniLibs`; point `OUT_DIR` at your own app's `jniLibs` instead. When you bump `llama_cpp_dart`, bump `LLAMA_CPP_COMMIT` in the script with it.

## Logging

The library is silent below `warning`. `ToolkitLog.level = LogLevel.debug;` enables more, and `ToolkitLog.sink` redirects records to your own logger.

## Status

Pure-Dart logic (chat, RAG, providers, downloads, audio DSP) is unit tested. Native engines (llama.cpp, LiteRT, TFLite) compile against their current APIs but need testing on real devices and models; ASR in particular assumes a Whisper TFLite model with `[1,80,3000]` float input.

## Migrating from 0.0.x

See [CHANGELOG.md](CHANGELOG.md). Highlights: `flutter_gemma` (discontinued) is replaced by `flutter_edge_ai`; `InferenceEngineType` and the Gemma/TFLite engines are gone in favour of string engine ids and capability interfaces; `SearchQuery(searchTerm:)` is now `text:`; RAG moved to `RagPipeline`.

## License

MIT
