import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../base_provider.dart';
import '../../model_detector.dart';
import '../../model_info.dart';
import '../../search_query.dart';
import '../../storage/download_manager.dart';

/// Model files already on disk, found by scanning directories.
class LocalProvider extends BaseModelProvider {
  final List<Directory> directories;
  final bool recursive;
  final ModelDetector detector;

  LocalProvider(
    Iterable<Directory> directories, {
    this.recursive = true,
    this.detector = ModelDetector.instance,
  }) : directories = List.unmodifiable(directories);

  @override
  String get id => 'local';

  static const _formats = [
    ModelFormat.gguf,
    ModelFormat.litertlm,
    ModelFormat.task,
    ModelFormat.tflite,
    ModelFormat.onnx,
  ];

  /// Every model file under [directories]; each file is its own model, with
  /// the absolute path as its id.
  Future<List<ModelInfo>> scan() async {
    final models = <ModelInfo>[];
    for (final dir in directories) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final format = ModelFormat.fromFilename(entity.path);
        if (format == null || !_formats.contains(format)) continue;
        models.add(await _describe(entity, format));
      }
    }
    models.sort((a, b) => a.name.compareTo(b.name));
    return models;
  }

  @override
  Future<List<ModelInfo>> searchModels(SearchQuery query) async {
    final text = query.text.trim().toLowerCase();
    final matches = [
      for (final m in await scan())
        if ((text.isEmpty || m.name.toLowerCase().contains(text)) &&
            (query.formats.isEmpty || m.formats.any(query.formats.contains)) &&
            (query.maxSizeBytes == null ||
                (m.sizeBytes ?? 0) <= query.maxSizeBytes!))
          m,
    ];
    matches.sort((a, b) {
      final result = switch (query.sort) {
        ModelSort.lastModified || ModelSort.createdAt => (a.lastModified ??
                DateTime(0))
            .compareTo(b.lastModified ?? DateTime(0)),
        _ => a.name.compareTo(b.name),
      };
      final byDate =
          query.sort == ModelSort.lastModified ||
          query.sort == ModelSort.createdAt;
      return byDate && query.descending ? -result : result;
    });
    return matches.take(query.limit).toList();
  }

  @override
  Future<ModelInfo> getModelDetails(String modelId) async {
    final file = File(modelId);
    final format = ModelFormat.fromFilename(modelId);
    if (format == null || !await file.exists()) {
      throw ModelProviderException('No model file at $modelId');
    }
    return _describe(file, format);
  }

  @override
  Future<DownloadTask> startDownload(String modelId, String filename) {
    throw const ModelProviderException('Local models are already on disk');
  }

  /// Nothing to fetch: returns the path of the local file.
  @override
  Future<String> downloadModel(
    String modelId,
    String filename, {
    ProgressCallback? onProgress,
    DownloadProgressCallback? onDetailedProgress,
  }) async {
    final info = await getModelDetails(modelId);
    onProgress?.call(1);
    return info.files.single.downloadUrl;
  }

  Future<ModelInfo> _describe(File file, ModelFormat format) async {
    final stat = await file.stat();
    final name = p.basename(file.path);
    final detected = detector.detect(file.path);
    final modelFile = ModelFile(
      filename: name,
      downloadUrl: file.path,
      sizeBytes: stat.size,
    );
    return ModelInfo(
      id: file.path,
      name: name,
      provider: id,
      library: detected.engineId,
      tags: [detected.family.name, ...detected.capabilities.map((c) => c.name)],
      files: [modelFile],
      lastModified: stat.modified,
      parameterCount: ModelNaming.parameterCount(name),
      quantization: modelFile.quantization,
      sizeBytes: stat.size,
    );
  }
}
