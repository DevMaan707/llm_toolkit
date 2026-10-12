import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../exceptions/llm_toolkit_exceptions.dart';
import '../logging/toolkit_logger.dart';

const _tag = 'DownloadManager';

/// Lifecycle of a [DownloadTask].
enum DownloadState { queued, downloading, paused, completed, failed, cancelled }

/// Snapshot of a running download.
class DownloadProgress {
  final DownloadState state;
  final int receivedBytes;

  /// Total size of the file, or `null` if the server did not say.
  final int? totalBytes;

  /// Smoothed transfer rate over the last few seconds.
  final double bytesPerSecond;

  const DownloadProgress({
    required this.state,
    required this.receivedBytes,
    this.totalBytes,
    this.bytesPerSecond = 0,
  });

  /// 0..1, or `null` when the total is unknown.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  /// Estimated time left, or `null` when it cannot be estimated.
  Duration? get eta {
    final total = totalBytes;
    if (total == null || bytesPerSecond <= 0) return null;
    return Duration(
      milliseconds: ((total - receivedBytes) / bytesPerSecond * 1000).round(),
    );
  }

  @override
  String toString() => 'DownloadProgress($state, $receivedBytes/$totalBytes)';
}

/// What to download and where to put it.
class DownloadRequest {
  final Uri url;

  /// Final path; data is written to `<destination>.part` first.
  final String destination;
  final Map<String, String> headers;

  /// Lower-case hex SHA-256 to verify after the transfer.
  final String? sha256;

  /// Expected size, used to skip an already complete destination.
  final int? expectedSize;

  /// Return an existing destination (of the expected size) untouched.
  final bool skipIfExists;

  const DownloadRequest({
    required this.url,
    required this.destination,
    this.headers = const {},
    this.sha256,
    this.expectedSize,
    this.skipIfExists = true,
  });
}

/// The server answered with an unexpected HTTP status.
class HttpDownloadException extends DownloadException {
  final int statusCode;
  const HttpDownloadException(this.statusCode, super.message);
}

/// There is not enough free space for the file.
class InsufficientStorageException extends DownloadException {
  final int? requiredBytes;
  final int? availableBytes;
  const InsufficientStorageException(
    super.message, {
    this.requiredBytes,
    this.availableBytes,
  });
}

/// Reports free bytes on the volume holding a directory, or `null` if unknown.
typedef FreeSpaceProbe = Future<int?> Function(String directory);

class _Interrupted implements Exception {
  const _Interrupted();
}

/// Handle to one queued or running download.
class DownloadTask {
  final DownloadRequest request;

  final _progress = StreamController<DownloadProgress>.broadcast();
  final _done = Completer<File>();
  final _samples = Queue<(int, int)>();
  final _clock = Stopwatch()..start();

  DownloadProgress _latest = const DownloadProgress(
    state: DownloadState.queued,
    receivedBytes: 0,
  );
  CancelToken _http = CancelToken();
  Completer<void> _interrupt = Completer<void>();
  Completer<void>? _gate;
  bool _paused = false;
  bool _cancelled = false;
  int _lastEmitMs = -1000;

  DownloadTask._(this.request) {
    _done.future.ignore();
  }

  /// Progress snapshots; emits roughly ten times a second.
  Stream<DownloadProgress> get progress => _progress.stream;

  DownloadProgress get latest => _latest;

  /// Completes with the finished file, or fails with a [DownloadException].
  Future<File> get done => _done.future;

  bool get isFinished => switch (_latest.state) {
    DownloadState.completed ||
    DownloadState.failed ||
    DownloadState.cancelled => true,
    _ => false,
  };

  /// Stops transferring but keeps the partial file; see [resume].
  void pause() {
    if (isFinished || _paused) return;
    _paused = true;
    _gate = Completer<void>();
    _signal();
    _emit(DownloadState.paused);
  }

  void resume() {
    if (!_paused || _cancelled) return;
    _paused = false;
    _interrupt = Completer<void>();
    _gate?.complete();
    _gate = null;
    _emit(DownloadState.queued);
  }

  /// Aborts the download and deletes the partial file.
  void cancel() {
    if (isFinished || _cancelled) return;
    _cancelled = true;
    _signal();
    if (_gate != null && !_gate!.isCompleted) _gate!.complete();
  }

  void _signal() {
    if (!_interrupt.isCompleted) _interrupt.complete();
    if (!_http.isCancelled) _http.cancel('interrupted');
  }

