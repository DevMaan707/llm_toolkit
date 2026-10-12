import '../../model_info.dart';

/// Converts Hugging Face Hub JSON into toolkit types.
abstract final class HfParser {
  /// Fields requested through the Hub's `expand` parameter.
  static const expandFields = [
    'author',
    'downloads',
    'likes',
    'siblings',
    'gated',
    'lastModified',
    'pipeline_tag',
    'library_name',
    'tags',
    'gguf',
    'cardData',
  ];

  static ModelInfo model(
    Map<String, dynamic> json, {
    required String endpoint,
  }) {
    final id = json['id'] as String? ?? json['modelId'] as String? ?? '';
    final name = id.split('/').last;
    final card = json['cardData'] as Map<String, dynamic>? ?? const {};
    final gguf = json['gguf'] as Map<String, dynamic>?;
    final tags = [for (final t in json['tags'] as List? ?? const []) '$t'];

    return ModelInfo(
      id: id,
      name: name,
      provider: 'huggingface',
      author:
          json['author'] as String? ??
          (id.contains('/') ? id.split('/').first : null),
      tags: tags,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      pipelineTag: (json['pipeline_tag'] ?? card['pipeline_tag']) as String?,
      library: (json['library_name'] ?? card['library_name']) as String?,
      license: _license(card, tags),
      gated: _isGated(json['gated']),
      lastModified: DateTime.tryParse(json['lastModified'] as String? ?? ''),
      parameterCount:
          (gguf?['total'] as num?)?.toInt() ?? ModelNaming.parameterCount(name),
      contextLength: (gguf?['context_length'] as num?)?.toInt(),
      files: [
        for (final s in json['siblings'] as List? ?? const [])
          if (_file(id, s as Map<String, dynamic>, endpoint) case final f?) f,
      ],
    );
  }

  static ModelFile? _file(String id, Map<String, dynamic> s, String endpoint) {
    final filename = s['rfilename'] as String?;
    if (filename == null || ModelFormat.fromFilename(filename) == null) {
      return null;
    }
    final lfs = s['lfs'] as Map<String, dynamic>?;
    return ModelFile(
      filename: filename,
      downloadUrl: resolveUrl(endpoint, id, filename).toString(),
      sizeBytes:
          (s['size'] as num?)?.toInt() ?? (lfs?['size'] as num?)?.toInt(),
      sha256: (lfs?['sha256'] as String?)?.toLowerCase(),
    );
  }

  /// Direct download URL of a file on the `main` branch.
  static Uri resolveUrl(String endpoint, String id, String filename) {
    final base = Uri.parse(endpoint);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        ...id.split('/'),
        'resolve',
        'main',
        ...filename.split('/'),
      ],
    );
  }

  static bool _isGated(Object? value) => value != null && value != false;

  static String? _license(Map<String, dynamic> card, List<String> tags) {
    final license = card['license'];
    if (license is String) return license;
    if (license is List && license.isNotEmpty) return '${license.first}';
    for (final t in tags) {
      if (t.startsWith('license:')) return t.substring(8);
    }
    return null;
  }
}
