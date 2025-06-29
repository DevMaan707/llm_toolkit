class ModelInfo {
  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final int downloads;
  final List<ModelFile> files;
  final String provider;

  ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.tags,
    required this.downloads,
    required this.files,
    required this.provider,
  });

  List<ModelFile> get ggufFiles =>
      files
          .where((file) => file.filename.toLowerCase().endsWith('.gguf'))
          .toList();

  List<ModelFile> get tfliteFiles =>
      files
          .where((file) => file.filename.toLowerCase().endsWith('.tflite'))
          .toList();

  List<ModelFile> get compatibleFiles {
    final compatible = <ModelFile>[];
    compatible.addAll(ggufFiles);
    compatible.addAll(tfliteFiles);
    return compatible;
  }

  bool get isLlamaCompatible => ggufFiles.isNotEmpty;
  bool get isGemmaCompatible => tfliteFiles.isNotEmpty;
  bool get hasCompatibleFiles => compatibleFiles.isNotEmpty;
}

class ModelFile {
  final String filename;
  final int size;
  final String downloadUrl;

  ModelFile({
    required this.filename,
    required this.size,
    required this.downloadUrl,
  });

  String get sizeFormatted {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024)
      return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String get fileType {
    final ext = filename.toLowerCase();
    if (ext.endsWith('.gguf')) return 'GGUF';
    if (ext.endsWith('.tflite')) return 'TFLite';
    if (ext.endsWith('.ggml')) return 'GGML';
    return 'Unknown';
  }
}
