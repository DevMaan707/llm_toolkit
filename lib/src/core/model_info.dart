/// Ids of the engines the toolkit ships (see `InferenceEngine.id`).
abstract final class EngineIds {
  static const llama = 'llama';
  static const litert = 'litert';
  static const asr = 'asr';
  static const sherpaAsr = 'sherpa-asr';
  static const sherpaTts = 'sherpa-tts';
  static const ollama = 'ollama';
}

/// What a model does, derived from the Hub's `pipeline_tag`.
enum ModelTask {
  textGeneration(
    'Text generation',
    ['text-generation'],
    aliases: ['text2text-generation', 'conversational'],
  ),
  vision(
    'Vision',
    ['image-text-to-text'],
    aliases: ['image-to-text', 'visual-question-answering'],
  ),
  embedding('Embedding', ['feature-extraction', 'sentence-similarity']),
  speechToText('Speech to text', ['automatic-speech-recognition']),
  textToSpeech('Text to speech', ['text-to-speech']),
  imageGeneration(
    'Image generation',
    ['text-to-image'],
    aliases: ['image-to-image'],
  ),
  videoGeneration(
    'Video generation',
    ['text-to-video'],
    aliases: ['image-to-video'],
  );

  const ModelTask(this.label, this.pipelineTags, {this.aliases = const []});

  final String label;

  /// Hub `pipeline_tag` values searched for this task.
  final List<String> pipelineTags;

  /// Further tags that map to this task when classifying a model.
  final List<String> aliases;

  /// Formats the built-in engines can run for this task; empty when the
  /// toolkit cannot run it locally (use a remote engine instead).
  Set<ModelFormat> get runnableFormats => switch (this) {
    textGeneration ||
    vision => const {ModelFormat.gguf, ModelFormat.litertlm, ModelFormat.task},
    embedding => const {ModelFormat.gguf},
    speechToText => const {ModelFormat.tflite, ModelFormat.onnx},
    textToSpeech => const {ModelFormat.onnx},
    imageGeneration || videoGeneration => const {},
  };

  /// Task for a Hub `pipeline_tag`, or `null` when it is not one we model.
  static ModelTask? fromPipelineTag(String? tag) {
    if (tag == null) return null;
    for (final task in values) {
      if (task.pipelineTags.contains(tag) || task.aliases.contains(tag)) {
        return task;
      }
    }
    return null;
  }
}

/// Multi-file model layouts that must be downloaded as a folder.
enum ModelBundle {
  /// sherpa-onnx: several `.onnx` graphs plus `tokens.txt` (and lexicons).
  sherpaOnnx;

  /// Detects a bundle from Hub [tags] and all repository [filenames].
  static ModelBundle? detect(
    Iterable<String> tags,
    Iterable<String> filenames,
  ) {
    if (tags.contains('sherpa-onnx')) return sherpaOnnx;
    var onnx = false;
    var tokens = false;
    for (final name in filenames) {
      final lower = name.toLowerCase();
      onnx |= lower.endsWith('.onnx');
      tokens |= lower.endsWith('tokens.txt');
    }
    return onnx && tokens ? sherpaOnnx : null;
  }
}

/// On-disk model formats the toolkit knows about.
enum ModelFormat {
  gguf('gguf', 'gguf'),
  litertlm('litertlm', 'litert-lm'),
  task('task', 'litert-lm'),
  tflite('tflite', 'tflite'),
  litert('litert', 'litert'),
  onnx('onnx', 'onnx'),
  safetensors('safetensors', 'safetensors');

  const ModelFormat(this.extension, this.hubTag);

  /// File extension without the dot.
  final String extension;

  /// Hub `filter` tag that finds repositories shipping this format.
  final String hubTag;

  /// Whether an inference engine in this toolkit can load the format.
  bool get isRunnable => this != safetensors && this != litert;

  /// Format of [filename], or `null` when it is not a model weights file.
  static ModelFormat? fromFilename(String filename) {
    final lower = filename.toLowerCase();
    for (final format in values) {
      if (lower.endsWith('.${format.extension}')) return format;
    }
    return null;
  }
}

