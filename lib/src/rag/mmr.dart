import 'similarity_metrics.dart';

/// Maximal Marginal Relevance selection. Returns indices (in pick order) of up
/// to [k] items balancing [relevance] against similarity to already-picked
/// items: `lambda * relevance - (1 - lambda) * maxSimilarityToSelected`.
/// [lambda] 1 is pure relevance, 0 pure diversity.
List<int> mmrSelect({
  required List<double> relevance,
  required List<List<double>> embeddings,
  required int k,
  double lambda = 0.5,
}) {
  assert(relevance.length == embeddings.length);
  final remaining = List<int>.generate(relevance.length, (i) => i);
  final selected = <int>[];
  while (selected.length < k && remaining.isNotEmpty) {
    var best = -1;
    var bestScore = double.negativeInfinity;
    for (final i in remaining) {
      var redundancy = 0.0;
      for (final j in selected) {
        final s = SimilarityMetrics.cosine(embeddings[i], embeddings[j]);
        if (s > redundancy) redundancy = s;
      }
      final score = lambda * relevance[i] - (1 - lambda) * redundancy;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    selected.add(best);
    remaining.remove(best);
  }
  return selected;
}
