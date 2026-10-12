import 'dart:async';

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

  final _active = <String, DownloadTask>{};

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
    _active.clear();
  }
}
