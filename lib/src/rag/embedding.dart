import 'dart:collection';

import 'package:crypto/crypto.dart';

import '../core/inference/base_inference_engine.dart';

/// Hex SHA-1 of [text], used for cache keys and content dedupe.
String contentHash(String text) => sha1.convert(text.codeUnits).toString();

/// Adapts a plain closure (a remote API, a test fake, ...) to [Embedder].
class EmbeddingFunction implements Embedder {
  final Future<List<double>> Function(String text) _embed;
  final Future<List<List<double>>> Function(List<String> texts)? _embedBatch;

  @override
  final int? embeddingDimensions;

  /// [batch] is optional; without it batches run [embed] sequentially.
  EmbeddingFunction(
    Future<List<double>> Function(String text) embed, {
    Future<List<List<double>>> Function(List<String> texts)? batch,
    this.embeddingDimensions,
  }) : _embed = embed,
       _embedBatch = batch;

  @override
  Future<List<double>> embed(String text) => _embed(text);

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final batch = _embedBatch;
    if (batch != null) return batch(texts);
    return [for (final t in texts) await _embed(t)];
  }
}

/// Wraps an [Embedder] with an LRU cache keyed by the hash of the text.
class CachingEmbedder implements Embedder {
  final Embedder inner;
  final int capacity;
  final LinkedHashMap<String, List<double>> _cache = LinkedHashMap();

  int hits = 0;
  int misses = 0;

  CachingEmbedder(this.inner, {this.capacity = 1024})
    : assert(capacity > 0, 'capacity must be positive');

  @override
  int? get embeddingDimensions => inner.embeddingDimensions;

  int get size => _cache.length;

  void clear() => _cache.clear();

  List<double>? _get(String key) {
    final v = _cache.remove(key);
    if (v != null) _cache[key] = v;
    return v;
  }

  void _put(String key, List<double> value) {
    _cache.remove(key);
    _cache[key] = value;
    if (_cache.length > capacity) _cache.remove(_cache.keys.first);
  }

  @override
  Future<List<double>> embed(String text) async {
    final key = contentHash(text);
    final cached = _get(key);
    if (cached != null) {
      hits++;
      return cached;
    }
    misses++;
    final v = await inner.embed(text);
    _put(key, v);
    return v;
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final keys = [for (final t in texts) contentHash(t)];
    final results = List<List<double>?>.filled(texts.length, null);
    final missing = <String, String>{}; // key -> text, deduplicated
    for (var i = 0; i < texts.length; i++) {
      final cached = _get(keys[i]);
      if (cached != null) {
        hits++;
        results[i] = cached;
      } else {
        misses++;
        missing[keys[i]] = texts[i];
      }
    }
    if (missing.isNotEmpty) {
      final computed = await inner.embedBatch(missing.values.toList());
      final byKey = <String, List<double>>{};
      var j = 0;
      for (final key in missing.keys) {
        byKey[key] = computed[j++];
        _put(key, byKey[key]!);
      }
      for (var i = 0; i < texts.length; i++) {
        results[i] ??= byKey[keys[i]];
      }
    }
    return [for (final r in results) r!];
  }
}
