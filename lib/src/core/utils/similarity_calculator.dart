// lib/rag/utils/similarity_calculator.dart
import 'dart:math';

class SimilarityCalculator {
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) {
      return 0.0;
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    normA = sqrt(normA);
    normB = sqrt(normB);

    if (normA < 1e-10 || normB < 1e-10) return 0.0;
    return dotProduct / (normA * normB);
  }

  static double euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) return double.infinity;

    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      sum += pow(a[i] - b[i], 2);
    }
    return sqrt(sum);
  }
}
