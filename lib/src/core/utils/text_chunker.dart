import '../rag/models/rag_models.dart';

class TextChunker {
  final int maxChunkSize;
  final int overlapSentences;
  final ChunkingStrategy strategy;

  TextChunker({
    required this.maxChunkSize,
    this.overlapSentences = 1,
    this.strategy = ChunkingStrategy.sentence,
  });

  List<String> chunk(String text) {
    switch (strategy) {
      case ChunkingStrategy.sentence:
        return _chunkBySentence(text);
      case ChunkingStrategy.paragraph:
        return _chunkByParagraph(text);
      case ChunkingStrategy.fixed:
        return _chunkByFixedSize(text);
    }
  }

  List<String> _chunkBySentence(String text) {
    final sentences =
        text
            .replaceAll('\n', ' ')
            .split(RegExp(r'(?<=[.!?])\s+'))
            .where((s) => s.trim().isNotEmpty)
            .toList();

    final chunks = <String>[];
    var currentChunk = <String>[];
    var currentLength = 0;

    for (final sentence in sentences) {
      if (currentLength + sentence.length > maxChunkSize &&
          currentChunk.isNotEmpty) {
        chunks.add(currentChunk.join(' '));

        if (overlapSentences > 0 && currentChunk.length >= overlapSentences) {
          currentChunk = currentChunk.sublist(
            currentChunk.length - overlapSentences,
          );
          currentLength = currentChunk.join(' ').length;
        } else {
          currentChunk = [];
          currentLength = 0;
        }
      }

      currentChunk.add(sentence);
      currentLength += sentence.length + 1;
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.join(' '));
    }

    return chunks;
  }

  List<String> _chunkByParagraph(String text) {
    return text.split('\n\n').where((p) => p.trim().isNotEmpty).toList();
  }

  List<String> _chunkByFixedSize(String text) {
    final chunks = <String>[];
    for (int i = 0; i < text.length; i += maxChunkSize) {
      final end =
          (i + maxChunkSize < text.length) ? i + maxChunkSize : text.length;
      chunks.add(text.substring(i, end));
    }
    return chunks;
  }
}
