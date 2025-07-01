// lib/rag/models/rag_models.dart
class DocumentChunk {
  final String id;
  final String content;
  final List<double> embedding;
  final Map<String, dynamic>? metadata;
  final double? relevanceScore;

  DocumentChunk({
    required this.id,
    required this.content,
    required this.embedding,
    this.metadata,
    this.relevanceScore,
  });
}

class RagResponse {
  final String answer;
  final List<DocumentChunk> relevantChunks;
  final double confidence;
  final Map<String, dynamic>? metadata;

  RagResponse({
    required this.answer,
    required this.relevantChunks,
    required this.confidence,
    this.metadata,
  });
}

class RagConfig {
  final int maxRelevantChunks;
  final double similarityThreshold;
  final int maxTokens;
  final double temperature;
  final String? systemPrompt;
  final ChunkingConfig chunkingConfig;

  RagConfig({
    this.maxRelevantChunks = 3,
    this.similarityThreshold = 0.7,
    this.maxTokens = 500,
    this.temperature = 0.7,
    this.systemPrompt,
    ChunkingConfig? chunkingConfig,
  }) : chunkingConfig = chunkingConfig ?? ChunkingConfig();
}

class ChunkingConfig {
  final int chunkSize;
  final int chunkOverlap;
  final ChunkingStrategy strategy;

  ChunkingConfig({
    this.chunkSize = 150,
    this.chunkOverlap = 2,
    this.strategy = ChunkingStrategy.sentence,
  });
}

enum ChunkingStrategy { sentence, paragraph, fixed }
