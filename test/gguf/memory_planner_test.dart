import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/config.dart';
import 'package:llm_toolkit/src/core/inference/gguf/gguf_metadata.dart';
import 'package:llm_toolkit/src/core/inference/gguf/kv_cache_estimator.dart';
import 'package:llm_toolkit/src/core/inference/gguf/memory_planner.dart';
import 'package:llm_toolkit/src/core/inference/llama_engine.dart';

import 'gguf_builder.dart';

const mb = 1024 * 1024;
const gb = 1024 * mb;

Future<GgufMetadata> meta(GgufBuilder b) => GgufMetadata.fromBytes(b.build());

void main() {
  group('KV cache estimate', () {
    test('GQA: 16 layers, 4 kv heads, head dim 128, f16', () async {
      final m = await meta(GgufBuilder().transformer());
      // 16 layers * 4 heads * (128 + 128) * 2 bytes = 32768 per token.
      expect(m.kvCacheBytes(1000), 32768 * 1000);
    });

    test('quantisation shrinks the cache by the expected ratio', () async {
      final m = await meta(GgufBuilder().transformer());
      final f16 = m.kvCacheBytes(4096)!;
      final q8 =
          m.kvCacheBytes(4096, k: KvCacheType.q8_0, v: KvCacheType.q8_0)!;
      final q4 =
          m.kvCacheBytes(4096, k: KvCacheType.q4_0, v: KvCacheType.q4_0)!;
      expect(q8 / f16, closeTo(0.53, 0.01));
      expect(q4 / f16, closeTo(0.28, 0.01));
    });

    test('explicit key/value length override the derived head size', () async {
      final m = await meta(
        GgufBuilder()
            .transformer(blocks: 2, kvHeads: 1)
            .u32('llama.attention.key_length', 256)
            .u32('llama.attention.value_length', 128),
      );
      expect(m.kvCacheBytes(10), 2 * 1 * (256 + 128) * 2 * 10);
    });

    test('sliding window layers cache only the window', () async {
      final m = await meta(
        GgufBuilder()
            .transformer(
              arch: 'gemma3',
              blocks: 12,
              heads: 8,
              kvHeads: 4,
              embedding: 1024,
            )
            .u32('gemma3.attention.sliding_window', 512),
      );
      expect(m.slidingLayerCount, 10); // pattern 6 => 2 global of 12
      final perTokenLayer = 4 * (128 + 128) * 2;
      final expected = (2 * 8192 + 10 * (512 + 256)) * perTokenLayer;
      expect(m.kvCacheBytes(8192, ubatchSize: 256), expected);
      expect(
        m.kvCacheBytes(8192, ubatchSize: 256, swaFull: true),
        12 * 8192 * perTokenLayer,
      );
    });

    test('per-layer sliding flags and unknown architectures', () async {
      final flags = await meta(
        GgufBuilder()
            .transformer(arch: 'foo', blocks: 4)
            .u32('foo.attention.sliding_window', 64)
            .boolArray('foo.attention.sliding_window_pattern', [
              true,
              true,
              true,
              false,
            ]),
      );
      expect(flags.slidingLayerCount, 3);
      final unknown = await meta(
        GgufBuilder()
            .transformer(arch: 'foo')
            .u32('foo.attention.sliding_window', 64),
      );
      expect(unknown.slidingLayerCount, 0);
    });

    test(
      'recurrent models have no KV cache; sparse metadata gives null',
      () async {
        final mamba = await meta(
          GgufBuilder().string('general.architecture', 'mamba'),
        );
        expect(mamba.kvCacheBytes(4096), 0);
        final sparse = await meta(
          GgufBuilder().string('general.architecture', 'llama'),
        );
        expect(sparse.kvCacheBytes(4096), isNull);
      },
    );
  });

  group('MemoryPlanner', () {
    late GgufMetadata model;
    setUp(() async {
      // 7B-like: 32 layers, 8 kv heads, head dim 128 => 128 KiB/token f16.
      model = await meta(
        GgufBuilder().transformer(
          context: 32768,
          embedding: 4096,
          blocks: 32,
          heads: 32,
          kvHeads: 8,
        ),
      );
    });

    test('plenty of memory keeps f16 at the default context', () {
      final p = MemoryPlanner.plan(
        metadata: model,
        fileSizeBytes: 4 * gb,
        availableBytes: 16 * gb,
        cores: 8,
      );
      expect(p.contextSize, 4096);
      expect(p.kvCacheType, KvCacheType.f16);
      expect(p.flashAttention, isFalse);
      expect(p.fitsInMemory, isTrue);
      expect(p.threads, 4);
      expect(p.useMmap, isTrue);
      expect(p.useMlock, isFalse);
      expect(p.warnings, isEmpty);
    });

    test(
      'tight memory quantises the cache, enables flash, shrinks batches',
      () {
        final p = MemoryPlanner.plan(
          metadata: model,
          fileSizeBytes: 3 * gb,
          availableBytes: 4 * gb - 1,
          cores: 8,
        );
        expect(p.kvCacheType, isNot(KvCacheType.f16));
        expect(p.flashAttention, isTrue);
        expect(p.ubatchSize, 256);
        expect(p.totalBytes, lessThanOrEqualTo(p.budgetBytes!));
        expect(p.reasons.join(), contains('quantised'));
      },
    );

    test('very tight memory reduces the context', () {
      final p = MemoryPlanner.plan(
        metadata: model,
        fileSizeBytes: 3 * gb,
        availableBytes: 3 * gb + 200 * mb,
        cores: 8,
      );
      expect(p.contextSize, lessThan(4096));
      expect(p.kvCacheType, KvCacheType.q4_0);
      expect(p.reasons.join(), contains('Context reduced'));
    });

    test('model larger than memory warns and returns the smallest plan', () {
      final p = MemoryPlanner.plan(
        metadata: model,
        fileSizeBytes: 8 * gb,
        availableBytes: 2 * gb,
        cores: 8,
      );
      expect(p.fitsInMemory, isFalse);
      expect(p.contextSize, 512);
      expect(p.warnings.join(), contains('exceeds the budget'));
    });

    test('explicit config wins', () {
      final p = MemoryPlanner.plan(
        metadata: model,
        fileSizeBytes: 3 * gb,
        availableBytes: 6 * gb,
        cores: 8,
        config: const InferenceConfig(
          contextSize: 2048,
          kvCacheType: KvCacheType.q8_0,
          flashAttention: false,
          batchSize: 128,
          ubatchSize: 64,
          threads: 3,
          useMmap: false,
          useMlock: true,
        ),
      );
      expect(p.contextSize, 2048);
      expect(p.kvCacheType, KvCacheType.q8_0);
      expect(p.flashAttention, isFalse);
      expect((p.batchSize, p.ubatchSize, p.threads), (128, 64, 3));
      expect((p.useMmap, p.useMlock), (false, true));
      expect(
        p.warnings.join(),
        allOf(
          contains('Flash attention is disabled'),
          contains('mmap disabled'),
        ),
      );
    });

    test('explicit context is reduced only when it cannot fit', () {
      final fits = MemoryPlanner.plan(
        metadata: model,
        fileSizeBytes: 2 * gb,
        availableBytes: 8 * gb,
        config: const InferenceConfig(contextSize: 16384),
      );
      expect(fits.contextSize, 16384);
      final squeezed = MemoryPlanner.plan(
        metadata: model,
        fileSizeBytes: 2 * gb,
        availableBytes: 3 * gb,
        config: const InferenceConfig(contextSize: 16384),
      );
      expect(squeezed.contextSize, lessThan(16384));
    });

    test('context is capped at the trained length', () async {
      final small = await meta(GgufBuilder().transformer(context: 1024));
      final p = MemoryPlanner.plan(
        metadata: small,
        fileSizeBytes: gb,
        availableBytes: 8 * gb,
      );
      expect(p.contextSize, 1024);
      final over = MemoryPlanner.plan(
        metadata: small,
        fileSizeBytes: gb,
        availableBytes: 8 * gb,
        config: const InferenceConfig(contextSize: 4096),
      );
      expect(over.warnings.join(), contains('exceeds the trained length'));
    });

    test('unknown memory skips the fit check', () {
      final p = MemoryPlanner.plan(metadata: model, fileSizeBytes: 2 * gb);
      expect(p.fitsInMemory, isNull);
      expect(p.contextSize, 4096);
      expect(p.warnings.join(), contains('unknown'));
    });

    test(
      'sparse metadata falls back to a rough estimate with a warning',
      () async {
        final sparse = await meta(
          GgufBuilder().string('general.architecture', 'llama'),
        );
        final p = MemoryPlanner.plan(
          metadata: sparse,
          fileSizeBytes: 2 * gb,
          availableBytes: 8 * gb,
        );
        expect(p.kvCacheBytes, greaterThan(0));
        expect(p.warnings.join(), contains('rough estimate'));
      },
    );

    test('embedding models batch the whole context', () async {
      final bert = await meta(
        GgufBuilder().transformer(
          arch: 'bert',
          context: 512,
          embedding: 384,
          blocks: 12,
          heads: 12,
          kvHeads: 12,
        ),
      );
      final p = MemoryPlanner.plan(
        metadata: bert,
        fileSizeBytes: 50 * mb,
        availableBytes: 4 * gb,
      );
      expect((p.contextSize, p.batchSize, p.ubatchSize), (512, 512, 512));
    });

    test('performance thread heuristic', () {
      expect(MemoryPlanner.performanceThreads(1), 1);
      expect(MemoryPlanner.performanceThreads(4), 4);
      expect(MemoryPlanner.performanceThreads(6), 4);
      expect(MemoryPlanner.performanceThreads(8), 4);
      expect(MemoryPlanner.performanceThreads(12), 6);
      expect(MemoryPlanner.performanceThreads(32), 8);
    });

    test('plan renders a readable summary', () {
      final p = MemoryPlanner.plan(
        metadata: model,
        fileSizeBytes: 2 * gb,
        availableBytes: 8 * gb,
      );
      expect(p.toString(), allOf(contains('ctx=4096'), contains('Budget')));
    });
  });

  test('LlamaEngine.planFor plans from a file on disk', () async {
    final dir = Directory.systemTemp.createTempSync('plan_for');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/m.gguf')
      ..writeAsBytesSync(GgufBuilder().transformer().build());
    final p = await LlamaEngine.planFor(f.path, availableBytes: 8 * gb);
    expect(p.availableBytes, 8 * gb);
    expect(p.contextSize, 4096);
    expect(p.weightsBytes, f.lengthSync());
  });
}
