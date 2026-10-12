import 'dart:math' as math;

final _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Lower-cased alphanumeric tokens of [text].
List<String> tokenize(String text) => [
  for (final m in _wordPattern.allMatches(text)) m.group(0)!.toLowerCase(),
];

/// Okapi BM25 over a small in-memory corpus (the retrieval candidates).
class Bm25Scorer {
  final double k1;
  final double b;
  final List<Map<String, int>> _termFreqs = [];
  final List<int> _lengths = [];
  final Map<String, int> _docFreq = {};
  late final double _avgLength;

  Bm25Scorer(List<String> documents, {this.k1 = 1.5, this.b = 0.75}) {
    for (final doc in documents) {
      final tf = <String, int>{};
      final tokens = tokenize(doc);
      for (final t in tokens) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      for (final t in tf.keys) {
        _docFreq[t] = (_docFreq[t] ?? 0) + 1;
      }
      _termFreqs.add(tf);
      _lengths.add(tokens.length);
    }
    _avgLength =
        _lengths.isEmpty
            ? 0
            : _lengths.reduce((a, c) => a + c) / _lengths.length;
  }

  /// BM25 score of every document for [query], in corpus order.
  List<double> score(String query) {
    final terms = tokenize(query).toSet();
    final n = _termFreqs.length;
    return [
      for (var i = 0; i < n; i++)
        _scoreDoc(terms, _termFreqs[i], _lengths[i], n),
    ];
  }

  double _scoreDoc(Set<String> terms, Map<String, int> tf, int len, int n) {
    var total = 0.0;
    for (final term in terms) {
      final f = tf[term];
      if (f == null) continue;
      final df = _docFreq[term]!;
      final idf = math.log(1 + (n - df + 0.5) / (df + 0.5));
      final norm = _avgLength == 0 ? 1.0 : 1 - b + b * len / _avgLength;
      total += idf * f * (k1 + 1) / (f + k1 * norm);
    }
    return total;
  }
}
