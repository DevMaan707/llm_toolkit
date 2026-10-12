import 'dart:convert';

import '../exceptions/llm_toolkit_exceptions.dart';
import 'embedding.dart';

/// A unit of source content to index. [id] identifies it for later removal
/// and citations; it defaults to the content hash.
class RagDocument {
  final String id;
  final String text;
  final Map<String, Object?> metadata;

  RagDocument({String? id, required this.text, this.metadata = const {}})
    : id = id ?? contentHash(text);
}

/// Turns some source (a string, a file path, bytes, ...) into documents.
/// Apps implement this for formats the toolkit does not ship, such as PDF.
abstract interface class DocumentLoader<S> {
  Future<List<RagDocument>> load(S source);
}

/// Treats the input string as one document.
class PlainTextLoader implements DocumentLoader<String> {
  final String? id;
  final Map<String, Object?> metadata;

  const PlainTextLoader({this.id, this.metadata = const {}});

  @override
  Future<List<RagDocument>> load(String source) async => [
    RagDocument(id: id, text: source, metadata: metadata),
  ];
}

/// Markdown input; a leading `---` front-matter block of `key: value` lines
/// becomes metadata and is removed from the text.
class MarkdownLoader implements DocumentLoader<String> {
  final String? id;
  final Map<String, Object?> metadata;

  const MarkdownLoader({this.id, this.metadata = const {}});

  @override
  Future<List<RagDocument>> load(String source) async {
    var body = source;
    final meta = Map<String, Object?>.of(metadata);
    final m = RegExp(
      r'^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|$)',
      dotAll: true,
    ).firstMatch(source);
    if (m != null) {
      for (final line in m.group(1)!.split('\n')) {
        final i = line.indexOf(':');
        if (i > 0) {
          meta[line.substring(0, i).trim()] = line.substring(i + 1).trim();
        }
      }
      body = source.substring(m.end);
    }
    return [RagDocument(id: id, text: body, metadata: meta)];
  }
}

/// JSON input: an array (or a single object) of strings and/or objects. For
/// objects, [textField] is the content, [idField] the optional id and every
/// other scalar field (or just [metadataFields]) becomes metadata.
class JsonLoader implements DocumentLoader<String> {
  final String textField;
  final String idField;
  final List<String>? metadataFields;

  const JsonLoader({
    this.textField = 'text',
    this.idField = 'id',
    this.metadataFields,
  });

  @override
  Future<List<RagDocument>> load(String source) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw VectorStorageException('Invalid JSON document source.', e);
    }
    final items = decoded is List ? decoded : [decoded];
    return [for (final item in items) _convert(item)];
  }

  RagDocument _convert(Object? item) {
    if (item is String) return RagDocument(text: item);
    if (item is Map && item[textField] is String) {
      final fields = metadataFields;
      return RagDocument(
        id: item[idField]?.toString(),
        text: item[textField] as String,
        metadata: {
          for (final MapEntry(:key, :value) in item.entries)
            if (key != textField &&
                key != idField &&
                (value is num || value is String || value is bool) &&
                (fields == null || fields.contains(key)))
              key as String: value,
        },
      );
    }
    throw VectorStorageException(
      'JSON item must be a string or an object with a "$textField" string.',
    );
  }
}
