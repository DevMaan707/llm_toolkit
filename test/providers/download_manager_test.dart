import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/storage/download_manager.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

/// Serves [data] at `/file`, honouring `Range` unless [ignoreRange].
class TestServer {
  TestServer(this.data, {this.ignoreRange = false, this.chunkDelay});

  final Uint8List data;
  final bool ignoreRange;
  final Duration? chunkDelay;
  late HttpServer server;
  final rangeHeaders = <String?>[];
  int active = 0;
  int maxActive = 0;
  int failuresLeft = 0;

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/file');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/missing') {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    if (path == '/flaky' && failuresLeft > 0) {
      failuresLeft--;
      req.response.statusCode = 503;
      await req.response.close();
      return;
    }
    active++;
    maxActive = max(maxActive, active);
    final range = req.headers.value(HttpHeaders.rangeHeader);
    rangeHeaders.add(range);
    var start = 0;
    final res = req.response;
    if (range != null && !ignoreRange) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= data.length) {
        res.statusCode = 416;
        res.headers.set('content-range', 'bytes */${data.length}');
        await res.close();
        active--;
        return;
      }
      res.statusCode = 206;
      res.headers.set(
        'content-range',
        'bytes $start-${data.length - 1}/${data.length}',
      );
    }
    res.contentLength = data.length - start;
    try {
      const step = 16 * 1024;
      for (var i = start; i < data.length; i += step) {
        res.add(data.sublist(i, min(i + step, data.length)));
        await res.flush();
        if (chunkDelay != null) await Future<void>.delayed(chunkDelay!);
      }
      await res.close();
    } on Object {
      // client went away (pause or cancel)
    } finally {
      active--;
    }
  }

  Future<void> stop() => server.close(force: true);
}

Uint8List _bytes(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + 7) & 0xff));

