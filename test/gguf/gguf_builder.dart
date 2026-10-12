import 'dart:convert';
import 'dart:typed_data';

import 'package:llm_toolkit/src/core/inference/gguf/gguf_reader.dart';

/// Builds a synthetic GGUF file (header and metadata only).
class GgufBuilder {
  final _b = BytesBuilder();
  final int version;
  final List<Uint8List> _entries = [];

  GgufBuilder({this.version = 3});

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
  static Uint8List _u64(int v) =>
      Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.little);
  static Uint8List _str(String s) {
    final bytes = utf8.encode(s);
    return Uint8List.fromList([..._u64(bytes.length), ...bytes]);
  }

  GgufBuilder _add(String key, int type, List<int> value) {
    _entries.add(Uint8List.fromList([..._str(key), ..._u32(type), ...value]));
    return this;
  }

  GgufBuilder string(String key, String value) =>
      _add(key, GgufType.string, _str(value));

  GgufBuilder u32(String key, int value) =>
      _add(key, GgufType.uint32, _u32(value));

  GgufBuilder u64(String key, int value) =>
      _add(key, GgufType.uint64, _u64(value));

  GgufBuilder f32(String key, double value) => _add(
    key,
    GgufType.float32,
    Uint8List(4)..buffer.asByteData().setFloat32(0, value, Endian.little),
  );

  GgufBuilder boolean(String key, bool value) =>
      _add(key, GgufType.bool_, [value ? 1 : 0]);

  GgufBuilder u32Array(String key, List<int> values) =>
      _add(key, GgufType.array, [
        ..._u32(GgufType.uint32),
        ..._u64(values.length),
        for (final v in values) ..._u32(v),
      ]);

  GgufBuilder boolArray(String key, List<bool> values) =>
      _add(key, GgufType.array, [
        ..._u32(GgufType.bool_),
        ..._u64(values.length),
        for (final v in values) v ? 1 : 0,
      ]);

  GgufBuilder stringArray(String key, List<String> values) =>
      _add(key, GgufType.array, [
        ..._u32(GgufType.string),
        ..._u64(values.length),
        for (final v in values) ..._str(v),
      ]);

  /// Typical decoder-only transformer entries.
  GgufBuilder transformer({
    String arch = 'llama',
    int context = 4096,
    int embedding = 2048,
    int blocks = 16,
    int heads = 16,
    int kvHeads = 4,
  }) => string('general.architecture', arch)
      .string('general.name', 'Test $arch')
      .u32('$arch.context_length', context)
      .u32('$arch.embedding_length', embedding)
      .u32('$arch.block_count', blocks)
      .u32('$arch.attention.head_count', heads)
      .u32('$arch.attention.head_count_kv', kvHeads);

  Uint8List build({int tensors = 7}) {
    _b
      ..add('GGUF'.codeUnits)
      ..add(_u32(version))
      ..add(_u64(tensors))
      ..add(_u64(_entries.length));
    for (final e in _entries) {
      _b.add(e);
    }
    return _b.toBytes();
  }
}