  void _emit(DownloadState state, {int? received, int? total}) {
    final bytes = received ?? _latest.receivedBytes;
    final now = _clock.elapsedMilliseconds;
    _samples.addLast((now, bytes));
    while (_samples.length > 2 && now - _samples.first.$1 > 3000) {
      _samples.removeFirst();
    }
    var speed = 0.0;
    if (state == DownloadState.downloading && _samples.length > 1) {
      final span = now - _samples.first.$1;
      if (span > 0) speed = (bytes - _samples.first.$2) * 1000 / span;
    }
    _latest = DownloadProgress(
      state: state,
      receivedBytes: bytes,
      totalBytes: total ?? _latest.totalBytes,
      bytesPerSecond: speed,
    );
    _lastEmitMs = now;
    if (!_progress.isClosed) _progress.add(_latest);
  }

  void _emitThrottled(int received, int? total) {
    if (_clock.elapsedMilliseconds - _lastEmitMs < 100) return;
    _emit(DownloadState.downloading, received: received, total: total);
  }

  void _finish(DownloadState state, {File? file, Object? error}) {
    _emit(state);
    if (file != null) {
      _done.complete(file);
    } else {
      _done.completeError(error!);
    }
    _progress.close();
  }
}

class _Semaphore {
  _Semaphore(this._free);

  int _free;
  final _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_free > 0) {
      _free--;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _free++;
    }
  }
}

/// Resumable HTTP downloader with a concurrency limit.
///
/// Data goes to `<destination>.part` and is renamed atomically once complete
/// and verified. An interrupted transfer (pause, network loss, app restart)
/// continues from the partial file with an HTTP `Range` request.
class DownloadManager {
  final Dio _dio;
  final _Semaphore _slots;
  final int maxRetries;
  final Duration retryDelay;
  final FreeSpaceProbe? freeSpace;
  final _tasks = <DownloadTask>{};

