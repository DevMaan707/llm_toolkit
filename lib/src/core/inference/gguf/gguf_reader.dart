import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../exceptions/llm_toolkit_exceptions.dart';

/// Random-access byte source the GGUF reader pulls from.
abstract interface class GgufByteSource {
  /// Up to [length] bytes starting at [offset]; shorter near the end.
  Future<Uint8List> read(int offset, int length);
}

/// [GgufByteSource] over a file; opens it lazily and keeps it open.
class GgufFileSource implements GgufByteSource {
  final RandomAccessFile _file;

  GgufFileSource(this._file);

  @override
  Future<Uint8List> read(int offset, int length) async {
    await _file.setPosition(offset);
    return _file.read(length);
  }
}

/// [GgufByteSource] over bytes already in memory.
class GgufMemorySource implements GgufByteSource {
  final Uint8List _bytes;

  GgufMemorySource(this._bytes);

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset >= _bytes.length) return Uint8List(0);
    final end =
        offset + length > _bytes.length ? _bytes.length : offset + length;
    return Uint8List.sublistView(_bytes, offset, end);
  }
}

/// GGUF value type ids.
abstract final class GgufType {
  static const uint8 = 0;
  static const int8 = 1;
  static const uint16 = 2;
  static const int16 = 3;
  static const uint32 = 4;
  static const int32 = 5;
  static const float32 = 6;
  static const bool_ = 7;
  static const string = 8;
  static const array = 9;
  static const uint64 = 10;
  static const int64 = 11;
  static const float64 = 12;

  /// Byte width of a fixed-size type, or null for strings and arrays.
  static int? width(int type) => switch (type) {
    uint8 || int8 || bool_ => 1,
    uint16 || int16 => 2,
    uint32 || int32 || float32 => 4,
    uint64 || int64 || float64 => 8,
    _ => null,
  };
}

/// Forward-only buffered reader. Keeps one chunk in memory so skipping the
/// vocabulary (hundreds of thousands of strings) costs no extra I/O.
class GgufReader {
  static const _chunk = 256 * 1024;

  final GgufByteSource _source;
  final String _name;
  Uint8List _buffer = Uint8List(0);
  int _bufferStart = 0;
  int _pos = 0;

  GgufReader(this._source, [this._name = 'model']);

  /// Absolute offset of the next unread byte.
  int get position => _pos;

  Never _fail(String why) => throw InferenceException('$_name: $why');

  Future<void> _ensure(int n) async {
    final end = _pos - _bufferStart + n;
    if (_pos >= _bufferStart && end <= _buffer.length) return;
    _buffer = await _source.read(_pos, n > _chunk ? n : _chunk);
    _bufferStart = _pos;
    if (_buffer.length < n) _fail('unexpected end of file (truncated GGUF).');
  }

  ByteData _view(int n) => ByteData.sublistView(
    _buffer,
    _pos - _bufferStart,
    _pos - _bufferStart + n,
  );

  Future<int> u8() async {
    await _ensure(1);
    final v = _buffer[_pos - _bufferStart];
    _pos += 1;
    return v;
  }

  Future<int> u32() async {
    await _ensure(4);
    final v = _view(4).getUint32(0, Endian.little);
    _pos += 4;
    return v;
  }

  Future<int> u64() async {
    await _ensure(8);
    final v = _view(8).getUint64(0, Endian.little);
    _pos += 8;
    if (v < 0) _fail('corrupt length field.');
    return v;
  }

  /// Reads a length-prefixed string. Throws when longer than [maxLength].
  Future<String> string({int maxLength = 1 << 20}) async {
    final length = await u64();
    if (length > maxLength) _fail('string of $length bytes is too large.');
    return _utf8(length);
  }

  Future<String> _utf8(int length) async {
    await _ensure(length);
    final start = _pos - _bufferStart;
    final s = utf8.decode(
      Uint8List.sublistView(_buffer, start, start + length),
      allowMalformed: true,
    );
    _pos += length;
    return s;
  }

  /// Reads a string, or skips it and returns null when over [maxLength].
  Future<String?> optionalString({required int maxLength}) async {
    final length = await u64();
    if (length > maxLength) {
      skip(length);
      return null;
    }
    return _utf8(length);
  }

  /// Skips [n] bytes without reading them when they lie beyond the buffer.
  void skip(int n) => _pos += n;

  /// Skips a length-prefixed string.
  Future<void> skipString() async => skip(await u64());

  /// Reads one fixed-width scalar of [type] as int, double or bool.
  Future<Object> scalar(int type) async {
    final width = GgufType.width(type);
    if (width == null) _fail('type $type is not a scalar.');
    await _ensure(width);
    final data = _view(width);
    final value = switch (type) {
      GgufType.uint8 => data.getUint8(0),
      GgufType.int8 => data.getInt8(0),
      GgufType.uint16 => data.getUint16(0, Endian.little),
      GgufType.int16 => data.getInt16(0, Endian.little),
      GgufType.uint32 => data.getUint32(0, Endian.little),
      GgufType.int32 => data.getInt32(0, Endian.little),
      GgufType.float32 => data.getFloat32(0, Endian.little),
      GgufType.bool_ => data.getUint8(0) != 0,
      GgufType.uint64 => data.getUint64(0, Endian.little),
      GgufType.int64 => data.getInt64(0, Endian.little),
      _ => data.getFloat64(0, Endian.little),
    };
    _pos += width;
    return value;
  }
}
