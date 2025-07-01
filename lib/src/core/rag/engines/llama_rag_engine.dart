// lib/rag/engines/llama_rag_engine.dart
import 'dart:io';
import 'dart:math';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import '../../utils/similarity_calculator.dart';

import '../models/rag_models.dart';
import '../rag_engine.dart';

class LlamaRagEngine implements RagEngine {
  final String embeddingModelPath;
  final String llmModelPath;
  final String libraryPath;

  Llama? _embeddingModel;
  Llama? _llmModel;
  final List<DocumentChunk> _documentChunks = [];
  bool _isInitialized = false;

  LlamaRagEngine({
    required this.embeddingModelPath,
    required this.llmModelPath,
    required this.libraryPath,
  });

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Llama.libraryPath = libraryPath;

      // Initialize embedding model
      final embeddingModelParams = ModelParams();
      final embeddingContextParams =
          ContextParams()
            ..embeddings = true
            ..nCtx = 2048;

      _embeddingModel = Llama(
        embeddingModelPath,
        embeddingModelParams,
        embeddingContextParams,
        SamplerParams(),
      );

      // Initialize LLM model
      final llmModelParams = ModelParams();
      final llmContextParams =
          ContextParams()
            ..nPredict = 500
            ..nCtx = 4096;
      final llmSamplerParams =
          SamplerParams()
            ..temp = 0.7
            ..topP = 0.95;

      _llmModel = Llama(
        llmModelPath,
        llmModelParams,
        llmContextParams,
        llmSamplerParams,
      );

      _isInitialized = true;
      print("✅ Llama RAG Engine initialized successfully");
    } catch (e) {
      print("❌ Failed to initialize Llama RAG Engine: $e");
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    _embeddingModel?.dispose();
    _llmModel?.dispose();
    _embeddingModel = null;
    _llmModel = null;
    _isInitialized = false;
  }

  @override
  Future<void> addDocument(
    String id,
    String content,
    Map<String, dynamic>? metadata,
  ) async {
    if (!_isInitialized) throw Exception("Engine not initialized");

    final chunker = TextChunker(maxChunkSize: 150, overlapSentences: 2);

    final chunks = chunker.chunk(content);
    print("📄 Document split into ${chunks.length} chunks");

    for (int i = 0; i < chunks.length; i++) {
      final chunkId = "${id}_chunk_$i";
      final embedding = await createEmbedding(chunks[i]);

      final documentChunk = DocumentChunk(
        id: chunkId,
        content: chunks[i],
        embedding: embedding,
        metadata: {
          ...?metadata,
          'documentId': id,
          'chunkIndex': i,
          'totalChunks': chunks.length,
        },
      );

      _documentChunks.add(documentChunk);
    }

    print("✅ Added ${chunks.length} chunks for document: $id");
  }

  @override
  Future<void> removeDocument(String id) async {
    _documentChunks.removeWhere((chunk) => chunk.metadata?['documentId'] == id);
    print("🗑️ Removed document: $id");
  }

  @override
  Future<List<DocumentChunk>> getDocuments() async {
    return List.from(_documentChunks);
  }

  @override
  Future<List<double>> createEmbedding(String text) async {
    if (_embeddingModel == null)
      throw Exception("Embedding model not initialized");

    try {
      return _embeddingModel!.getEmbeddings(text);
    } catch (e) {
      print("❌ Error creating embedding: $e");
      rethrow;
    }
  }

  @override
  Future<List<List<double>>> createBatchEmbeddings(List<String> texts) async {
    final embeddings = <List<double>>[];

    for (int i = 0; i < texts.length; i++) {
      if (i % 10 == 0) {
        print("📊 Processing embedding ${i + 1}/${texts.length}");
      }
      embeddings.add(await createEmbedding(texts[i]));
    }

    return embeddings;
  }

  @override
  Future<RagResponse> query(String query, {RagConfig? config}) async {
    if (!_isInitialized) throw Exception("Engine not initialized");

    config ??= RagConfig();

    print("🔍 Processing query: \"$query\"");

    // Step 1: Create query embedding
    final queryEmbedding = await createEmbedding(query);

    // Step 2: Find relevant chunks
    final relevantChunks = _findRelevantChunks(
      queryEmbedding,
      config.maxRelevantChunks,
      config.similarityThreshold,
    );

    print("📋 Found ${relevantChunks.length} relevant chunks");

    // Step 3: Generate answer
    final answer = await _generateAnswer(query, relevantChunks, config);

    return RagResponse(
      answer: answer,
      relevantChunks: relevantChunks,
      confidence: _calculateConfidence(relevantChunks),
    );
  }

  List<DocumentChunk> _findRelevantChunks(
    List<double> queryEmbedding,
    int maxChunks,
    double threshold,
  ) {
    final chunksWithSimilarity = <DocumentChunk>[];

    for (final chunk in _documentChunks) {
      final similarity = SimilarityCalculator.cosineSimilarity(
        queryEmbedding,
        chunk.embedding,
      );

      if (similarity >= threshold) {
        chunksWithSimilarity.add(
          DocumentChunk(
            id: chunk.id,
            content: chunk.content,
            embedding: chunk.embedding,
            metadata: chunk.metadata,
            relevanceScore: similarity,
          ),
        );
      }
    }

    // Sort by relevance score and take top chunks
    chunksWithSimilarity.sort(
      (a, b) => (b.relevanceScore ?? 0).compareTo(a.relevanceScore ?? 0),
    );

    return chunksWithSimilarity.take(maxChunks).toList();
  }

  Future<String> _generateAnswer(
    String query,
    List<DocumentChunk> relevantChunks,
    RagConfig config,
  ) async {
    if (_llmModel == null) throw Exception("LLM model not initialized");

    final context = relevantChunks.map((chunk) => chunk.content).join("\n\n");

    final systemPrompt =
        config.systemPrompt ??
        """
You are a helpful assistant that answers questions based on the provided context.
Use only the information from the context to answer the question.
If the context doesn't contain enough information, say so clearly.
Be concise and accurate in your response.
""";

    final prompt = """
<start_of_turn>user
$systemPrompt

Context information:
$context

Question: $query
<end_of_turn>

<start_of_turn>model
""";

    print("🤖 Generating answer...");
    _llmModel!.setPrompt(prompt);

    final answerBuffer = StringBuffer();
    try {
      while (true) {
        var (token, done) = _llmModel!.getNext();
        answerBuffer.write(token);
        if (done) break;
      }
    } catch (e) {
      print("❌ Error during generation: $e");
      return "Sorry, I encountered an error while generating the answer.";
    }

    return answerBuffer.toString().trim();
  }

  double _calculateConfidence(List<DocumentChunk> chunks) {
    if (chunks.isEmpty) return 0.0;

    final avgScore =
        chunks.map((c) => c.relevanceScore ?? 0.0).reduce((a, b) => a + b) /
        chunks.length;

    return avgScore;
  }
}
