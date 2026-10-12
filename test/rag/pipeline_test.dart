import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/config.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';
import 'package:llm_toolkit/src/rag/rag.dart';

/// Deterministic hashing bag-of-words embedder.
class FakeEmbedder implements Embedder {
  static const dims = 64;
  int calls = 0;

  @override
  int? get embeddingDimensions => dims;

  @override
  Future<List<double>> embed(String text) async {
    calls++;
    final v = List<double>.filled(dims, 0);
    for (final t in tokenize(text)) {
      var h = 7;
      for (final c in t.codeUnits) {
        h = (h * 31 + c) & 0x7fffffff;
      }
      v[h % dims] += 1;
    }
    return v;
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async => [
    for (final t in texts) await embed(t),
  ];
}

class FakeGenerator implements TextGenerator {
  String? lastPrompt;

  @override
  Stream<String> generateText(String prompt, GenerationParams params) {
    lastPrompt = prompt;
    return Stream.fromIterable(['The ', 'answer ', '[1]']);
  }
}

const cats =
    'Cats are small carnivorous mammals. They purr and groom '
    'themselves often. Cats sleep most of the day.';
const space =
    'Rockets burn fuel to reach orbit. Satellites orbit the earth '
    'and relay signals. Space agencies launch rockets regularly.';

void main() {
  late FakeEmbedder embedder;
  late RagPipeline pipeline;

  RagPipeline build({
    RagConfig config = const RagConfig(),
    VectorStore? store,
  }) => RagPipeline(
    embedder: embedder,
    store: store ?? InMemoryVectorStore(),
    generator: FakeGenerator(),
    chunker: SentenceChunker(chunkSize: 70),
    config: config,
  );

  setUp(() {
    embedder = FakeEmbedder();
    pipeline = build();
  });

  test(
    'indexes, retrieves the relevant document and reports progress',
    () async {
      final progress = <RagProgress>[];
      final res = await pipeline.addDocuments([
        RagDocument(id: 'cats', text: cats),
        RagDocument(id: 'space', text: space),
      ], onProgress: progress.add);
      expect(res.documentsAdded, 2);
      expect(res.chunksAdded, await pipeline.chunkCount);
      expect(progress.last.chunksDone, progress.last.chunksTotal);

      final hits = await pipeline.retrieve('rockets orbit', topK: 2);
      expect(hits.first.sourceId, 'space');
      expect(hits.first.score, greaterThan(hits.last.score - 1e-9));
      final h = hits.first;
      expect(space.substring(h.start!, h.end!), h.text);
    },
  );

  test('dedupes identical content and replaces changed documents', () async {
    await pipeline.addDocument(RagDocument(id: 'a', text: cats));
    final n = await pipeline.chunkCount;
    final again = await pipeline.addDocument(RagDocument(id: 'a', text: cats));
    final copy = await pipeline.addDocument(RagDocument(id: 'b', text: cats));
    expect(again.documentsSkipped + copy.documentsSkipped, 2);
    expect(await pipeline.chunkCount, n);

    await pipeline.addDocument(RagDocument(id: 'a', text: space));
    final hits = await pipeline.retrieve('cats purr');
    expect(hits.every((h) => h.sourceId == 'a'), isTrue);
    expect(hits.any((h) => h.text.contains('Cats')), isFalse);
  });

  test('removeDocument deletes only that document', () async {
    await pipeline.addDocuments([
      RagDocument(id: 'cats', text: cats),
      RagDocument(id: 'space', text: space),
    ]);
    expect(await pipeline.removeDocument('cats'), greaterThan(0));
    final hits = await pipeline.retrieve('cats purr', topK: 10);
    expect(hits.every((h) => h.sourceId == 'space'), isTrue);
  });

  test('metadata filter limits retrieval', () async {
    await pipeline.addDocuments([
      RagDocument(id: 'cats', text: cats, metadata: {'topic': 'pets'}),
      RagDocument(id: 'space', text: space, metadata: {'topic': 'science'}),
    ]);
    final hits = await pipeline.retrieve(
      'anything',
      topK: 10,
      filter: {'topic': 'pets'},
    );
    expect(hits.every((h) => h.sourceId == 'cats'), isTrue);
  });

  test(
    'MMR returns diverse results and hybrid rewards keyword overlap',
    () async {
      final p = build(
        config: const RagConfig(useMmr: true, mmrLambda: 0.3, hybrid: true),
      );
      await p.addDocuments([
        RagDocument(id: 'cats', text: cats),
        RagDocument(id: 'space', text: space),
      ]);
      final hits = await p.retrieve('cats rockets', topK: 2);
      expect(hits, hasLength(2));
      expect({for (final h in hits) h.sourceId}, {'cats', 'space'});
    },
  );

  test(
    'answer builds a cited prompt and returns sources with the stream',
    () async {
      final gen = FakeGenerator();
      final p = RagPipeline(
        embedder: embedder,
        store: InMemoryVectorStore(),
        generator: gen,
        chunker: SentenceChunker(chunkSize: 70),
      );
      await p.addDocument(RagDocument(id: 'space', text: space));
      final ans = await p.answer('How do rockets reach orbit?');
      expect(ans.sources, isNotEmpty);
      expect(await ans.stream.join(), 'The answer [1]');
      expect(gen.lastPrompt, contains('[1] '));
      expect(gen.lastPrompt, contains('Question: How do rockets reach orbit?'));
      expect(gen.lastPrompt, contains(ans.sources.first.text));
    },
  );

  test('answer without generator throws', () async {
    final p = RagPipeline(embedder: embedder, store: InMemoryVectorStore());
    expect(() => p.answer('x'), throwsA(isA<Exception>()));
  });

  test('works with a persistent store across restarts', () async {
    final dir = Directory.systemTemp.createTempSync('rag_pipe_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final first = build(store: FileVectorStore(dir));
    await first.addDocument(RagDocument(id: 'space', text: space));
    await first.store.close();

    final second = build(store: FileVectorStore(dir));
    final hits = await second.retrieve('rockets orbit');
    expect(hits.first.sourceId, 'space');
    final dup = await second.addDocument(RagDocument(id: 'space', text: space));
    expect(dup.documentsSkipped, 1);
  });

  group('CachingEmbedder / EmbeddingFunction', () {
    test('caches singles and batches, evicts LRU', () async {
      final inner = FakeEmbedder();
      final c = CachingEmbedder(inner, capacity: 2);
      await c.embed('a');
      await c.embed('a');
      expect(inner.calls, 1);
      expect(c.hits, 1);
      await c.embedBatch(['a', 'b', 'b', 'c']);
      expect(inner.calls, 3); // b and c computed once each
      expect(c.size, 2);
      await c.embed('a'); // evicted by b,c
      expect(inner.calls, 4);
    });

    test('closure adapter', () async {
      final e = EmbeddingFunction(
        (t) async => [t.length.toDouble(), 1],
        embeddingDimensions: 2,
      );
      expect(await e.embedBatch(['ab', 'abc']), [
        [2.0, 1.0],
        [3.0, 1.0],
      ]);
      expect(e.embeddingDimensions, 2);
    });
  });

  group('loaders', () {
    test('plain text, markdown front matter, json', () async {
      final plain = await const PlainTextLoader(id: 'p').load('hi');
      expect(plain.single.id, 'p');

      final md = await const MarkdownLoader().load(
        '---\ntitle: T\n---\n# Body',
      );
      expect(md.single.metadata['title'], 'T');
      expect(md.single.text, '# Body');

      final json = await const JsonLoader().load(
        '[{"id":"1","text":"one","lang":"en","nested":{"a":1}},"two"]',
      );
      expect(json, hasLength(2));
      expect(json.first.id, '1');
      expect(json.first.metadata, {'lang': 'en'});
      expect(json.last.text, 'two');
      expect(
        () => const JsonLoader().load('{"x":1}'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
