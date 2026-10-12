import 'dart:async';

import 'package:path/path.dart' as p;

import '../exceptions/llm_toolkit_exceptions.dart';
import 'model_info.dart';
import 'search_query.dart';
import 'storage/download_manager.dart';

/// Download completion in the range 0..1.
typedef ProgressCallback = void Function(double progress);

/// Detailed progress including speed and ETA.
typedef DownloadProgressCallback = void Function(DownloadProgress progress);

/// A source of models: a remote hub, a local server or a folder on disk.
abstract class BaseModelProvider {
  /// Stable identifier such as `huggingface`, `ollama` or `local`.
  String get id;

  Future<List<ModelInfo>> searchModels(SearchQuery query);

  Future<ModelInfo> getModelDetails(String modelId);

  /// Starts downloading [filename] of [modelId] and returns its task.
  ///
  /// The task can be paused, resumed and cancelled by the caller.
  Future<DownloadTask> startDownload(String modelId, String filename);

  /// Every file of [modelId] (any extension) with sizes, for folder
  /// downloads. Providers that cannot list files throw.
  Future<List<ModelFile>> listFiles(String modelId) {
    throw ModelProviderException('$id cannot list the files of $modelId');
  }

  /// Starts downloading one already-listed [file]; providers override this
  /// to skip per-file metadata lookups.
  Future<DownloadTask> startFileDownload(String modelId, ModelFile file) =>
      startDownload(modelId, file.filename);

  final _active = <String, DownloadTask>{};
  final _bundles = <String, List<DownloadTask>>{};

  /// Downloads a file and returns its local path.
  ///
  /// [onProgress] receives 0..1; [onDetailedProgress] gets speed and ETA.
  Future<String> downloadModel(
    String modelId,
    String filename, {
    ProgressCallback? onProgress,
    DownloadProgressCallback? onDetailedProgress,
  }) async {
    final key = '$modelId/$filename';
    final task = _active[key] ??= await startDownload(modelId, filename);
    final sub = task.progress.listen((p) {
      onDetailedProgress?.call(p);
      final fraction = p.fraction;
      if (fraction != null) onProgress?.call(fraction);
    });
    try {
      return (await task.done).path;
    } finally {
      _active.remove(key);
      await sub.cancel();
    }
  }

  /// Downloads several files of [modelId] into one directory and returns it.
  ///
  /// Pick files with [files] (repository paths) or [where]; with neither,
  /// the whole repository is fetched. Progress is aggregated over all files
  /// (sizes come from [listFiles]). Files already complete on disk are
  /// skipped and partial files resume, so calling again after a failure
  /// continues where it stopped. If one file fails the rest are cancelled.
  Future<String> downloadBundle(
    String modelId, {
    Iterable<String>? files,
    bool Function(String path)? where,
    ProgressCallback? onProgress,
    DownloadProgressCallback? onDetailedProgress,
  }) async {
    final listed = await listFiles(modelId);
    final wanted = files?.toSet();
    final missing = wanted?.difference({for (final f in listed) f.filename});
    if (missing != null && missing.isNotEmpty) {
      throw ModelProviderException(
        '$modelId has no file(s): ${missing.join(', ')}',
      );
    }
    final selected = [
      for (final f in listed)
        if ((wanted == null || wanted.contains(f.filename)) &&
            (where?.call(f.filename) ?? true))
          f,
    ];
    if (selected.isEmpty) {
      throw ModelProviderException('No files selected from $modelId');
    }
    if (_bundles.containsKey(modelId)) {
      throw ModelProviderException('$modelId is already downloading');
    }

    final tasks = <DownloadTask>[];
    _bundles[modelId] = tasks;
    final tracker = _BundleProgress(
      [for (final f in selected) f.sizeBytes],
      onProgress,
      onDetailedProgress,
    );
    final subs = <StreamSubscription<DownloadProgress>>[];
    try {
      for (final (i, file) in selected.indexed) {
        final task = await startFileDownload(modelId, file);
        tasks.add(task);
        subs.add(task.progress.listen((p) => tracker.update(i, p)));
      }
      final done = await Future.wait([
        for (final (i, task) in tasks.indexed)
          task.done.then((f) {
            tracker.complete(i);
            return f;
          }),
      ]);
      return _bundleRoot(done.first.path, selected.first.filename);
    } catch (_) {
      for (final task in tasks) {
        task.cancel();
      }
      rethrow;
    } finally {
      _bundles.remove(modelId);
      for (final sub in subs) {
        await sub.cancel();
      }
    }
  }

  /// Cancels a [downloadBundle] of [modelId]; returns whether one ran.
  bool cancelBundle(String modelId) {
    final tasks = _bundles[modelId];
    if (tasks == null) return false;
    for (final task in tasks) {
      task.cancel();
    }
    return true;
  }

  /// Directory holding [relative] once downloaded to [path].
  static String _bundleRoot(String path, String relative) {
    var dir = path;
    for (var i = 0; i < p.posix.split(relative).length; i++) {
      dir = p.dirname(dir);
    }
    return dir;
  }

  /// Cancels a download started with [downloadModel]; returns whether one ran.
  bool cancelDownload(String modelId, String filename) {
    final task = _active[('$modelId/$filename')];
    task?.cancel();
    return task != null;
  }

  /// Releases clients and cancels running downloads.
  void dispose() {
    for (final task in _active.values) {
      task.cancel();
    }
    for (final tasks in _bundles.values) {
      for (final task in tasks) {
        task.cancel();
      }
    }
    _active.clear();
  }
}

/// Sums per-file progress into one stream of updates.
class _BundleProgress {
  final List<int?> _sizes;
  final ProgressCallback? _onProgress;
  final DownloadProgressCallback? _onDetailed;
  late final List<int> _received = List.filled(_sizes.length, 0);
  late final List<double> _speed = List.filled(_sizes.length, 0);

  _BundleProgress(this._sizes, this._onProgress, this._onDetailed);

  void update(int index, DownloadProgress progress) {
    _received[index] = progress.receivedBytes;
    _speed[index] = progress.bytesPerSecond;
    _sizes[index] ??= progress.totalBytes;
    _emit();
  }

  void complete(int index) {
    _received[index] = _sizes[index] ?? _received[index];
    _speed[index] = 0;
    _emit();
  }

  void _emit() {
    final known = _sizes.whereType<int>();
    final total = known.length == _sizes.length ? known.fold(0, _sum) : null;
    final snapshot = DownloadProgress(
      state: DownloadState.downloading,
      receivedBytes: _received.fold(0, _sum),
      totalBytes: total,
      bytesPerSecond: _speed.fold(0.0, (a, b) => a + b),
    );
    _onDetailed?.call(snapshot);
    final fraction = snapshot.fraction;
    if (fraction != null) _onProgress?.call(fraction);
  }

  static int _sum(int a, int b) => a + b;
}
