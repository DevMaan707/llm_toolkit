import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeHandler = ResponseBody Function(RequestOptions options);

/// Dio adapter answering from a closure and recording requests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final FakeHandler handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}

  static ResponseBody json(
    Object body, {
    int status = 200,
    Map<String, List<String>>? headers,
  }) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      ...?headers,
    },
  );

  static ResponseBody text(String body, {int status = 200}) =>
      ResponseBody.fromString(body, status);

  static Dio dio(FakeAdapter adapter) => Dio()..httpClientAdapter = adapter;
}
