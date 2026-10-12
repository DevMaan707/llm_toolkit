/// A stored chunk: its embedding, text and arbitrary JSON-encodable metadata.
class VectorRecord {
  final String id;
  final List<double> embedding;
  final String text;
  final Map<String, Object?> metadata;

  const VectorRecord({
    required this.id,
    required this.embedding,
    required this.text,
    this.metadata = const {},
  });
}

/// A [VectorRecord] returned from a query together with its similarity score.
class ScoredRecord {
  final VectorRecord record;
  final double score;

  const ScoredRecord(this.record, this.score);
}

/// Equality filter over metadata. A list value matches if the metadata value
/// equals any element; all entries must match.
typedef MetadataFilter = Map<String, Object?>;

/// Whether [metadata] satisfies [filter].
bool matchesFilter(Map<String, Object?> metadata, MetadataFilter? filter) {
  if (filter == null || filter.isEmpty) return true;
  for (final MapEntry(:key, value: want) in filter.entries) {
    final have = metadata[key];
    final ok = want is List ? want.contains(have) : have == want;
    if (!ok) return false;
  }
  return true;
}

/// Storage and similarity search over embedded chunks.
abstract interface class VectorStore {
  /// Inserts or replaces records by id. Throws `VectorStorageException` if an
  /// embedding's dimension differs from what the store already holds.
  Future<void> upsert(List<VectorRecord> records);

  /// Removes records by [ids] and/or matching [filter]; returns how many.
  Future<int> delete({List<String>? ids, MetadataFilter? filter});

  /// Top [topK] records by cosine similarity (best first) at or above
  /// [minScore] that satisfy [filter].
  Future<List<ScoredRecord>> query(
    List<double> embedding, {
    int topK = 5,
    double? minScore,
    MetadataFilter? filter,
  });

  /// Number of records, optionally only those matching [filter].
  Future<int> count({MetadataFilter? filter});

  Future<void> clear();

  Future<void> close();
}
