import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/providers/huggingface/hf_provider.dart';
import 'package:llm_toolkit/src/core/storage/download_manager.dart';
import 'package:llm_toolkit/src/core/storage/model_store.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';
import 'package:path/path.dart' as p;

const _repo = 'csukuangfj/sherpa-onnx-moonshine-tiny-en-int8';

Uint8List _bytes(int n, int seed) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + seed) & 0xff));

/// Fake Hub: tree API (two pages) plus `resolve` file downloads.
class _FakeHub {
  final files = <String, Uint8List>{
    'tokens.txt': _bytes(3000, 1),
    'encode.int8.onnx': _bytes(40000, 2),
    'decode.int8.onnx': _bytes(70000, 3),
    'sub/dir/extra.onnx': _bytes(5000, 4),
  };
  final fileRequests = <String>[];

  /// Listed but answered with 404.
  final broken = <String>{};
  late HttpServer server;

  String get endpoint => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    final res = req.response;
    if (path == '/api/models/$_repo/tree/main') {
      final entries = [
        {'type': 'directory', 'path': 'sub', 'size': 0},
        for (final e in files.entries)
          {'type': 'file', 'path': e.key, 'size': e.value.length},
      ];
      final page2 = req.uri.queryParameters['cursor'] == 'next';
      res.headers.contentType = ContentType.json;
      if (!page2) {
        res.headers.set(
          'link',
          '<$endpoint$path?recursive=true&cursor=next>; rel="next"',
        );
      }
      res.write(
        jsonEncode(page2 ? entries.skip(3).toList() : entries.take(3).toList()),
      );
    } else if (path.startsWith('/$_repo/resolve/main/')) {
      final name = path.substring('/$_repo/resolve/main/'.length);
      fileRequests.add(name);
      final data = files[name];
      if (data == null || broken.contains(name)) {
        res.statusCode = 404;
      } else {
        res.add(data);
      }
    } else {
      res.statusCode = 404;
    }
    await res.close();
  }
}

void main() {
  late _FakeHub hub;
  late Directory tmp;
  late HuggingFaceProvider provider;

  setUp(() async {
    hub = _FakeHub();
    await hub.start();
    tmp = await Directory.systemTemp.createTemp('bundle_test');
    provider = HuggingFaceProvider(
      endpoint: hub.endpoint,
      store: ModelStore(tmp),
      downloads: DownloadManager(retryDelay: Duration.zero, maxRetries: 0),
    );
  });

  tearDown(() async {
    provider.dispose();
    await hub.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('listFiles follows pagination and skips directories', () async {
    final files = await provider.listFiles(_repo);
    expect(files.map((f) => f.filename), [
      'tokens.txt',
      'encode.int8.onnx',
      'decode.int8.onnx',
      'sub/dir/extra.onnx',
    ]);
    expect(files.first.sizeBytes, 3000);
    expect(
      files.first.downloadUrl,
      '${hub.endpoint}/$_repo/resolve/main/tokens.txt',
    );
  });

  test('downloads the whole repository into one directory', () async {
    final progress = <double>[];
    final dir = await provider.downloadBundle(_repo, onProgress: progress.add);

    expect(dir, p.join(tmp.path, _repo.replaceAll('/', '__')));
    for (final e in hub.files.entries) {
      expect(await File(p.join(dir, e.key)).readAsBytes(), e.value);
    }
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
    expect(progress, orderedEquals([...progress]..sort()));
  });

  test('files and where narrow the selection', () async {
    final dir = await provider.downloadBundle(
      _repo,
      files: ['tokens.txt', 'encode.int8.onnx'],
      where: (path) => path.endsWith('.txt'),
    );
    expect(hub.fileRequests, ['tokens.txt']);
    expect(File(p.join(dir, 'tokens.txt')).existsSync(), isTrue);
    expect(File(p.join(dir, 'encode.int8.onnx')).existsSync(), isFalse);
  });

  test('unknown files are rejected before any transfer', () async {
    await expectLater(
      provider.downloadBundle(_repo, files: ['nope.onnx']),
      throwsA(isA<ModelProviderException>()),
    );
    expect(hub.fileRequests, isEmpty);
  });

  test('a second call skips files that are already complete', () async {
    await provider.downloadBundle(_repo);
    final first = hub.fileRequests.length;
    final progress = <double>[];
    await provider.downloadBundle(_repo, onProgress: progress.add);
    expect(hub.fileRequests, hasLength(first));
    expect(progress.last, 1.0);
  });

  test('one failing file fails the bundle', () async {
    hub.broken.add('decode.int8.onnx');
    await expectLater(
      provider.downloadBundle(_repo),
      throwsA(isA<DownloadException>()),
    );
  });
}
