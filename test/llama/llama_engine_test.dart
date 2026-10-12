import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/config.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:llm_toolkit/src/core/inference/gguf/resource_plan.dart';
import 'package:llm_toolkit/src/core/inference/llama/llama_params.dart';
import 'package:llm_toolkit/src/core/inference/llama/memory_guard.dart';
import 'package:llm_toolkit/src/core/inference/llama/stop_sequence_filter.dart';
import 'package:llm_toolkit/src/core/inference/llama_engine.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

String drive(StopSequenceFilter f, List<String> chunks) =>
    chunks.map(f.add).join() + f.flush();

void main() {
  test('engine refuses an invalid file without starting an isolate', () {
    final dir = Directory.systemTemp.createTempSync('llama_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/bad.gguf')..writeAsBytesSync(Uint8List(64));
    final engine = LlamaEngine();
    expect(
      engine.loadModel(f.path, const InferenceConfig()),
      throwsA(isA<InferenceException>()),
    );
    expect(engine.isModelLoaded, isFalse);
    expect(engine.capabilities, isEmpty);
    expect(engine.lastPlan, isNull);
    expect(engine.chatTemplate, isNull);
  });

  group('StopSequenceFilter', () {
    test('passes text through without stops', () {
      expect(drive(StopSequenceFilter([]), ['a', 'b']), 'ab');
    });

    test('trims at a stop split across chunks', () {
      final f = StopSequenceFilter(['<|end|>']);
      expect(drive(f, ['Hello <|', 'en', 'd|> ignored']), 'Hello ');
      expect(f.matched, isTrue);
    });

    test('releases held text that turned out not to be a stop', () {
      final f = StopSequenceFilter(['STOP']);
      expect(drive(f, ['ST', 'OK']), 'STOK');
      expect(f.matched, isFalse);
    });

    test('flushes a trailing partial match at end of stream', () {
      expect(drive(StopSequenceFilter(['STOP']), ['abc ST']), 'abc ST');
    });

    test('earliest of several stops wins', () {
      expect(drive(StopSequenceFilter(['b', 'a']), ['xxabxx']), 'xx');
    });
  });

  group('memory guard', () {
    test('parses MemAvailable', () {
      expect(
        parseAvailableMemoryMb('MemTotal: 1 kB\nMemAvailable:   2097152 kB\n'),
        2048,
      );
      expect(parseAvailableMemoryMb('nothing'), isNull);
    });

    test('clamps context by available memory', () {
      expect(clampContextSize(4096, 800), 512);
      expect(clampContextSize(4096, 1500), 1024);
      expect(clampContextSize(4096, 3000), 2048);
      expect(clampContextSize(1024, 3000), 1024);
      expect(clampContextSize(8192, 8000), 8192);
      expect(clampContextSize(8192, null), 8192);
    });
  });

  group('param mapping', () {
    test('model params follow backend and gpuLayers', () {
      expect(buildModelParams(const InferenceConfig()).nGpuLayers, 0);
      expect(
        buildModelParams(
          const InferenceConfig(backend: ComputeBackend.cpu, gpuLayers: 20),
        ).nGpuLayers,
        0,
      );
      expect(
        buildModelParams(
          const InferenceConfig(backend: ComputeBackend.gpu),
        ).nGpuLayers,
        99,
      );
      expect(
        buildModelParams(
          const InferenceConfig(backend: ComputeBackend.gpu, gpuLayers: 12),
        ).nGpuLayers,
        12,
      );
    });

    test('context params use config threads and batch sizing', () {
      final c = buildContextParams(
        const InferenceConfig(threads: 3),
        nCtx: 4096,
      );
      expect(
        (c.nCtx, c.nBatch, c.nThreads, c.embeddings),
        (4096, 512, 3, false),
      );
      final d = buildContextParams(
        const InferenceConfig(),
        nCtx: 256,
        processors: 12,
      );
      expect((d.nBatch, d.nThreads), (256, 6));
      final e = buildContextParams(
        const InferenceConfig(),
        nCtx: 1024,
        embedding: true,
        processors: 1,
      );
      expect(
        (e.nBatch, e.nUbatch, e.nThreads, e.embeddings),
        (1024, 1024, 1, true),
      );
    });

    test('plan drives kv type, flash attention, batches and threads', () {
      const plan = ResourcePlan(
        contextSize: 2048,
        kvCacheType: KvCacheType.q8_0,
        flashAttention: true,
        batchSize: 512,
        ubatchSize: 256,
        threads: 4,
        useMmap: true,
        useMlock: false,
        weightsBytes: 0,
        kvCacheBytes: 0,
        computeBytes: 0,
      );
      final c = buildContextParams(
        const InferenceConfig(),
        nCtx: plan.contextSize,
        plan: plan,
      );
      expect(
        (c.typeK, c.typeV, c.flashAttention, c.nBatch, c.nUbatch, c.nThreads),
        (
          LlamaKvCacheType.q8_0,
          LlamaKvCacheType.q8_0,
          LlamaFlashAttnType.enabled,
          512,
          256,
          4,
        ),
      );
    });

    test('config alone: quantised kv implies flash, f16 otherwise', () {
      final q = buildContextParams(
        const InferenceConfig(kvCacheType: KvCacheType.q4_0, batchSize: 128),
        nCtx: 1024,
      );
      expect(
        (q.typeV, q.flashAttention, q.nBatch),
        (LlamaKvCacheType.q4_0, LlamaFlashAttnType.enabled, 128),
      );
      final noFlash = buildContextParams(
        const InferenceConfig(
          kvCacheType: KvCacheType.q8_0,
          flashAttention: false,
        ),
        nCtx: 1024,
      );
      expect(
        (noFlash.typeK, noFlash.typeV),
        (LlamaKvCacheType.q8_0, LlamaKvCacheType.f16),
      );
      final d = buildContextParams(const InferenceConfig(), nCtx: 1024);
      expect(
        (d.typeK, d.flashAttention),
        (LlamaKvCacheType.f16, LlamaFlashAttnType.disabled),
      );
    });

    test('model params honour mmap and mlock overrides', () {
      final m = buildModelParams(
        const InferenceConfig(useMmap: false, useMlock: true),
      );
      expect((m.useMemorymap, m.useMemoryLock), (false, true));
      final d = buildModelParams(const InferenceConfig());
      expect((d.useMemorymap, d.useMemoryLock), (true, false));
    });

    test('chat format from embedded template', () {
      expect(chatFormatFromTemplate(null), isNull);
      expect(chatFormatFromTemplate('{{ "<start_of_turn>" }}'), 'gemma');
      expect(chatFormatFromTemplate('<|im_start|>user'), 'chatml');
      expect(chatFormatFromTemplate('### Instruction:'), 'alpaca');
      expect(chatFormatFromTemplate('<|start_header_id|>'), isNull);
    });

    test('sampler params map generation params', () {
      final s = buildSamplerParams(
        const GenerationParams(
          temperature: 0.3,
          topP: 0.8,
          topK: 10,
          repeatPenalty: 1.2,
          seed: 7,
        ),
      );
      expect(
        (s.temp, s.topP, s.topK, s.penaltyRepeat, s.seed, s.greedy),
        (0.3, 0.8, 10, 1.2, 7, false),
      );
      final g = buildSamplerParams(const GenerationParams(temperature: 0));
      expect(g.greedy, isTrue);
      expect(g.seed, 0xFFFFFFFF);
    });

    test('sampling key ignores length and stop sequences', () {
      const a = GenerationParams();
      expect(
        samplingKey(a),
        samplingKey(a.copyWith(maxTokens: 5, stopSequences: ['x'])),
      );
      expect(samplingKey(a), isNot(samplingKey(a.copyWith(topK: 1))));
    });

    test('max tokens is capped by config', () {
      const p = GenerationParams(maxTokens: 1000);
      expect(effectiveMaxTokens(p, null), 1000);
      expect(effectiveMaxTokens(p, const InferenceConfig(maxTokens: 256)), 256);
      expect(
        effectiveMaxTokens(p, const InferenceConfig(maxTokens: 4096)),
        1000,
      );
    });

    test('chat format selection', () {
      expect(
        chatFormatFor(ModelFamily.gemma).runtimeType.toString(),
        'GemmaFormat',
      );
      expect(
        chatFormatFor(ModelFamily.qwen).runtimeType.toString(),
        'ChatMLFormat',
      );
      expect(
        chatFormatFor(ModelFamily.generic, 'gemma').runtimeType.toString(),
        'GemmaFormat',
      );
    });
  });

  test('engine identity', () {
    final e = LlamaEngine();
    expect(e.id, 'llama');
    expect(e, isA<Embedder>());
    expect(
      e.generateText('hi', const GenerationParams()).first,
      throwsA(isA<InferenceException>()),
    );
  });
}
