import 'dart:async';

import 'models/rag_models.dart';

abstract class RagEngine {
  Future<void> initialize();
  Future<void> dispose();

  Future<void> addDocument(
    String id,
    String content,
    Map<String, dynamic>? metadata,
  );
  Future<void> removeDocument(String id);
  Future<List<DocumentChunk>> getDocuments();

  Future<RagResponse> query(String query, {RagConfig? config});

  Future<List<double>> createEmbedding(String text);
  Future<List<List<double>>> createBatchEmbeddings(List<String> texts);
}