/// Quantisation and parameter-count parsing from file and repository names.
abstract final class ModelNaming {
  static final _quant = RegExp(
    r'(?<![A-Za-z0-9])(?:UD-)?(I?Q\d(?:_(?:K|[01]|XXS|XS|XL|S|M|L|NL))*|BF16|F16|F32|FP16|FP32|MXFP4|INT4|INT8)(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  static final _params = RegExp(
    r'(?<![A-Za-z0-9.])(?:(\d+)x)?[Ee]?(\d+(?:\.\d+)?)([BbMm])(?![A-Za-z])',
  );

  static final _shard = RegExp(r'-(\d{5})-of-(\d{5})(?=\.)');

  /// Upper-case quantisation label such as `Q4_K_M` or `BF16`, if present.
  static String? quantization(String filename) {
    final name = filename.split('/').last;
    return _quant.firstMatch(name)?.group(1)?.toUpperCase();
  }

  /// Parameter count parsed from names such as `Llama-3.1-8B`, `e2b`,
  /// `270M` or `8x7B`; `null` when none is found.
  static int? parameterCount(String name) {
    final match = _params.firstMatch(name.split('/').last);
    if (match == null) return null;
    final experts = int.tryParse(match.group(1) ?? '1') ?? 1;
    final value = double.parse(match.group(2)!);
    final unit = match.group(3)!.toLowerCase() == 'b' ? 1e9 : 1e6;
    return (experts * value * unit).round();
  }

  /// `(index, count)` of a split file such as `x-00001-of-00003.gguf`.
  static (int, int)? shard(String filename) {
    final match = _shard.firstMatch(filename);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }
}

/// One downloadable file of a model repository.
class ModelFile {
  /// Path of the file inside the repository.
  final String filename;

  /// Size in bytes, or `null` when the provider did not report one.
  final int? sizeBytes;
  final String downloadUrl;

  /// Expected SHA-256 (lower-case hex) when the provider publishes one.
  final String? sha256;

  const ModelFile({
    required this.filename,
    required this.downloadUrl,
    this.sizeBytes,
    this.sha256,
  });

  ModelFormat? get format => ModelFormat.fromFilename(filename);

  /// Quantisation label such as `Q4_K_M`, if the name carries one.
  String? get quantization => ModelNaming.quantization(filename);

  /// `(index, count)` when this file is one shard of a split model.
  (int, int)? get shard => ModelNaming.shard(filename);

  bool get isSplit => shard != null;

  /// Multimodal projector files ship next to GGUF models but are not models.
  bool get isProjector => filename.toLowerCase().contains('mmproj');

  /// A single weights file an engine can load by itself.
  bool get isLoadable =>
      (format?.isRunnable ?? false) && !isSplit && !isProjector;

  String get sizeFormatted => formatBytes(sizeBytes);

  ModelFile copyWith({int? sizeBytes, String? sha256}) => ModelFile(
    filename: filename,
    downloadUrl: downloadUrl,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256 ?? this.sha256,
  );

  @override
  String toString() => 'ModelFile($filename, $sizeFormatted)';
}

