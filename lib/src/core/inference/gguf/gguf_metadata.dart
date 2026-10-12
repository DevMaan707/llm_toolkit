import 'dart:io';
import 'dart:typed_data';

import '../../../exceptions/llm_toolkit_exceptions.dart';
import 'gguf_reader.dart';

/// Model facts read from a GGUF header and key/value metadata. Tensor data is
/// never touched, so reading costs a few KB of I/O plus one pass over the
/// vocabulary entries (which are skipped, not stored).
class GgufMetadata {
  static const _magic = 0x46554747; // "GGUF" read little-endian
  static const _supportedVersions = {2, 3};
  static const _maxStoredString = 256 * 1024;
  static const _maxStoredArray = 4096;

  /// Architectures that produce embeddings instead of text.
  static const embeddingArchitectures = {
    'bert',
    'nomic-bert',
    'nomic-bert-moe',
    'jina-bert-v2',
    'jina-bert-v3',
    'modern-bert',
    'neo-bert',
  };

  /// Architectures with no attention KV cache to size.
  static const _recurrentArchitectures = {'mamba', 'mamba2', 'rwkv6', 'rwkv7'};

  static const _fileTypes = {
    0: 'F32',
    1: 'F16',
    2: 'Q4_0',
    3: 'Q4_1',
    7: 'Q8_0',
    8: 'Q5_0',
    9: 'Q5_1',
    10: 'Q2_K',
    11: 'Q3_K_S',
    12: 'Q3_K_M',
    13: 'Q3_K_L',
    14: 'Q4_K_S',
    15: 'Q4_K_M',
    16: 'Q5_K_S',
    17: 'Q5_K_M',
    18: 'Q6_K',
    19: 'IQ2_XXS',
    20: 'IQ2_XS',
    21: 'Q2_K_S',
    22: 'IQ3_XS',
    23: 'IQ3_XXS',
    24: 'IQ1_S',
    25: 'IQ4_NL',
    26: 'IQ3_S',
    27: 'IQ3_M',
    28: 'IQ2_S',
    29: 'IQ2_M',
    30: 'IQ4_XS',
    31: 'IQ1_M',
    32: 'BF16',
    36: 'TQ1_0',
    37: 'TQ2_0',
    38: 'MXFP4_MOE',
  };

  final int version;
  final int tensorCount;
  final int metadataCount;

  /// Scalars, short strings and short numeric arrays by key. Large arrays are
  /// not stored; their lengths are in [arrayLengths].
  final Map<String, Object> values;

  /// Element count of every array entry, including skipped ones.
  final Map<String, int> arrayLengths;

  const GgufMetadata({
    required this.version,
    required this.tensorCount,
    required this.metadataCount,
    this.values = const {},
    this.arrayLengths = const {},
  });

