import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../logging/toolkit_logger.dart';

/// Thin HTTP layer shared by the remote engines: auth headers, timeouts,
/// line streaming and mapping of failures to [InferenceException].
///
/// Secrets (API keys) are only ever placed in request headers; they are never
/// logged or included in error messages.
class RemoteHttp {
  final String baseUrl;
  final String service;
  final Duration requestTimeout;
  final Duration streamIdleTimeout;

  final http.Client _client;
  final bool _ownsClient;
  final Map<String, String> _headers;

  RemoteHttp({
    required String baseUrl,
    required this.service,
    String? apiKey,
    Map<String, String> headers = const {},
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 120),
    this.streamIdleTimeout = const Duration(seconds: 120),
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _headers = {
         if (apiKey != null && apiKey.isNotEmpty)
           'Authorization': 'Bearer $apiKey',
         ...headers,
       };

  Uri uri(String path) => Uri.parse('$baseUrl$path');

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<dynamic> getJson(String path) async {
    final response = await _guard(
      () => _client.get(uri(path), headers: _headers).timeout(requestTimeout),
    );
    _throwIfFailed(response.statusCode, response.body, response.headers);
    return jsonDecode(response.body);
  }

  Future<Uint8List> getBytes(Uri url) async {
    final response = await _guard(
      () => _client.get(url).timeout(requestTimeout),
    );
    _throwIfFailed(response.statusCode, '', response.headers);
    return response.bodyBytes;
  }

  Future<dynamic> postJson(String path, Map<String, Object?> body) async {
    final response = await _guard(
      () => _client
          .post(uri(path), headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(requestTimeout),
    );
    _throwIfFailed(response.statusCode, response.body, response.headers);
    return jsonDecode(response.body);
  }

  Future<Uint8List> postForBytes(String path, Map<String, Object?> body) async {
    final response = await _guard(
      () => _client
          .post(uri(path), headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(requestTimeout),
    );
    _throwIfFailed(response.statusCode, '', response.headers);
    return response.bodyBytes;
  }

  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required http.MultipartFile file,
  }) async {
    final request =
        http.MultipartRequest('POST', uri(path))
          ..headers.addAll(_headers)
          ..fields.addAll(fields)
          ..files.add(file);
    final response = await _guard(() async {
      final streamed = await _client.send(request).timeout(requestTimeout);
      return http.Response.fromStream(streamed);
    });
    _throwIfFailed(response.statusCode, response.body, response.headers);
    return jsonDecode(response.body);
  }

  /// POSTs [body] and yields the non-empty text lines of the response as they
  /// arrive. Cancelling the returned stream's subscription closes the
  /// connection (requires `package:http` 1.5+), which aborts the request on
  /// the server.
  Stream<String> postLines(String path, Map<String, Object?> body) async* {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest('POST', uri(path), abortTrigger: abort.future)
          ..headers.addAll(_jsonHeaders)
          ..body = jsonEncode(body);
    try {
      final response = await _client.send(request).timeout(requestTimeout);
      if (response.statusCode >= 400) {
        final text = await response.stream.bytesToString();
        _throwIfFailed(response.statusCode, text, response.headers);
      }
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(streamIdleTimeout);
      await for (final line in lines) {
        if (line.trim().isNotEmpty) yield line;
      }
    } on InferenceException {
      rethrow;
    } catch (e) {
      throw _mapTransportError(e);
    } finally {
      // Runs on completion and on cancellation; aborting closes the socket.
      if (!abort.isCompleted) abort.complete();
    }
  }

  Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
    ..._headers,
  };

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on InferenceException {
      rethrow;
    } catch (e) {
      throw _mapTransportError(e);
    }
  }

  InferenceException _mapTransportError(Object e) {
    ToolkitLog.warning(service, 'Request failed: ${e.runtimeType}');
    return switch (e) {
      TimeoutException() => InferenceException(
        '$service request timed out. The server may be overloaded or still '
        'loading the model; try again or raise the timeout.',
        e,
      ),
      SocketException() || http.ClientException() => InferenceException(
        'Cannot reach $service at $baseUrl. Check the URL, that the server '
        'is running and your network connection.',
        e,
      ),
      _ => InferenceException('$service request failed: $e', e),
    };
  }

  void _throwIfFailed(int status, String body, Map<String, String> headers) {
    if (status < 400) return;
    throw mapHttpError(
      service,
      status,
      body,
      retryAfter: headers['retry-after'],
    );
  }
}

/// Converts a failed HTTP response into an [InferenceException] with an
/// actionable message.
InferenceException mapHttpError(
  String service,
  int status,
  String body, {
  String? retryAfter,
}) {
  final detail = _errorDetail(body);
  final suffix = detail == null ? '' : ': $detail';
  final message = switch (status) {
    401 || 403 =>
      '$service rejected the credentials (HTTP $status). Check the API key '
          'and its permissions$suffix',
    404 =>
      '$service endpoint or model not found (HTTP 404). Check the base URL '
          'and model name$suffix',
    429 =>
      '$service rate limit or quota exceeded (HTTP 429)'
          '${retryAfter == null ? '' : '; retry after ${_retryText(retryAfter)}'}'
          '$suffix',
    >= 500 =>
      '$service server error (HTTP $status). The provider may be down or '
          'overloaded; retry later$suffix',
    _ => '$service request failed (HTTP $status)$suffix',
  };
  return InferenceException(message);
}

String _retryText(String value) =>
    int.tryParse(value.trim()) != null ? '${value.trim()}s' : value.trim();

String? _errorDetail(String body) {
  if (body.trim().isEmpty) return null;
  try {
    final json = jsonDecode(body);
    if (json is Map) {
      final error = json['error'];
      if (error is String) return error;
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (json['message'] is String) return json['message'] as String;
    }
  } on FormatException {
    // Not JSON; fall through to the raw text.
  }
  final text = body.trim();
  return text.length > 200 ? '${text.substring(0, 200)}...' : text;
}

/// Guesses an image MIME type from magic bytes, defaulting to PNG.
String imageMimeType(Uint8List bytes) {
  bool starts(List<int> sig) =>
      bytes.length >= sig.length &&
      [for (var i = 0; i < sig.length; i++) bytes[i] == sig[i]].every((e) => e);
  if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts([0x47, 0x49, 0x46])) return 'image/gif';
  if (starts([0x52, 0x49, 0x46, 0x46]) &&
      bytes.length > 11 &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return 'image/png';
}

/// Returns [audio] as a WAV file, wrapping raw 16 kHz mono PCM16 if needed.
Uint8List ensureWav(Uint8List audio, {int sampleRate = 16000}) {
  if (audio.length >= 4 &&
      String.fromCharCodes(audio.sublist(0, 4)) == 'RIFF') {
    return audio;
  }
  final header = ByteData(44);
  void tag(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + audio.length, Endian.little);
  tag(8, 'WAVEfmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, audio.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...audio]);
}