  DownloadManager({
    Dio? dio,
    int maxConcurrent = 2,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.freeSpace,
  }) : assert(maxConcurrent > 0),
       _slots = _Semaphore(maxConcurrent),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 60),
             ),
           );

  /// Downloads that are queued, running or paused.
  List<DownloadTask> get activeTasks => List.unmodifiable(_tasks);

  /// Starts (or queues) a download.
  DownloadTask enqueue(DownloadRequest request) {
    final task = DownloadTask._(request);
    _tasks.add(task);
    unawaited(_run(task));
    return task;
  }

  Future<void> _run(DownloadTask task) async {
    try {
      final file = await _execute(task);
      task._finish(DownloadState.completed, file: file);
    } on _Interrupted {
      await _deletePart(task.request.destination);
      task._finish(
        DownloadState.cancelled,
        error: const DownloadException('Download cancelled'),
      );
    } on DownloadException catch (e) {
      task._finish(DownloadState.failed, error: e);
    } catch (e, st) {
      ToolkitLog.error(_tag, 'Unexpected failure', e, st);
      task._finish(
        DownloadState.failed,
        error: DownloadException('Download failed: $e', e),
      );
    } finally {
      _tasks.remove(task);
    }
  }

  Future<File> _execute(DownloadTask task) async {
    final request = task.request;
    final destination = File(request.destination);
    final partPath = '${request.destination}.part';
    final part = File(partPath);

    if (request.skipIfExists && await destination.exists()) {
      final length = await destination.length();
      if (request.expectedSize == null || request.expectedSize == length) {
        task._emit(DownloadState.completed, received: length, total: length);
        return destination;
      }
    }
    await destination.parent.create(recursive: true);

    var failures = 0;
    var restarted = false;
    while (true) {
      if (task._cancelled) throw const _Interrupted();
      if (task._paused) {
        await task._gate!.future;
        continue;
      }

      final grant = _slots.acquire();
      await Future.any([grant, task._interrupt.future]);
      if (task._cancelled || task._paused) {
        unawaited(grant.then((_) => _slots.release()));
        continue;
      }

      final before = await part.exists() ? await part.length() : 0;
      try {
        task._http = CancelToken();
        final complete = await _transfer(task, part, restarted);
        if (complete) break;
        restarted = true;
      } on _Interrupted {
        if (task._cancelled) rethrow;
      } on DioException catch (e) {
        if (task._cancelled) throw const _Interrupted();
        if (task._paused) continue;
        final progressed = await part.exists() && await part.length() > before;
        failures = progressed ? 1 : failures + 1;
        if (!_isRetryable(e) || failures > maxRetries) {
          throw DownloadException(_describe(e), e);
        }
        ToolkitLog.warning(_tag, 'Retrying after ${e.type.name}', e);
        await Future<void>.delayed(retryDelay * failures);
      } on HttpDownloadException catch (e) {
        if ((e.statusCode < 500 && e.statusCode != 429) ||
            ++failures > maxRetries) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay * failures);
      } finally {
        _slots.release();
      }
    }

    final expected = request.sha256?.toLowerCase();
    if (expected != null) {
      final actual = (await sha256.bind(part.openRead()).first).toString();
      if (actual != expected) {
        await part.delete();
        throw DownloadException(
          'Checksum mismatch for ${request.destination}: '
          'expected $expected, got $actual',
        );
      }
    }
    if (await destination.exists()) await destination.delete();
    await part.rename(request.destination);
    final size = await destination.length();
    task._emit(DownloadState.completed, received: size, total: size);
    return destination;
  }

  /// Runs one HTTP exchange. Returns `true` when the partial file is complete,
  /// `false` when the partial file was discarded and the caller should retry.
  Future<bool> _transfer(DownloadTask task, File part, bool restarted) async {
    final request = task.request;
    var offset = await part.exists() ? await part.length() : 0;

    final response = await _dio.getUri<ResponseBody>(
      request.url,
      cancelToken: task._http,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        headers: {
          ...request.headers,
          if (offset > 0) HttpHeaders.rangeHeader: 'bytes=$offset-',
        },
      ),
    );
    final body = response.data!;
    final status = response.statusCode ?? 0;

    if (status == 416 && offset > 0) {
      final total = _rangeTotal(response.headers.value('content-range'));
      task._http.cancel('discarded');
      if (total == offset) return true;
      if (restarted) {
        throw const HttpDownloadException(416, 'Server rejected range request');
      }
      await part.delete();
      return false;
    }
    if (status != 200 && status != 206) {
      task._http.cancel('discarded');
      throw HttpDownloadException(status, _statusMessage(status, request.url));
    }

    int? total;
    if (status == 206) {
      final range = response.headers.value('content-range');
      total = _rangeTotal(range);
      final start = int.tryParse(
        RegExp(r'bytes (\d+)-').firstMatch(range ?? '')?.group(1) ?? '',
      );
      if (start != offset) {
        task._http.cancel('discarded');
        await part.delete();
        return false;
      }
    } else {
      offset = 0;
      total = int.tryParse(response.headers.value('content-length') ?? '');
    }

    final remaining = total == null ? null : total - offset;
    if (remaining != null && freeSpace != null) {
      final available = await freeSpace!(part.parent.path);
      if (available != null && available < remaining) {
        task._http.cancel('discarded');
        throw InsufficientStorageException(
          'Not enough free space: need ${remaining ~/ (1024 * 1024)} MB, '
          '${available ~/ (1024 * 1024)} MB available',
          requiredBytes: remaining,
          availableBytes: available,
        );
      }
    }

    final raf = await part.open(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var received = offset;
    task._emit(DownloadState.downloading, received: received, total: total);
    try {
      await for (final Uint8List chunk in body.stream) {
        if (task._paused || task._cancelled) throw const _Interrupted();
        await raf.writeFrom(chunk);
        received += chunk.length;
        task._emitThrottled(received, total);
      }
    } on FileSystemException catch (e) {
      if (_isNoSpace(e)) {
        throw InsufficientStorageException(
          'Disk full while writing ${part.path}',
          requiredBytes: remaining,
        );
      }
      throw DownloadException('Could not write ${part.path}: ${e.message}', e);
    } finally {
      await raf.close();
    }
    if (total != null && received != total) {
      throw DownloadException(
        'Connection closed early ($received of $total bytes)',
      );
    }
    task._emit(DownloadState.downloading, received: received, total: total);
    return true;
  }

  Future<void> _deletePart(String destination) async {
    final part = File('$destination.part');
    if (await part.exists()) await part.delete();
  }

  /// Cancels every active task.
  void cancelAll() {
    for (final task in List.of(_tasks)) {
      task.cancel();
    }
  }

  void close() {
    cancelAll();
    _dio.close();
  }

  static int? _rangeTotal(String? header) {
    final total = header?.split('/').last;
    return total == null ? null : int.tryParse(total);
  }

  static bool _isNoSpace(FileSystemException e) {
    final code = e.osError?.errorCode;
    return code == 28 || code == 112 || code == 39;
  }

  static bool _isRetryable(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.connectionError => true,
    DioExceptionType.unknown => e.error is IOException,
    _ => false,
  };

  static String _describe(DioException e) =>
      'Network error (${e.type.name}) while downloading: ${e.message ?? e.error}';

  static String _statusMessage(int status, Uri url) => switch (status) {
    401 || 403 =>
      'Access denied (HTTP $status) for $url. Gated models need an accepted '
          'licence and a valid access token.',
    404 => 'File not found (HTTP 404): $url',
    429 => 'Rate limited by the server (HTTP 429)',
    _ => 'Unexpected HTTP $status for $url',
  };
}
