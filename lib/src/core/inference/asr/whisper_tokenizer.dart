import 'dart:convert';

import '../../../exceptions/llm_toolkit_exceptions.dart';

/// Decodes Whisper token ids to text using the GPT-2 style byte-level
/// `vocab.json` (token string -> id).
class WhisperTokenizer {
  static const _defaultEot = 50257;

  final Map<int, String> _idToToken;

  /// First special token id. Ids at or above it (end-of-text, language,
  /// task and timestamp markers) never appear in the decoded text.
  final int eotId;

  WhisperTokenizer._(this._idToToken, this.eotId);

  /// Parses the contents of a Whisper `vocab.json`.
  factory WhisperTokenizer.fromJson(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw InferenceException('vocab.json is not valid JSON', e);
    }
    if (decoded is! Map<String, dynamic> || decoded.isEmpty) {
      throw const InferenceException('vocab.json must be a non-empty object');
    }
    final byId = <int, String>{
      for (final e in decoded.entries) (e.value as num).toInt(): e.key,
    };
    final eot = decoded['<|endoftext|>'];
    return WhisperTokenizer._(byId, eot is num ? eot.toInt() : _defaultEot);
  }

  int get vocabularySize => _idToToken.length;

  bool isSpecial(int id) => id >= eotId;

  /// Text for [ids], stopping at the first end-of-text token.
  String decode(Iterable<int> ids) {
    final bytes = <int>[];
    for (final id in ids) {
      if (id == eotId) break;
      if (isSpecial(id)) continue;
      final token = _idToToken[id];
      if (token == null) continue;
      for (final rune in token.runes) {
        final b = _unicodeToByte[rune];
        if (b != null) {
          bytes.add(b);
        } else {
          bytes.addAll(utf8.encode(String.fromCharCode(rune)));
        }
      }
    }
    return utf8.decode(bytes, allowMalformed: true).trim();
  }

  /// Inverse of GPT-2's `bytes_to_unicode`.
  static final Map<int, int> _unicodeToByte = () {
    final printable = <int>[
      for (var b = 33; b <= 126; b++) b,
      for (var b = 161; b <= 172; b++) b,
      for (var b = 174; b <= 255; b++) b,
    ];
    final map = <int, int>{for (final b in printable) b: b};
    var extra = 0;
    for (var b = 0; b < 256; b++) {
      if (!map.containsKey(b)) map[256 + extra++] = b;
    }
    return map;
  }();
}
