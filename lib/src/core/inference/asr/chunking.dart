import 'dart:typed_data';

/// A half-open sample range `[start, end)`.
typedef SampleRange = (int start, int end);

/// Splits [total] samples into windows of [chunk] samples that overlap by
/// [overlap]. The last window always ends at [total]; audio no longer than one
/// chunk yields a single window.
List<SampleRange> planChunks(int total, int chunk, int overlap) {
  if (chunk <= 0 || overlap < 0 || overlap >= chunk) {
    throw ArgumentError('Need 0 <= overlap < chunk (got $overlap, $chunk)');
  }
  if (total <= 0) return const [];
  final ranges = <SampleRange>[];
  var start = 0;
  while (true) {
    final end = start + chunk < total ? start + chunk : total;
    ranges.add((start, end));
    if (end == total) return ranges;
    start += chunk - overlap;
  }
}

/// Transcribes [samples] window by window and stitches the texts together,
/// dropping the words repeated in each overlap. [transcribe] receives one
/// window and returns its text.
Future<List<String>> transcribeWindows(
  Float32List samples, {
  required int chunk,
  required int overlap,
  required Future<String> Function(Float32List window) transcribe,
}) async {
  final texts = <String>[];
  for (final (start, end) in planChunks(samples.length, chunk, overlap)) {
    texts.add(await transcribe(Float32List.sublistView(samples, start, end)));
  }
  return texts;
}

/// Buffers a live PCM16 stream into overlapping windows.
///
/// [add] appends bytes; [takeWindow] yields the next full window and keeps the
/// last [overlapSamples] for the following one. [flush] returns whatever audio
/// arrived since the last window (with its overlap), or null if there is none.
class PcmWindower {
  final int windowSamples;
  final int overlapSamples;

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _newSamples = 0;
  Uint8List _carry = Uint8List(0);
  int? _strayByte;

  PcmWindower({required this.windowSamples, required this.overlapSamples})
    : assert(windowSamples > 0),
      assert(overlapSamples >= 0 && overlapSamples < windowSamples);

  int get _windowBytes => windowSamples * 2;

  int get _pendingBytes => _carry.length + _buffer.length;

  void add(Uint8List pcm16) {
    var data = pcm16;
    if (_strayByte != null) {
      data =
          Uint8List(pcm16.length + 1)
            ..[0] = _strayByte!
            ..setRange(1, pcm16.length + 1, pcm16);
      _strayByte = null;
    }
    if (data.length.isOdd) {
      _strayByte = data.last;
      data = Uint8List.sublistView(data, 0, data.length - 1);
    }
    _buffer.add(data);
    _newSamples += data.length ~/ 2;
  }

  /// Next full window as PCM16 bytes, or null if not enough audio yet.
  Uint8List? takeWindow() {
    if (_pendingBytes < _windowBytes) return null;
    final all = _drain();
    final window = Uint8List.sublistView(all, 0, _windowBytes);
    final keepFrom = _windowBytes - overlapSamples * 2;
    _carry = Uint8List.sublistView(all, keepFrom);
    _newSamples = (all.length - _windowBytes) ~/ 2;
    return Uint8List.fromList(window);
  }

  /// Remaining audio (including the overlap carried from the previous window)
  /// if at least [minNewSamples] of it are new; clears the buffer.
  Uint8List? flush({int minNewSamples = 1}) {
    if (_newSamples < minNewSamples) {
      reset();
      return null;
    }
    final all = _drain();
    reset();
    return all;
  }

  void reset() {
    _buffer.clear();
    _carry = Uint8List(0);
    _newSamples = 0;
    _strayByte = null;
  }

  Uint8List _drain() {
    final merged =
        BytesBuilder(copy: false)
          ..add(_carry)
          ..add(_buffer.takeBytes());
    return merged.takeBytes();
  }
}
