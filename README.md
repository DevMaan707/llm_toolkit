<h1 align="center">LLM Toolkit</h1>

<p align="center">
  On-device AI for Flutter. Run language, vision, speech and embedding models locally,<br>
  discover and download them, and build chat, RAG and tool-calling apps on top.
</p>

<p align="center">
  <a href="https://pub.dev/packages/llm_toolkit"><img alt="pub package" src="https://img.shields.io/pub/v/llm_toolkit.svg"></a>
  <a href="https://github.com/DevMaan707/llm_toolkit/blob/main/LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Linux%20%7C%20Windows-lightgrey">
</p>

---

## Overview

`llm_toolkit` gives a Flutter app one consistent API over several inference runtimes. Your app asks for a *capability* (chat, transcription, embeddings, speech synthesis) and the toolkit routes the request to the engine that has a model loaded for it. Several models can be loaded at the same time, for example a chat model, an embedding model and a speech model.

- **Private and offline.** Inference runs on the device. No server is required.
- **Many model families.** Qwen, DeepSeek, Kimi, Llama, Gemma, Mistral, Phi, GLM, SmolLM, LFM, Granite and more, through llama.cpp and LiteRT.
- **More than text.** Vision input, embeddings, speech recognition and speech synthesis.
- **Local or remote, same code.** Point the same chat API at an OpenAI-compatible endpoint or an Ollama server when a model is too big for the phone.
- **Batteries included.** Model search, resumable downloads, chat sessions, structured output, tool calling and RAG.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Engines and capabilities](#engines-and-capabilities)
- [Model discovery and downloads](#model-discovery-and-downloads)
- [Chat](#chat)
- [Structured output and tools](#structured-output-and-tools)
- [Retrieval-augmented generation](#retrieval-augmented-generation)
- [Speech](#speech)
- [Voice assistant](#voice-assistant)
- [Remote models](#remote-models)
- [Running well on small devices](#running-well-on-small-devices)
- [Custom engines: image and video](#custom-engines-image-and-video)
- [Android native libraries](#android-native-libraries)
- [Logging](#logging)
- [Project status](#project-status)
- [Migrating from 0.0.x](#migrating-from-00x)
- [License](#license)

## Installation

```yaml
dependencies:
  llm_toolkit: ^0.1.1
```

```dart
import 'package:llm_toolkit/llm_toolkit.dart';
```

Platform setup:

| Platform | Requirement |
|---|---|
| Android | `INTERNET` permission for downloads, `RECORD_AUDIO` for the microphone. LiteRT needs `minSdk 30`. llama.cpp libraries must be bundled, see [Android native libraries](#android-native-libraries). |
| iOS | `NSMicrophoneUsageDescription` in `Info.plist` if you use the microphone. |
| Desktop | Engine support follows the underlying runtime; the sherpa-onnx speech engines work on Linux x64. |

## Quick start

```dart
final toolkit = LLMToolkit.instance
  ..initialize(huggingFaceApiKey: 'hf_...'); // key is optional

// 1. Find and download a model that fits the device
final results = await toolkit.searchModels(
  'qwen2.5 1.5b instruct',
  formats: {ModelFormat.gguf},
);
final file = results.first.recommendedFileFor(3 << 30)!; // 3 GB budget
final path = await toolkit.downloadModel(
  results.first,
  file.filename,
  onProgress: (p) => print('${(p * 100).round()}%'),
);

// 2. Load it. The engine is chosen from the file.
await toolkit.loadModel(path, config: const InferenceConfig.mobile());

// 3. Chat
final chat = toolkit.createChat(systemPrompt: 'You are concise.');
await for (final token in chat.send('Why is the sky blue?')) {
  stdout.write(token);
}
print(chat.lastUsage); // tokens/sec, time to first token, ...
```

## Engines and capabilities

An engine implements one or more capability interfaces. `InferenceManager` keeps a registry of loaded models, one per capability, so loading an embedding model does not unload your chat model.

| Engine id | Runtime | Formats | Capabilities |
|---|---|---|---|
| `llama` | llama.cpp via `llama_cpp_dart` | GGUF | text, chat, vision, embeddings |
| `litert` | LiteRT-LM via `flutter_edge_ai` | `.task`, `.litertlm` | text, chat, vision |
| `asr` | TFLite | Whisper `.tflite` | speech-to-text |
| `sherpa-asr` | sherpa-onnx | ONNX folders | speech-to-text (offline and streaming) |
| `sherpa-tts` | sherpa-onnx | ONNX folders | text-to-speech |
| `openai` / `ollama` | HTTP | n/a | text, chat, vision, embeddings; optional speech and images |

Engines are plugins. Implement the interfaces you need (`TextGenerator`, `ChatGenerator`, `Embedder`, `VisionGenerator`, `SpeechRecognizer`, `SpeechSynthesizer`, `ImageGenerator`, `VideoGenerator`) and call `toolkit.registerEngine(...)`.

## Model discovery and downloads

Search is task-aware. `runnableBy` on a result names the engine that can load it, so you can hide models your app cannot run.

```dart
final asr = await toolkit.searchModels('whisper', task: ModelTask.speechToText);

// A curated, verified catalog of phone-sized models per task
final tts = ModelCatalog.forDevice(ModelTask.textToSpeech, 3 << 30);
```

Sources: Hugging Face (including whole-folder `downloadBundle` for sherpa-onnx), Ollama, and local folders.

Downloads are resumable (HTTP Range), can be paused and cancelled, report speed and ETA, verify SHA-256, and are tracked in an on-disk `ModelStore`.

## Chat

`ChatSession` manages history, trims context to fit the model, supports regenerate and undo, reports usage, and saves and restores as JSON.

Prompt templates cover ChatML, Llama 3, Gemma, Mistral, Phi-3, Qwen, DeepSeek and about a dozen more families. They are picked from the model name or from the template embedded in the GGUF (`PromptTemplate.forModelName`, `PromptTemplate.fromGgufTemplate`).

## Structured output and tools

```dart
final schema = JsonSchema.object(properties: {
  'city': JsonSchema.string(),
  'temperature_c': JsonSchema.number(),
}, required: ['city', 'temperature_c']);

final data = await generateStructured<Map<String, dynamic>>(
  engine,
  prompt: 'Weather in Paris, as JSON',
  schema: schema,
);
```

JSON is extracted and repaired from model output, validated against the schema, and retried on failure.

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

## Retrieval-augmented generation

Load an embedding model (for example `nomic-embed-text` as GGUF) next to your chat model.

```dart
await toolkit.loadModel(embeddingPath);
await toolkit.loadModel(chatPath);

final rag = toolkit.createRagPipeline(store: FileVectorStore(Directory(dir)));
await rag.addDocument(RagDocument(id: 'manual', text: manualText));

final answer = await rag.answer('How do I reset the device?');
answer.stream.listen(stdout.write); // answer.sources holds the citations
```

Included: sentence, paragraph, recursive and markdown chunkers; in-memory and file-backed vector stores; hybrid BM25 plus vector search; MMR re-ranking; cited answers.

## Speech

### Whisper (TFLite)

```dart
await toolkit.loadModel(whisperTflitePath);
final text = await toolkit.transcribe(wavBytes);

final asr = ASRService(); // microphone, VAD and streaming transcription
await asr.initialize(whisperTflitePath);
asr.startStreamingTranscription().listen(print);
```

The `asr` engine expects a Whisper TFLite model with a `[1, 80, 3000]` float input.

### sherpa-onnx

`sherpa-asr` and `sherpa-tts` run the mobile-friendly models of [sherpa-onnx](https://k2-fsa.github.io/sherpa/onnx/). Models are folders; the architecture is detected from the file names.

- **Recognition:** Whisper, Moonshine, NVIDIA Parakeet, Zipformer, SenseVoice, Paraformer (offline and streaming).
- **Synthesis:** Kokoro, Piper/VITS, Kitten, Matcha.

```dart
await toolkit.loadModel('/models/sherpa-onnx-whisper-tiny.en'); // routes to sherpa-asr
final text = await toolkit.transcribe(wavBytes);                // WAV or 16 kHz PCM16

final asr = SherpaAsrEngine();
await asr.loadModel('/models/sherpa-onnx-streaming-zipformer-en-2023-06-26',
    const InferenceConfig.defaults());
asr.transcribeStream(micPcmStream).listen(print); // streaming models endpoint themselves

final wav = await toolkit.synthesizeSpeech('Hello', voice: '3'); // WAV bytes
```

Offline models are cut into utterances by Silero VAD when you pass `InferenceConfig(extra: {'vadModel': '/path/silero_vad.onnx'})`. Without it, the stream is transcribed as one text when it ends. Other `extra` keys: `language`, `task`, `numThreads`, `provider` (`cpu`, `xnnpack`, `nnapi`, `coreml`), `decodingMethod`, `preferInt8`, `streaming`, `speakerNames`, `vocoder` (Matcha). Recognition and synthesis run in a background isolate.

<details>
<summary>Hugging Face repositories known to work (under <code>csukuangfj/</code>)</summary>

| Kind | Repository |
|---|---|
| Whisper | `sherpa-onnx-whisper-tiny.en`, `-base.en`, `-small.en`, `-tiny`, `-base`, `-small` |
| Moonshine | `sherpa-onnx-moonshine-tiny-en-int8`, `sherpa-onnx-moonshine-base-en-int8` |
| Parakeet | `sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8`, `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` |
| SenseVoice | `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` |
| Zipformer | `sherpa-onnx-zipformer-small-en-2023-06-26`, `sherpa-onnx-streaming-zipformer-en-2023-06-26` |
| Paraformer | `sherpa-onnx-paraformer-zh-2023-09-14`, `sherpa-onnx-streaming-paraformer-bilingual-zh-en` |
| Kokoro | `kokoro-multi-lang-v1_0`, `kokoro-int8-multi-lang-v1_1` |
| Piper / VITS | `vits-piper-en_US-amy-low` (and other `vits-piper-*`), `vits-melo-tts-zh_en` |
| Kitten | `kitten-nano-en-v0_1-fp16` |
| Matcha | `matcha-icefall-en_US-ljspeech` (needs a vocoder such as `vocos-22khz-univ.onnx`) |

More models are listed in the [sherpa-onnx model list](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/). The Silero VAD model, `silero_vad.onnx`, is in the [`asr-models` release](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models).

</details>

## Voice assistant

`VoiceAssistant` connects recognition, chat and synthesis: the reply is spoken sentence by sentence while it is still being generated. It produces WAV audio and events; playing the audio is up to your app.

```dart
await toolkit.loadModel(llmPath);                          // chat
await toolkit.loadModel('/models/vits-piper-en_US-amy-low'); // text-to-speech
final chat = toolkit.createChat(systemPrompt: 'Answer in one or two sentences.');
final assistant = toolkit.createVoiceAssistant(chat, voice: '0');

// From typed text or already recognised text
await for (final e in assistant.respondToText('Tell me a fact')) {
  switch (e) {
    case VoiceReplyToken(:final text): ui.append(text);
    case VoiceSpeech(:final wav): player.enqueue(wav);   // play in order
    case VoiceTurnDone(:final usage): ui.finish(usage);
    case VoiceWarning(:final message): log(message);
    default: break;
  }
}

// Hands-free: microphone -> streaming recognizer -> chat -> speech
assistant.listen(recognizer: sherpaAsrEngine).listen(handleEvent);

assistant.interrupt(); // stop the current reply
```

Events: `VoicePartialTranscript`, `VoiceTranscript`, `VoiceReplyToken`, `VoiceSpeech`, `VoiceTurnDone`, `VoiceWarning`. `respondToAudio(bytes, recognizer)` handles a recorded clip. While a reply is produced the microphone is buffered, so use headphones or pause capture while audio plays to avoid the assistant hearing itself.

## Remote models

Models too big for a phone (Kimi K2, DeepSeek-V3, hosted GPT-class models), or models served on your network, use the same API:

```dart
await toolkit.useRemote(RemoteModelPresets.deepSeek, model: 'deepseek-chat', apiKey: key);
await toolkit.useRemote(RemoteModelPresets.openRouter, model: 'moonshotai/kimi-k2', apiKey: key);
await toolkit.useOllama(model: 'qwen3:8b', baseUrl: 'http://192.168.1.20:11434');

final chat = toolkit.createChat(); // identical from here on
```

`OpenAiCompatibleEngine` also supports embeddings and vision, and, when enabled, speech and image endpoints, so remote Whisper, TTS and diffusion servers plug into `transcribe`, `synthesizeSpeech` and `generateImage`.

## Running well on small devices

`LlamaEngine` plans every load from the GGUF header (layers, KV heads, sliding window, quantisation) and from the memory the OS reports as free. With `InferenceConfig.optimizeForDevice` (the default) it chooses:

- the context size,
- the KV cache precision (`f16`, then `q8_0`, then `q4_0` only when memory demands it),
- flash attention (required for a quantised V cache),
- batch sizes and the performance-core thread count,
- memory-mapped weights.

Anything you set explicitly (`contextSize`, `kvCacheType`, `flashAttention`, `batchSize`, `ubatchSize`, `threads`, `useMmap`, `useMlock`) wins. A requested context that cannot fit even with a `q4_0` cache is still reduced, to avoid being killed for out-of-memory.

```dart
final plan = await LlamaEngine.planFor(path); // before loading, e.g. for a UI warning
print(plan); // context, KV type, estimated MB, reasons and warnings
```

Notes:

- `q8_0` KV roughly halves cache memory with negligible quality loss. `q4_0` costs quality on some tasks. KV quantisation saves memory, not speed.
- Memory figures are estimates (about 10%). Free memory is only readable on Android and Linux.
- Speculative and multi-token-prediction decoding are not available in the `llama_cpp_dart` binding.
- If the model embeds a chat template, `LlamaEngine.chatTemplate` exposes it.

## Custom engines: image and video

On-device diffusion and video runtimes are not bundled. The toolkit defines `ImageGenerator`, `VideoGenerator` and `SpeechSynthesizer`, and routes `generateImage(...)`, `generateVideo(...)` and `synthesizeSpeech(...)` to any engine you register:

```dart
class MyDiffusionEngine implements InferenceEngine, ImageGenerator { /* ... */ }

toolkit.registerEngine(MyDiffusionEngine());
await toolkit.loadModel(path, engineId: 'my-diffusion');
final png = await toolkit.generateImage(const ImageGenerationRequest(prompt: 'a lighthouse'));
```

For images today, use a remote endpoint through `OpenAiCompatibleEngine`.

## Android native libraries

`llama_cpp_dart` does not ship llama.cpp binaries, and its C bindings match exactly one llama.cpp revision (0.2.2 is generated against `4ffc47c`). A newer `libllama.so` has different struct layouts and will misbehave.

`scripts/build_android_libs.sh` builds the pinned revision, including `libmtmd.so`, with the NDK:

```bash
ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/27.2.12479018 \
  scripts/build_android_libs.sh arm64-v8a x86_64
```

Output goes to `example/android/app/src/main/jniLibs`. Set `OUT_DIR` to use your own app's `jniLibs`. When you bump `llama_cpp_dart`, bump `LLAMA_CPP_COMMIT` in the script with it. You can also pass `extra: {'libraryPath': ...}` in `InferenceConfig`.

## Logging

The library is silent below `warning`. Set `ToolkitLog.level = LogLevel.debug;` for more, and `ToolkitLog.sink` to redirect records to your own logger.

## Project status

This is a 0.1 release. Be aware of what has been verified:

| Area | Status |
|---|---|
| Chat, RAG, providers, downloads, audio DSP | Unit tested (pure Dart, fake servers) |
| sherpa-onnx: Whisper (offline, with VAD), streaming Zipformer, Piper | Run end to end on Linux x64 |
| sherpa-onnx: Moonshine, Parakeet, SenseVoice, Paraformer, Kokoro, Matcha | Configured from the sherpa API, not yet run |
| llama.cpp, LiteRT, TFLite engines | Compile against current APIs; need testing on real devices and models |
| Prompt templates for some families (for example Command-R, GLM-4) | Written from public descriptions, not verified against reference output |

A configuration that sherpa-onnx rejects can abort the process from native code. Streaming-model mismatches are detected up front; other mismatches may not be. Issues and pull requests are welcome at [github.com/DevMaan707/llm_toolkit](https://github.com/DevMaan707/llm_toolkit/issues).

## Migrating from 0.0.x

See [CHANGELOG.md](CHANGELOG.md) for the full list. The main changes:

- `flutter_gemma` (discontinued) is replaced by `flutter_edge_ai`, and its types are no longer re-exported.
- `InferenceEngineType` and the old Gemma and TFLite engines are replaced by string engine ids and capability interfaces.
- `SearchQuery(searchTerm:)` is now `SearchQuery(text:)`.
- RAG moved to `RagPipeline`.
- `ASRService` initialisation changed.

## License

MIT. See [LICENSE](LICENSE). Models you download have their own licences.
