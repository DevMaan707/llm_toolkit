import 'dart:math' as math;

/// Vector similarity and distance functions over plain `List<double>`.
abstract final class SimilarityMetrics {
  static void _check(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vector length mismatch: ${a.length} vs ${b.length}');
    }
  }

  /// Dot product.
  static double dot(List<double> a, List<double> b) {
    _check(a, b);
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  /// Euclidean (L2) norm.
  static double norm(List<double> a) => math.sqrt(dot(a, a));

  /// Cosine similarity in [-1, 1]; 0 when either vector is all zeros.
  static double cosine(List<double> a, List<double> b) {
    final denom = norm(a) * norm(b);
    return denom == 0 ? 0 : dot(a, b) / denom;
  }

  /// Euclidean (L2) distance; smaller is closer.
  static double euclidean(List<double> a, List<double> b) {
    _check(a, b);
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return math.sqrt(sum);
  }

  /// Returns a unit-length copy of [a] (a zero vector stays zero).
  static List<double> normalize(List<double> a) {
    final n = norm(a);
    return n == 0 ? List<double>.of(a) : [for (final v in a) v / n];
  }
}
