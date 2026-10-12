import '../core/config.dart';

/// Tunables for [RagPipeline].
class RagConfig {
  /// Chunks returned by `retrieve` / used as context by `answer`.
  final int topK;

  /// Drop vector matches scoring below this cosine similarity.
  final double? minScore;

  /// Re-rank with Maximal Marginal Relevance to reduce redundant chunks.
  final bool useMmr;

  /// MMR trade-off: 1 = relevance only, 0 = diversity only.
  final double mmrLambda;

  /// Blend BM25 keyword scores into the ranking.
  final bool hybrid;

  /// Weight of the vector score when [hybrid]; the keyword score gets the rest.
  final double hybridAlpha;

  /// Re-ranking steps look at `topK * candidateMultiplier` vector matches.
  final int candidateMultiplier;

  /// Texts per `embedBatch` call while indexing.
  final int embedBatchSize;

  /// Skip documents whose content is already indexed.
  final bool dedupe;

  /// Context budget (characters) for the default prompt builder.
  final int maxContextChars;

  /// Sampling settings used by `answer`.
  final GenerationParams generation;

  const RagConfig({
    this.topK = 4,
    this.minScore,
    this.useMmr = false,
    this.mmrLambda = 0.5,
    this.hybrid = false,
    this.hybridAlpha = 0.7,
    this.candidateMultiplier = 4,
    this.embedBatchSize = 16,
    this.dedupe = true,
    this.maxContextChars = 6000,
    this.generation = const GenerationParams.precise(),
  }) : assert(topK > 0),
       assert(candidateMultiplier >= 1),
       assert(embedBatchSize > 0),
       assert(mmrLambda >= 0 && mmrLambda <= 1),
       assert(hybridAlpha >= 0 && hybridAlpha <= 1);
}
