import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../exceptions/llm_toolkit_exceptions.dart';
import '../logging/toolkit_logger.dart';
import '../model_info.dart';

const _tag = 'ModelStore';

/// A model file found in the [ModelStore].
class StoredModel {
  final String path;
  final int sizeBytes;
  final DateTime modified;

  /// Last time [ModelStore.markUsed] was called for it, if ever.
  final DateTime? lastUsed;

  const StoredModel({
    required this.path,
    required this.sizeBytes,
    required this.modified,
    this.lastUsed,
  });

  String get filename => p.basename(path);
  ModelFormat? get format => ModelFormat.fromFilename(path);

  @override
  String toString() => 'StoredModel($path, ${formatBytes(sizeBytes)})';
}

/// Manages the on-disk models directory.
///
/// Files live in `<root>/<owner>__<repo>/<file>`; partial downloads
/// (`*.part`) are ignored by [list] and removed by [clearPartials].
class ModelStore {
  static const _indexName = '.usage.json';

  final Directory root;

  ModelStore(this.root);

  /// `<application documents>/models`.
  static Future<ModelStore> defaultStore() async {
    final docs = await getApplicationDocumentsDirectory();
    return ModelStore(Directory(p.join(docs.path, 'models')));
  }

  /// Destination path for [filename] of [modelId]. Rejects paths that would
  /// escape the store.
  String pathFor(String modelId, String filename) {
    final folder = modelId.replaceAll(RegExp(r'[\\/:]+'), '__');
    final relative = p.normalize(p.join(folder, filename));
    if (p.isAbsolute(filename) ||
        relative.startsWith('..') ||
        p.split(relative).length < 2) {
      throw ArgumentError.value(filename, 'filename', 'Unsafe model path');
    }
    return p.join(root.path, relative);
  }

  Future<bool> contains(String modelId, String filename) =>
      File(pathFor(modelId, filename)).exists();

  /// All model files in the store, most recently used first.
  Future<List<StoredModel>> list() async {
    if (!await root.exists()) return [];
    final usage = await _readUsage();
    final models = <StoredModel>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File || ModelFormat.fromFilename(entity.path) == null) {
        continue;
      }
      final stat = await entity.stat();
      final key = p.relative(entity.path, from: root.path);
      models.add(
        StoredModel(
          path: entity.path,
          sizeBytes: stat.size,
          modified: stat.modified,
          lastUsed: usage[key],
        ),
      );
    }
    models.sort((a, b) {
      final x = a.lastUsed ?? a.modified;
      final y = b.lastUsed ?? b.modified;
      return y.compareTo(x);
    });
    return models;
  }

  /// Bytes used by model files and partial downloads.
  Future<int> totalSize() async {
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File && !p.basename(entity.path).startsWith('.usage')) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> markUsed(String path, {DateTime? at}) async {
    final usage = await _readUsage();
    usage[p.relative(path, from: root.path)] = at ?? DateTime.now();
    await _writeUsage(usage);
  }

  /// Deletes a model file; returns whether it existed.
  Future<bool> delete(String path) async {
    final file = File(path);
    if (!p.isWithin(root.path, file.path)) {
      throw ModelProviderException('$path is outside the model store');
    }
    final existed = await file.exists();
    if (existed) await file.delete();
    final usage = await _readUsage();
    if (usage.remove(p.relative(path, from: root.path)) != null) {
      await _writeUsage(usage);
    }
    await _pruneEmptyParents(file.parent);
    return existed;
  }

  /// Deletes least recently used models until the store holds at most
  /// [maxBytes] of models. Returns the deleted paths.
  Future<List<String>> trimTo(
    int maxBytes, {
    Set<String> keep = const {},
  }) async {
    final models = (await list()).reversed.toList();
    var total = models.fold<int>(0, (sum, m) => sum + m.sizeBytes);
    final removed = <String>[];
    for (final m in models) {
      if (total <= maxBytes) break;
      if (keep.contains(m.path)) continue;
      await delete(m.path);
      total -= m.sizeBytes;
      removed.add(m.path);
    }
    return removed;
  }

  /// Removes leftover `.part` files; returns how many were deleted.
  Future<int> clearPartials() async {
    if (!await root.exists()) return 0;
    var count = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.part')) {
        await entity.delete();
        count++;
      }
    }
    return count;
  }

  Future<void> _pruneEmptyParents(Directory dir) async {
    if (!p.isWithin(root.path, dir.path) || !await dir.exists()) return;
    if (await dir.list().isEmpty) await dir.delete();
  }

  File get _indexFile => File(p.join(root.path, _indexName));

  Future<Map<String, DateTime>> _readUsage() async {
    try {
      if (!await _indexFile.exists()) return {};
      final json = jsonDecode(await _indexFile.readAsString()) as Map;
      return {
        for (final e in json.entries)
          e.key as String: DateTime.parse(e.value as String),
      };
    } on FormatException catch (e) {
      ToolkitLog.warning(_tag, 'Ignoring corrupt usage index', e);
      return {};
    }
  }

  Future<void> _writeUsage(Map<String, DateTime> usage) async {
    await root.create(recursive: true);
    await _indexFile.writeAsString(
      jsonEncode({
        for (final e in usage.entries) e.key: e.value.toIso8601String(),
      }),
    );
  }
}