void main() {
  late Directory tmp;
  late String dest;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dl_test');
    dest = '${tmp.path}/sub/model.gguf';
  });
  tearDown(() => tmp.delete(recursive: true));

  DownloadManager manager({int concurrent = 2, FreeSpaceProbe? probe}) =>
      DownloadManager(
        maxConcurrent: concurrent,
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 10),
        freeSpace: probe,
      );

  test('downloads, verifies SHA-256 and renames atomically', () async {
    final data = _bytes(200 * 1024);
    final server = TestServer(data);
    await server.start();
    addTearDown(server.stop);

    final task = manager().enqueue(
      DownloadRequest(
        url: server.url,
        destination: dest,
        sha256: sha256.convert(data).toString(),
      ),
    );
    final events = <DownloadProgress>[];
    task.progress.listen(events.add);
    final file = await task.done;

    expect(await file.readAsBytes(), data);
    expect(File('$dest.part').existsSync(), isFalse);
    expect(task.latest.state, DownloadState.completed);
    expect(task.latest.fraction, 1.0);
    expect(events.last.totalBytes, data.length);
  });

  test('resumes from an existing .part file with a Range request', () async {
    final data = _bytes(300 * 1024);
    final server = TestServer(data);
    await server.start();
    addTearDown(server.stop);
    await Directory('${tmp.path}/sub').create();
    await File('$dest.part').writeAsBytes(data.sublist(0, 100 * 1024));

    final file =
        await manager()
            .enqueue(
              DownloadRequest(
                url: server.url,
                destination: dest,
                sha256: sha256.convert(data).toString(),
              ),
            )
            .done;

    expect(server.rangeHeaders, ['bytes=${100 * 1024}-']);
    expect(await file.readAsBytes(), data);
  });

  test('restarts when the server ignores Range', () async {
    final data = _bytes(64 * 1024);
    final server = TestServer(data, ignoreRange: true);
    await server.start();
    addTearDown(server.stop);
    await Directory('${tmp.path}/sub').create();
    await File('$dest.part').writeAsBytes(data.sublist(0, 1000));

    final file =
        await manager()
            .enqueue(DownloadRequest(url: server.url, destination: dest))
            .done;
    expect(await file.readAsBytes(), data);
  });

  test('a complete .part (416) is finalised', () async {
    final data = _bytes(10 * 1024);
    final server = TestServer(data);
    await server.start();
    addTearDown(server.stop);
    await Directory('${tmp.path}/sub').create();
    await File('$dest.part').writeAsBytes(data);

    final file =
        await manager()
            .enqueue(DownloadRequest(url: server.url, destination: dest))
            .done;
    expect(await file.readAsBytes(), data);
  });

  test('hash mismatch fails and discards the data', () async {
    final data = _bytes(20 * 1024);
    final server = TestServer(data);
    await server.start();
    addTearDown(server.stop);

    final task = manager().enqueue(
      DownloadRequest(url: server.url, destination: dest, sha256: '00' * 32),
    );
    await expectLater(
      task.done,
      throwsA(
        isA<DownloadException>().having(
          (e) => e.message,
          'message',
          contains('Checksum'),
        ),
      ),
    );
    expect(File(dest).existsSync(), isFalse);
    expect(File('$dest.part').existsSync(), isFalse);
    expect(task.latest.state, DownloadState.failed);
  });

  test('skips an existing destination of the expected size', () async {
    await Directory('${tmp.path}/sub').create();
    await File(dest).writeAsBytes([1, 2, 3]);
    final task = manager().enqueue(
      DownloadRequest(
        url: Uri.parse('http://127.0.0.1:1/never'),
        destination: dest,
        expectedSize: 3,
      ),
    );
    expect((await task.done).path, dest);
  });

  test('HTTP errors carry the status code', () async {
    final server = TestServer(_bytes(10));
    await server.start();
    addTearDown(server.stop);
    final task = manager().enqueue(
      DownloadRequest(
        url: server.url.replace(path: '/missing'),
        destination: dest,
      ),
    );
    await expectLater(
      task.done,
      throwsA(
        isA<HttpDownloadException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
  });

  test('retries transient 5xx responses', () async {
    final data = _bytes(10 * 1024);
    final server = TestServer(data)..failuresLeft = 2;
    await server.start();
    addTearDown(server.stop);
    final file =
        await manager()
            .enqueue(
              DownloadRequest(
                url: server.url.replace(path: '/flaky'),
                destination: dest,
              ),
            )
            .done;
    expect(file.existsSync(), isTrue);
  });

  test('reports insufficient storage before writing', () async {
    final server = TestServer(_bytes(50 * 1024));
    await server.start();
    addTearDown(server.stop);
    final task = manager(
      probe: (_) async => 1024,
    ).enqueue(DownloadRequest(url: server.url, destination: dest));
    await expectLater(
      task.done,
      throwsA(
        isA<InsufficientStorageException>().having(
          (e) => e.requiredBytes,
          'required',
          50 * 1024,
        ),
      ),
    );
  });

  test('cancel stops the transfer and deletes the partial file', () async {
    final server = TestServer(
      _bytes(2 * 1024 * 1024),
      chunkDelay: const Duration(milliseconds: 5),
    );
    await server.start();
    addTearDown(server.stop);
    final task = manager().enqueue(
      DownloadRequest(url: server.url, destination: dest),
    );
    await task.progress.firstWhere((p) => p.receivedBytes > 0);
    task.cancel();
    await expectLater(task.done, throwsA(isA<DownloadException>()));
    expect(task.latest.state, DownloadState.cancelled);
    expect(File('$dest.part').existsSync(), isFalse);
    expect(File(dest).existsSync(), isFalse);
  });

  test('pause keeps the .part file and resume continues with Range', () async {
    final data = _bytes(2 * 1024 * 1024);
    final server = TestServer(
      data,
      chunkDelay: const Duration(milliseconds: 5),
    );
    await server.start();
    addTearDown(server.stop);
    final task = manager().enqueue(
      DownloadRequest(
        url: server.url,
        destination: dest,
        sha256: sha256.convert(data).toString(),
      ),
    );
    await task.progress.firstWhere((p) => p.receivedBytes > 64 * 1024);
    task.pause();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(task.latest.state, DownloadState.paused);
    final partial = File('$dest.part').lengthSync();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(data.length));

    task.resume();
    final file = await task.done;
    expect(await file.readAsBytes(), data);
    expect(server.rangeHeaders.length, 2);
    expect(server.rangeHeaders.last, startsWith('bytes='));
  });

  test('limits concurrent downloads', () async {
    final data = _bytes(512 * 1024);
    final server = TestServer(
      data,
      chunkDelay: const Duration(milliseconds: 3),
    );
    await server.start();
    addTearDown(server.stop);
    final m = manager(concurrent: 2);
    final tasks = [
      for (var i = 0; i < 5; i++)
        m.enqueue(
          DownloadRequest(url: server.url, destination: '${tmp.path}/f$i.gguf'),
        ),
    ];
    await Future.wait(tasks.map((t) => t.done));
    expect(server.maxActive, lessThanOrEqualTo(2));
    expect(server.maxActive, 2);
  });

  test('progress exposes speed and ETA', () {
    const p = DownloadProgress(
      state: DownloadState.downloading,
      receivedBytes: 250,
      totalBytes: 1000,
      bytesPerSecond: 50,
    );
    expect(p.fraction, 0.25);
    expect(p.eta, const Duration(seconds: 15));
    expect(
      const DownloadProgress(state: DownloadState.queued, receivedBytes: 0).eta,
      isNull,
    );
  });
}
