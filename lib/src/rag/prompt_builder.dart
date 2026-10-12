import 'rag_pipeline.dart';

/// Builds the final prompt from the question and retrieved chunks.
abstract interface class PromptBuilder {
  String build(String question, List<RetrievedChunk> sources);
}

/// Numbers each source as `[n]` and asks the model to answer only from them
/// and cite by number. Sources beyond [maxContextChars] are dropped.
class CitationPromptBuilder implements PromptBuilder {
  final int maxContextChars;
  final String instructions;

  const CitationPromptBuilder({
    this.maxContextChars = 6000,
    this.instructions =
        'Answer the question using only the numbered context below. Cite '
            'sources inline like [1]. If the context does not contain the '
            'answer, say you do not know.',
  });

  @override
  String build(String question, List<RetrievedChunk> sources) {
    final context = StringBuffer();
    for (var i = 0; i < sources.length; i++) {
      final entry = '[${i + 1}] ${sources[i].text}\n\n';
      if (i > 0 && context.length + entry.length > maxContextChars) break;
      context.write(entry);
    }
    return '$instructions\n\nContext:\n${context.toString().trimRight()}'
        '\n\nQuestion: $question\nAnswer:';
  }
}
