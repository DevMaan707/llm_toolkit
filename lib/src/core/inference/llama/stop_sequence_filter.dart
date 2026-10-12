import 'dart:math' as math;

/// Incrementally trims streamed text at the first stop sequence.
///
/// Text that might still become the start of a stop sequence is held back until
/// the next chunk disambiguates it, so a stop sequence is never leaked even
/// when it is split across tokens.
class StopSequenceFilter {
  final List<String> _stops;
  final int _longest;
  String _held = '';
  bool _matched = false;

  StopSequenceFilter(Iterable<String> stopSequences)
    : _stops = stopSequences.where((s) => s.isNotEmpty).toList(),
      _longest = stopSequences.fold(0, (m, s) => math.max(m, s.length));

  /// Whether a stop sequence has been seen; further input is ignored.
  bool get matched => _matched;

  /// Feeds [chunk] and returns the text that is safe to emit.
  String add(String chunk) {
    if (_matched) return '';
    if (_stops.isEmpty) return chunk;
    final text = _held + chunk;
    var cut = -1;
    for (final stop in _stops) {
      final i = text.indexOf(stop);
      if (i >= 0 && (cut < 0 || i < cut)) cut = i;
    }
    if (cut >= 0) {
      _matched = true;
      _held = '';
      return text.substring(0, cut);
    }
    final keep = _partialSuffixLength(text);
    _held = text.substring(text.length - keep);
    return text.substring(0, text.length - keep);
  }

  /// Returns any text still held back once the stream has ended.
  String flush() {
    final rest = _matched ? '' : _held;
    _held = '';
    return rest;
  }

  int _partialSuffixLength(String text) {
    for (var n = math.min(text.length, _longest - 1); n > 0; n--) {
      final suffix = text.substring(text.length - n);
      if (_stops.any((s) => s.startsWith(suffix))) return n;
    }
    return 0;
  }
}
