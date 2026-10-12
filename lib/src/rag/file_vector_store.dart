import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/logging/toolkit_logger.dart';
import '../exceptions/llm_toolkit_exceptions.dart';
import 'in_memory_vector_store.dart';
import 'vector_store.dart';

/// Persistent store: an [InMemoryVectorStore] backed by a JSON-lines file
/// (`vectors.jsonl`) in [directory]. A header line records the embedding
/// dimension; each record line holds the text, metadata and a base64
/// float32 embedding. The file loads lazily on first use and every mutation
/// rewrites it atomically (temp file + rename).
class FileVectorStore implements VectorStore {
  static const _tag = 'FileVectorStore';
  static const _format = 'llm_toolkit.vectors';
  static const fileName = 'vectors.jsonl';

  final Directory directory;
  final InMemoryVectorStore _memory;

  Future<void>? _loading;
  Future<void> _writeChain = Future.value();

  FileVectorStore(this.directory, {int isolateThreshold = 20000})
    : _memory = InMemoryVectorStore(isolateThreshold: isolateThreshold);

  File get _file => File('${directory.path}/$fileName');

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final file = _file;
    if (!await file.exists()) return;
    final lines =
        await file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((l) => l.isNotEmpty)
            .toList();
    if (lines.isEmpty) return;
    try {
      final header = jsonDecode(lines.first) as Map<String, dynamic>;
      if (header['format'] != _format || header['version'] != 1) {
        throw FormatException('Unsupported store header: ${lines.first}');
      }
      final records = <VectorRecord>[];
      for (final line in lines.skip(1)) {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final bytes = base64Decode(m['vec'] as String);
        records.add(
          VectorRecord(
            id: m['id'] as String,
            text: m['text'] as String,
            metadata: Map<String, Object?>.from(m['meta'] as Map),
            embedding: bytes.buffer.asFloat32List(
              bytes.offsetInBytes,
              bytes.length ~/ 4,
            ),
          ),
        );
      }
      await _memory.upsert(records);
      ToolkitLog.debug(_tag, 'Loaded ${records.length} records');
    } on VectorStorageException {
      rethrow;
    } catch (e) {
      _loading = null;
      throw VectorStorageException(
        'Vector store file ${file.path} is corrupt or unreadable.',
        e,
      );
    }
  }

  Future<void> _persist() {
    final next = _writeChain.then((_) async {
      await directory.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      final sink = tmp.openWrite();
      try {
        sink.writeln(
          jsonEncode({
            'format': _format,
            'version': 1,
            'dimensions': _memory.dimensions,
          }),
        );
        for (final r in _memory.snapshot()) {
          final vec = Float32List.fromList(r.embedding);
          sink.writeln(
            jsonEncode({
              'id': r.id,
              'text': r.text,
              'meta': r.metadata,
              'vec': base64Encode(vec.buffer.asUint8List()),
            }),
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await tmp.rename(_file.path);
    });
    _writeChain = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> upsert(List<VectorRecord> records) async {
    await _ensureLoaded();
    await _memory.upsert(records);
    await _persist();
  }

  @override
  Future<int> delete({List<String>? ids, MetadataFilter? filter}) async {
    await _ensureLoaded();
    final n = await _memory.delete(ids: ids, filter: filter);
    if (n > 0) await _persist();
    return n;
  }

  @override
  Future<List<ScoredRecord>> query(
    List<double> embedding, {
    int topK = 5,
    double? minScore,
    MetadataFilter? filter,
  }) async {
    await _ensureLoaded();
    return _memory.query(
      embedding,
      topK: topK,
      minScore: minScore,
      filter: filter,
    );
  }

  @override
  Future<int> count({MetadataFilter? filter}) async {
    await _ensureLoaded();
    return _memory.count(filter: filter);
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    await _memory.clear();
    await _persist();
  }

  @override
  Future<void> close() => _writeChain;
}