/// Human readable byte count (`1.5 GB`); `unknown` for `null`.
String formatBytes(int? bytes) {
  if (bytes == null) return 'unknown';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// A model offered by a provider.
class ModelInfo {
  final String id;
  final String name;
  final String provider;
  final String? author;
  final String description;
  final List<String> tags;
  final int downloads;
  final int likes;
  final List<ModelFile> files;
  final String? pipelineTag;
  final String? library;
  final String? license;

  /// Whether files require an accepted licence and an access token.
  final bool gated;
  final DateTime? lastModified;
  final int? parameterCount;
  final int? contextLength;

  /// Quantisation of the model as a whole, for providers without file lists.
  final String? quantization;

  /// Total size when the provider reports one for the whole model.
  final int? sizeBytes;

  /// Folder layout the model needs, if it is not a single weights file.
  final ModelBundle? bundle;

  /// Engine that runs the model, when the provider knows it (for example a
  /// local server); otherwise [runnableBy] infers it.
  final String? runtime;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    this.author,
    this.description = '',
    this.tags = const [],
    this.downloads = 0,
    this.likes = 0,
    this.files = const [],
    this.pipelineTag,
    this.library,
    this.license,
    this.gated = false,
    this.lastModified,
    this.parameterCount,
    this.contextLength,
    this.quantization,
    this.sizeBytes,
    this.bundle,
    this.runtime,
  });

  /// Task parsed from [pipelineTag].
  ModelTask? get task => ModelTask.fromPipelineTag(pipelineTag);

  /// Id of the built-in engine that can run this model, or `null` when none
  /// can (image/video generation, graphs needing a custom pipeline, ...).
  ///
  /// Models without a known task are treated as text generation.
  String? get runnableBy {
    if (runtime != null) return runtime;
    final formats = {for (final f in loadableFiles) f.format!};
    bool any(Set<ModelFormat> wanted) => formats.any(wanted.contains);
    return switch (task ?? ModelTask.textGeneration) {
      ModelTask.textGeneration || ModelTask.vision =>
        any({ModelFormat.gguf})
            ? EngineIds.llama
            : any({ModelFormat.litertlm, ModelFormat.task})
            ? EngineIds.litert
            : null,
      ModelTask.embedding => any({ModelFormat.gguf}) ? EngineIds.llama : null,
      ModelTask.speechToText =>
        bundle == ModelBundle.sherpaOnnx && any({ModelFormat.onnx})
            ? EngineIds.sherpaAsr
            : formats.contains(ModelFormat.tflite) &&
                id.toLowerCase().contains('whisper')
            ? EngineIds.asr
            : null,
      ModelTask.textToSpeech =>
        bundle == ModelBundle.sherpaOnnx && any({ModelFormat.onnx})
            ? EngineIds.sherpaTts
            : null,
      ModelTask.imageGeneration || ModelTask.videoGeneration => null,
    };
  }

  Set<ModelFormat> get formats => {
    for (final f in files)
      if (f.format != null) f.format!,
  };

  List<ModelFile> filesOf(ModelFormat format) => [
    for (final f in files)
      if (f.format == format) f,
  ];

  /// Files an engine can load directly.
  List<ModelFile> get loadableFiles => [
    for (final f in files)
      if (f.isLoadable) f,
  ];

  bool get hasLoadableFiles => loadableFiles.isNotEmpty;

  int? get totalSizeBytes {
    if (sizeBytes != null) return sizeBytes;
    var total = 0;
    for (final f in files) {
      final size = f.sizeBytes;
      if (size == null) return null;
      total += size;
    }
    return total;
  }

  /// Largest loadable file that fits [availableMemoryBytes] once [overhead]
  /// (runtime buffers, KV cache) is added; `null` when none fits.
  ///
  /// Files of unknown size are ignored. Restrict to one [format] if needed.
  ModelFile? recommendedFileFor(
    int availableMemoryBytes, {
    ModelFormat? format,
    double overhead = 1.2,
  }) {
    ModelFile? best;
    for (final f in loadableFiles) {
      final size = f.sizeBytes;
      if (size == null || (format != null && f.format != format)) continue;
      if (size * overhead > availableMemoryBytes) continue;
      if (best == null || size > best.sizeBytes!) best = f;
    }
    return best;
  }

  ModelInfo copyWith({List<ModelFile>? files}) => ModelInfo(
    id: id,
    name: name,
    provider: provider,
    author: author,
    description: description,
    tags: tags,
    downloads: downloads,
    likes: likes,
    files: files ?? this.files,
    pipelineTag: pipelineTag,
    library: library,
    license: license,
    gated: gated,
    lastModified: lastModified,
    parameterCount: parameterCount,
    contextLength: contextLength,
    quantization: quantization,
    sizeBytes: sizeBytes,
    bundle: bundle,
    runtime: runtime,
  );

  @override
  String toString() => 'ModelInfo($provider:$id, ${files.length} files)';
}
