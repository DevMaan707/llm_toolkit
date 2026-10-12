import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/config.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';
import 'package:llm_toolkit/src/core/model_detector.dart';

void main() {
  const detector = ModelDetector();

  test('detects every family from typical file names', () {
    const cases = {
      'gemma-3-4b-it-Q4_K_M.gguf': ModelFamily.gemma,
      'DeepSeek-R1-Distill-Qwen-7B.gguf': ModelFamily.deepSeek,
      'Qwen3-8B-Q4_K_M.gguf': ModelFamily.qwen,
      'QwQ-32B.gguf': ModelFamily.qwen,
      'Kimi-K2-Instruct.gguf': ModelFamily.kimi,
      'Moonlight-16B-A3B-Instruct.gguf': ModelFamily.kimi,
      'GLM-4-9B-0414-Q4_K_M.gguf': ModelFamily.glm,
      'SmolLM3-3B-Q8_0.gguf': ModelFamily.smolLm,
      'LFM2-1.2B-Q4_0.gguf': ModelFamily.liquid,
      'granite-3.3-2b-instruct.gguf': ModelFamily.granite,
      'c4ai-command-r7b-12-2024.gguf': ModelFamily.cohere,
      'OLMo-2-1124-7B-Instruct.gguf': ModelFamily.olmo,
      'internlm3-8b-instruct.gguf': ModelFamily.internLm,
      'MiniCPM4-8B.gguf': ModelFamily.miniCpm,
      'Yi-1.5-9B-Chat.gguf': ModelFamily.yi,
      'gpt-oss-20b-mxfp4.gguf': ModelFamily.openAiOss,
      'Phi-3-mini-4k-instruct.gguf': ModelFamily.phi,
      'phi4-mini.gguf': ModelFamily.phi,
      'Mistral-7B-Instruct-v0.3.gguf': ModelFamily.mistral,
      'Llama-3.2-3B-Instruct.gguf': ModelFamily.llama,
      'unknown-model.gguf': ModelFamily.generic,
    };
    for (final MapEntry(key: name, value: family) in cases.entries) {
      expect(detector.detectFamily(name), family, reason: name);
    }
  });

  test('family detection is case insensitive', () {
    expect(detector.detectFamily('KIMI-K2'), ModelFamily.kimi);
  });

  test('routes files to engines', () {
    expect(detector.detect('/models/Qwen3-8B.gguf').engineId, 'llama');
    expect(detector.detect('gemma.litertlm').engineId, 'litert');
    expect(detector.detect(r'C:\m\whisper-tiny.tflite').engineId, 'asr');
  });

  group('sherpa routing', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('detector'));
    tearDown(() => root.deleteSync(recursive: true));

    String folder(String name, List<String> files) {
      final dir = Directory('${root.path}/$name')..createSync();
      for (final f in files) {
        File('${dir.path}/$f').writeAsBytesSync(const []);
      }
      return dir.path;
    }

    test('folders route by content', () {
      final asr = detector.detect(
        folder('anything', ['model.onnx', 'tokens.txt']),
      );
      expect(asr.engineId, 'sherpa-asr');
      expect(asr.capabilities, {ModelCapability.speechToText});
      final tts = detector.detect(
        folder('voice-pack', ['model.onnx', 'voices.bin', 'tokens.txt']),
      );
      expect(tts.engineId, 'sherpa-tts');
      expect(tts.capabilities, {ModelCapability.textToSpeech});
    });

    test('unreadable folders fall back to the name', () {
      expect(
        detector.detect(folder('kokoro-empty', const [])).engineId,
        'sherpa-tts',
      );
      expect(detector.detect(folder('mystery', const [])).engineId, 'llama');
    });

    test('names route when the path is not a folder', () {
      const asr = [
        'sherpa-onnx-whisper-tiny.en',
        'moonshine-tiny.onnx',
        'nemo-parakeet-tdt-0.6b-v2-int8',
        'streaming-zipformer-en',
        'sherpa-onnx-sense-voice-zh-en',
        'paraformer-zh',
      ];
      const tts = [
        'kokoro-multi-lang-v1_0',
        'vits-piper-en_US-amy-low',
        'matcha-icefall-en_US-ljspeech',
        'kokoro.onnx',
      ];
      for (final n in asr) {
        expect(detector.detect('/m/$n').engineId, 'sherpa-asr', reason: n);
      }
      for (final n in tts) {
        expect(detector.detect('/m/$n').engineId, 'sherpa-tts', reason: n);
      }
    });

    test('other formats keep their engines', () {
      expect(detector.detect('whisper-tiny.tflite').engineId, 'asr');
      expect(detector.detect('whisper-large.bin').engineId, 'llama');
      expect(detector.detect('piper-chat.gguf').engineId, 'llama');
      expect(detector.detect('gemma.litertlm').engineId, 'litert');
    });
  });
}
