import '../core/config.dart';
import '../core/inference/base_inference_engine.dart';
import '../core/logging/toolkit_logger.dart';
import '../exceptions/llm_toolkit_exceptions.dart';
import 'bm25.dart';
import 'chunking/chunk.dart';
import 'chunking/chunkers.dart';
import 'document.dart';
import 'embedding.dart';
import 'mmr.dart';
import 'prompt_builder.dart';
import 'rag_config.dart';
import 'vector_store.dart';

/// A chunk returned by retrieval.
class RetrievedChunk {
  final String id;
  final String text;
  final double score;
  final Map<String, Object?> metadata;
  final List<double> embedding;

  const RetrievedChunk({
    required this.id,
    required this.text,
    required this.score,
    required this.metadata,
    required this.embedding,
  });

  String get sourceId => metadata['sourceId'] as String? ?? '';
  int? get start => metadata['start'] as int?;
  int? get end => metadata['end'] as int?;
}

/// Indexing progress, reported per embedded batch.
class RagProgress {
  final String documentId;
  final int chunksDone;
  final int chunksTotal;

  const RagProgress(this.documentId, this.chunksDone, this.chunksTotal);
}

/// What an `addDocuments` call did.
class IngestResult {
  final int documentsAdded;
  final int documentsSkipped;
  final int chunksAdded;

  const IngestResult({
    this.documentsAdded = 0,
    this.documentsSkipped = 0,
    this.chunksAdded = 0,
  });

  IngestResult operator +(IngestResult o) => IngestResult(
    documentsAdded: documentsAdded + o.documentsAdded,
    documentsSkipped: documentsSkipped + o.documentsSkipped,
    chunksAdded: chunksAdded + o.chunksAdded,
  );
}

/// A grounded answer: the [sources] used (citation `[n]` is `sources[n-1]`)
/// and the generated text as it streams.
class RagAnswer {
  final List<RetrievedChunk> sources;
  final Stream<String> stream;

  const RagAnswer(this.sources, this.stream);
}

/// Chunk -> embed -> store, and retrieval / grounded answering on top.
class RagPipeline {
  static const _tag = 'RagPipeline';

  final Embedder embedder;
  final VectorStore store;
  final Chunker chunker;
  final TextGenerator? generator;
  final PromptBuilder promptBuilder;
  final RagConfig config;

  RagPipeline({
    required this.embedder,
    required this.store,
    this.generator,
    Chunker? chunker,
    PromptBuilder? promptBuilder,
    this.config = const RagConfig(),
  }) : chunker = chunker ?? RecursiveCharacterChunker(),
       promptBuilder =
           promptBuilder ??
           CitationPromptBuilder(maxContextChars: config.maxContextChars);

  Future<IngestResult> addDocument(
    RagDocument document, {
    void Function(RagProgress progress)? onProgress,
  }) async {
    final docHash = contentHash(document.text);
    final existing = await store.count(filter: {'sourceId': document.id});
    if (config.dedupe) {
      if (existing > 0 &&
          await store.count(
                filter: {'sourceId': document.id, 'docHash': docHash},
              ) >
              0) {
        return const IngestResult(documentsSkipped: 1);
      }
      if (await store.count(filter: {'docHash': docHash}) > 0) {
        return const IngestResult(documentsSkipped: 1);
      }
    }
    final chunks = chunker.chunk(document.text, sourceId: document.id);
    if (chunks.isEmpty) return const IngestResult(documentsSkipped: 1);

    final vectors = <List<double>>[];
    for (var i = 0; i < chunks.length; i += config.embedBatchSize) {
      final batch = chunks.sublist(
        i,
        (i + config.embedBatchSize).clamp(0, chunks.length),
      );
      final embedded = await embedder.embedBatch([
        for (final c in batch) c.text,
      ]);
      if (embedded.length != batch.length) {
        throw VectorStorageException(
          'Embedder returned ${embedded.length} vectors for ${batch.length} '
          'texts.',
        );
      }
      vectors.addAll(embedded);
      onProgress?.call(RagProgress(document.id, vectors.length, chunks.length));
    }

    if (existing > 0) await removeDocument(document.id);
    await store.upsert([
      for (var i = 0; i < chunks.length; i++)
        VectorRecord(
          id: '${document.id}#${chunks[i].index}',
          embedding: vectors[i],
          text: chunks[i].text,
          metadata: {
            ...document.metadata,
            ...chunks[i].metadata,
            'sourceId': document.id,
            'chunkIndex': chunks[i].index,
            'start': chunks[i].start,
            'end': chunks[i].end,
            'docHash': docHash,
          },
        ),
    ]);
    ToolkitLog.debug(_tag, 'Indexed ${document.id}: ${chunks.length} chunks');
    return IngestResult(documentsAdded: 1, chunksAdded: chunks.length);
  }

  Future<IngestResult> addDocuments(
    Iterable<RagDocument> documents, {
    void Function(RagProgress progress)? onProgress,
  }) async {
    var total = const IngestResult();
    for (final doc in documents) {
      total += await addDocument(doc, onProgress: onProgress);
    }
    return total;
  }

  /// Removes every chunk of [documentId]; returns how many were deleted.
  Future<int> removeDocument(String documentId) =>
      store.delete(filter: {'sourceId': documentId});

  Future<int> get chunkCount => store.count();

  /// Most relevant chunks for [query], best first.
  Future<List<RetrievedChunk>> retrieve(
    String query, {
    int? topK,
    MetadataFilter? filter,
  }) async {
    final k = topK ?? config.topK;
    final rerank = config.useMmr || config.hybrid;
    final matches = await store.query(
      await embedder.embed(query),
      topK: rerank ? k * config.candidateMultiplier : k,
      minScore: config.minScore,
      filter: filter,
    );
    if (matches.isEmpty) return const [];

    var scores = [for (final m in matches) m.score];
    if (config.hybrid) {
      final keyword = Bm25Scorer([
        for (final m in matches) m.record.text,
      ]).score(query);
      final maxKeyword = keyword.reduce((a, b) => a > b ? a : b);
      scores = [
        for (var i = 0; i < matches.length; i++)
          config.hybridAlpha * scores[i] +
              (1 - config.hybridAlpha) *
                  (maxKeyword == 0 ? 0 : keyword[i] / maxKeyword),
      ];
    }

    final order = List<int>.generate(matches.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final picked =
        config.useMmr
            ? mmrSelect(
              relevance: [for (final i in order) scores[i]],
              embeddings: [for (final i in order) matches[i].record.embedding],
              k: k,
              lambda: config.mmrLambda,
            ).map((p) => order[p]).toList()
            : order.take(k).toList();

    return [
      for (final i in picked)
        RetrievedChunk(
          id: matches[i].record.id,
          text: matches[i].record.text,
          score: scores[i],
          metadata: matches[i].record.metadata,
          embedding: matches[i].record.embedding,
        ),
    ];
  }

  /// Retrieves context for [query] and streams a grounded answer.
  Future<RagAnswer> answer(
    String query, {
    GenerationParams? params,
    MetadataFilter? filter,
  }) async {
    final gen = generator;
    if (gen == null) {
      throw const InferenceException(
        'RagPipeline.answer requires a TextGenerator.',
      );
    }
    final sources = await retrieve(query, filter: filter);
    final prompt = promptBuilder.build(query, sources);
    return RagAnswer(
      sources,
      gen.generateText(prompt, params ?? config.generation),
    );
  }
}
