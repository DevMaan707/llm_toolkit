import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/rag/rag.dart';

void main() {
  group('SimilarityMetrics', () {
    test('cosine', () {
      expect(SimilarityMetrics.cosine([1, 0], [1, 0]), closeTo(1, 1e-12));
      expect(SimilarityMetrics.cosine([1, 0], [0, 1]), closeTo(0, 1e-12));
      expect(SimilarityMetrics.cosine([1, 0], [-2, 0]), closeTo(-1, 1e-12));
      expect(SimilarityMetrics.cosine([1, 1], [2, 2]), closeTo(1, 1e-12));
      expect(SimilarityMetrics.cosine([0, 0], [1, 1]), 0);
    });

    test('dot, euclidean, normalize', () {
      expect(SimilarityMetrics.dot([1, 2, 3], [4, 5, 6]), 32);
      expect(SimilarityMetrics.euclidean([0, 0], [3, 4]), 5);
      final n = SimilarityMetrics.normalize([3, 4]);
      expect(n, [closeTo(0.6, 1e-12), closeTo(0.8, 1e-12)]);
    });

    test('length mismatch throws', () {
      expect(() => SimilarityMetrics.dot([1], [1, 2]), throwsArgumentError);
    });
  });

  group('mmrSelect', () {
    final emb = [
      [1.0, 0.0],
      [0.99, 0.14], // near-duplicate of 0
      [0.0, 1.0], // diverse
    ];
    final rel = [0.9, 0.88, 0.5];

    test('lambda 1 is pure relevance', () {
      expect(mmrSelect(relevance: rel, embeddings: emb, k: 2, lambda: 1), [
        0,
        1,
      ]);
    });

    test('lower lambda prefers diversity', () {
      expect(mmrSelect(relevance: rel, embeddings: emb, k: 2, lambda: 0.5), [
        0,
        2,
      ]);
    });

    test('k larger than items returns all', () {
      expect(mmrSelect(relevance: rel, embeddings: emb, k: 10), hasLength(3));
    });
  });

  group('Bm25Scorer', () {
    final docs = [
      'the cat sat on the mat',
      'dogs chase cats in the park',
      'quantum chromodynamics explained',
    ];

    test('ranks matching document highest, zero for no match', () {
      final s = Bm25Scorer(docs).score('quantum physics');
      expect(s[2], greaterThan(0));
      expect(s[0], 0);
      expect(s[1], 0);
    });

    test('rarer terms weigh more and repetition saturates', () {
      final scorer = Bm25Scorer([
        'apple banana',
        'apple apple apple',
        'cherry',
      ]);
      final s = scorer.score('apple');
      expect(s[1], greaterThan(s[0]));
      expect(s[1], lessThan(s[0] * 3));
      final idfRare = Bm25Scorer(['x y', 'x z', 'x w', 'q']).score('q')[3];
      final idfCommon = Bm25Scorer(['x y', 'x z', 'x w', 'q']).score('x')[0];
      expect(idfRare, greaterThan(idfCommon));
    });

    test('known value for single term', () {
      // N=2, df=1: idf = ln(1 + 1.5/1.5) = ln 2; tf=1, len=avg => norm=1
      final s = Bm25Scorer(['alpha', 'beta']).score('alpha');
      expect(s[0], closeTo(math.log(2) * 2.5 / 2.5, 1e-9));
    });

    test('tokenizer lowercases and splits punctuation', () {
      expect(tokenize('Hello, World-42!'), ['hello', 'world', '42']);
    });
  });
}
