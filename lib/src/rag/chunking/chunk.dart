/// A slice of a source document. `source.substring(start, end) == text`.
class Chunk {
  final String text;
  final int index;
  final int start;
  final int end;
  final String sourceId;
  final Map<String, Object?> metadata;

  const Chunk({
    required this.text,
    required this.index,
    required this.start,
    required this.end,
    this.sourceId = '',
    this.metadata = const {},
  });

  Chunk copyWith({
    int? index,
    int? start,
    int? end,
    Map<String, Object?>? metadata,
  }) => Chunk(
    text: text,
    index: index ?? this.index,
    start: start ?? this.start,
    end: end ?? this.end,
    sourceId: sourceId,
    metadata: metadata ?? this.metadata,
  );

  @override
  String toString() => 'Chunk(#$index [$start,$end) ${text.length} chars)';
}

/// Splits text into [Chunk]s of at most `chunkSize` characters.
abstract class Chunker {
  /// Maximum characters per chunk.
  final int chunkSize;

  /// Characters shared between consecutive chunks (best effort for chunkers
  /// that split on boundaries: only whole units that fit are repeated).
  final int overlap;

  Chunker({required this.chunkSize, this.overlap = 0}) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be positive');
    }
    if (overlap < 0 || overlap >= chunkSize) {
      throw ArgumentError.value(
        overlap,
        'overlap',
        'must be >= 0 and < chunkSize ($chunkSize)',
      );
    }
  }

  List<Chunk> chunk(String text, {String sourceId = ''});
}