  /// Reads the metadata of the GGUF file at [path].
  ///
  /// Throws [InferenceException] if the file is missing, is not GGUF, is
  /// truncated, or uses a version llama.cpp no longer loads.
  static Future<GgufMetadata> read(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw InferenceException('Model file does not exist: $path');
    }
    final raf = await file.open();
    try {
      return await parse(GgufFileSource(raf), path);
    } finally {
      await raf.close();
    }
  }

  /// Parses GGUF [bytes]; [source] only appears in error messages.
  static Future<GgufMetadata> fromBytes(
    Uint8List bytes, [
    String source = 'model',
  ]) => parse(GgufMemorySource(bytes), source);

  /// Parses from any [GgufByteSource].
  static Future<GgufMetadata> parse(
    GgufByteSource source, [
    String name = 'model',
  ]) async {
    final reader = GgufReader(source, name);
    final int magic;
    try {
      magic = await reader.u32();
    } on InferenceException {
      throw InferenceException('$name is too small to be a GGUF file.');
    }
    if (magic != _magic) {
      throw InferenceException(
        '$name is not a GGUF file (bad magic number). '
        'Re-download the model and try again.',
      );
    }
    final version = await reader.u32();
    if (!_supportedVersions.contains(version)) {
      throw InferenceException('$name uses unsupported GGUF version $version.');
    }
    final tensorCount = await reader.u64();
    final metadataCount = await reader.u64();
    if (metadataCount > 1 << 20) {
      throw InferenceException('$name has a corrupt metadata count.');
    }
    final values = <String, Object>{};
    final arrayLengths = <String, int>{};
    for (var i = 0; i < metadataCount; i++) {
      final key = await reader.string(maxLength: 4096);
      final type = await reader.u32();
      await _readValue(reader, key, type, values, arrayLengths, name);
    }
    return GgufMetadata(
      version: version,
      tensorCount: tensorCount,
      metadataCount: metadataCount,
      values: values,
      arrayLengths: arrayLengths,
    );
  }

  static Future<void> _readValue(
    GgufReader r,
    String key,
    int type,
    Map<String, Object> values,
    Map<String, int> arrayLengths,
    String name,
  ) async {
    switch (type) {
      case GgufType.string:
        final text = await r.optionalString(maxLength: _maxStoredString);
        if (text != null) values[key] = text;
      case GgufType.array:
        final elementType = await r.u32();
        final count = await r.u64();
        arrayLengths[key] = count;
        await _readArray(r, key, elementType, count, values, name);
      default:
        if (GgufType.width(type) == null) {
          throw InferenceException('$name has unknown metadata type $type.');
        }
        values[key] = await r.scalar(type);
    }
  }

  static Future<void> _readArray(
    GgufReader r,
    String key,
    int elementType,
    int count,
    Map<String, Object> values,
    String name,
  ) async {
    if (elementType == GgufType.string) {
      for (var i = 0; i < count; i++) {
        await r.skipString();
      }
      return;
    }
    final width = GgufType.width(elementType);
    if (width == null) {
      throw InferenceException('$name has unsupported nested arrays.');
    }
    if (count > _maxStoredArray || elementType == GgufType.float64) {
      r.skip(count * width);
      return;
    }
    final items = <num>[];
    for (var i = 0; i < count; i++) {
      final v = await r.scalar(elementType);
      items.add(switch (v) {
        bool b => b ? 1 : 0,
        num n => n,
        _ => 0,
      });
    }
    values[key] = items;
  }

  String? _string(String key) => values[key] as String?;

  int? _int(String key) {
    final v = values[key];
    return v is num ? v.toInt() : null;
  }

  /// A per-model int that some models store as a per-layer array; the maximum.
  int? _intOrMax(String key) {
    final v = values[key];
    if (v is num) return v.toInt();
    if (v is List<num> && v.isNotEmpty) {
      return v.reduce((a, b) => a > b ? a : b).toInt();
    }
    return null;
  }

  int? _arch(String suffix) => _int('$architecture.$suffix');

  String? get architecture => _string('general.architecture');
  String? get name => _string('general.name');
  int? get contextLength => _arch('context_length');
  int? get embeddingLength => _arch('embedding_length');
  int? get blockCount => _arch('block_count');
  int? get headCount => _intOrMax('$architecture.attention.head_count');
  int? get headCountKv => _intOrMax('$architecture.attention.head_count_kv');
  int? get keyLength => _arch('attention.key_length');
  int? get valueLength => _arch('attention.value_length');
  int? get slidingWindow => _arch('attention.sliding_window');

  /// Dense-layer interval of sliding-window models: every n-th layer attends
  /// to the full context. Null when the file does not say.
  int? get slidingWindowPattern => _arch('attention.sliding_window_pattern');

  /// Per-layer flags (true = sliding window) when the file stores them.
  List<bool>? get slidingLayerFlags {
    final v = values['$architecture.attention.sliding_window_pattern'];
    return v is List<num> ? [for (final n in v) n != 0] : null;
  }

  /// `general.file_type` id (llama.cpp `llama_ftype`).
  int? get fileType => _int('general.file_type');

  /// Quantisation label such as `Q4_K_M`, or null when unknown.
  String? get quantization => _fileTypes[fileType];

  /// Vocabulary size from the tokenizer array or the architecture key.
  int? get vocabSize =>
      arrayLengths['tokenizer.ggml.tokens'] ?? _arch('vocab_size');

  /// The Jinja chat template embedded in the file, if any.
  String? get chatTemplate {
    final t = _string('tokenizer.chat_template');
    return t == null || t.trim().isEmpty ? null : t;
  }

  bool get isEmbeddingModel => embeddingArchitectures.contains(architecture);

  /// False for state-space and RWKV models that keep no attention KV cache.
  bool get hasKvCache => !_recurrentArchitectures.contains(architecture);
}
