import 'dart:isolate';
import 'dart:typed_data';

import '../exceptions/llm_toolkit_exceptions.dart';
import 'similarity_metrics.dart';
import 'vector_store.dart';

class _Entry {
  final String id;
  final Float32List vector; // unit length
  final String text;
  final Map<String, Object?> metadata;

  _Entry(this.id, this.vector, this.text, this.metadata);
}

/// Exact cosine search held in memory. Vectors are normalised on insert so a
/// query is a dot product per entry. Above [isolateThreshold] candidates the
/// scan runs in a background isolate to keep the UI thread free.
class InMemoryVectorStore implements VectorStore {
  final int isolateThreshold;
  final Map<String, _Entry> _entries = {};
  int? _dimensions;

  InMemoryVectorStore({this.isolateThreshold = 20000});

  /// Embedding dimension, or null while the store is empty.
  int? get dimensions => _dimensions;

  /// All records (with normalised embeddings), in insertion order.
  List<VectorRecord> snapshot() => [
    for (final e in _entries.values)
      VectorRecord(
        id: e.id,
        embedding: e.vector,
        text: e.text,
        metadata: e.metadata,
      ),
  ];

  void _checkDimension(int length) {
    if (length == 0) {
      throw const VectorStorageException('Embedding must not be empty.');
    }
    final dim = _dimensions;
    if (dim != null && dim != length) {
      throw VectorStorageException(
        'Embedding dimension mismatch: the store holds $dim-dimensional '
        'vectors but received $length. Use the same embedding model or '
        'clear the store first.',
      );
    }
  }

  @override
  Future<void> upsert(List<VectorRecord> records) async {
    for (final r in records) {
      _checkDimension(r.embedding.length);
      _dimensions ??= r.embedding.length;
    }
    for (final r in records) {
      _entries[r.id] = _Entry(
        r.id,
        Float32List.fromList(SimilarityMetrics.normalize(r.embedding)),
        r.text,
        Map.of(r.metadata),
      );
    }
  }

  @override
  Future<int> delete({List<String>? ids, MetadataFilter? filter}) async {
    final doomed = <String>{
      ...?ids?.where(_entries.containsKey),
      if (filter != null && filter.isNotEmpty)
        for (final e in _entries.values)
          if (matchesFilter(e.metadata, filter)) e.id,
    };
    doomed.forEach(_entries.remove);
    if (_entries.isEmpty) _dimensions = null;
    return doomed.length;
  }

  @override
  Future<List<ScoredRecord>> query(
    List<double> embedding, {
    int topK = 5,
    double? minScore,
    MetadataFilter? filter,
  }) async {
    if (topK <= 0 || _entries.isEmpty) return const [];
    _checkDimension(embedding.length);
    final candidates = [
      for (final e in _entries.values)
        if (matchesFilter(e.metadata, filter)) e,
    ];
    final q = Float32List.fromList(SimilarityMetrics.normalize(embedding));

    final dim = q.length;
    final matrix = Float32List(candidates.length * dim);
    for (var i = 0; i < candidates.length; i++) {
      matrix.setRange(i * dim, (i + 1) * dim, candidates[i].vector);
    }
    final ranked =
        candidates.length >= isolateThreshold
            ? await Isolate.run(() => _topK(matrix, dim, q, topK, minScore))
            : _topK(matrix, dim, q, topK, minScore);
    return [
      for (final (index, score) in ranked)
        ScoredRecord(
          VectorRecord(
            id: candidates[index].id,
            embedding: candidates[index].vector,
            text: candidates[index].text,
            metadata: candidates[index].metadata,
          ),
          score,
        ),
    ];
  }

  static List<(int, double)> _topK(
    Float32List matrix,
    int dim,
    Float32List q,
    int topK,
    double? minScore,
  ) {
    final n = matrix.length ~/ dim;
    final scored = <(int, double)>[];
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      final base = i * dim;
      for (var j = 0; j < dim; j++) {
        s += matrix[base + j] * q[j];
      }
      if (minScore == null || s >= minScore) scored.add((i, s));
    }
    scored.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return scored.length > topK ? scored.sublist(0, topK) : scored;
  }

  @override
  Future<int> count({MetadataFilter? filter}) async =>
      filter == null
          ? _entries.length
          : _entries.values
              .where((e) => matchesFilter(e.metadata, filter))
              .length;

  @override
  Future<void> clear() async {
    _entries.clear();
    _dimensions = null;
  }

  @override
  Future<void> close() async {}
}
