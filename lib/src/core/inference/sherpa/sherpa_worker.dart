import 'dart:async';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../exceptions/llm_toolkit_exceptions.dart';

var _bindingsReady = false;

/// Loads the native sherpa-onnx library once for the calling isolate.
///
/// Every isolate has its own FFI state, so workers call this themselves.
void ensureSherpaBindings() {
  if (_bindingsReady) return;
  sherpa.initBindings();
  _bindingsReady = true;
}

/// Answers requests inside a worker isolate.
typedef SherpaHandler = FutureOr<Object?> Function(Object? request);

/// What [SherpaWorkerInit] returns: a request handler and its cleanup.
typedef SherpaWorkerSetup = ({SherpaHandler handle, void Function() dispose});

/// Runs inside the worker isolate to build the native objects it owns. Must be
/// a top-level or static function; [arg] must be sendable between isolates.
typedef SherpaWorkerInit = SherpaWorkerSetup Function(Object? arg);

typedef _Boot = (SendPort, SherpaWorkerInit, Object?, bool);

/// A long-lived isolate owning native sherpa objects, so heavy decoding never
/// blocks the UI isolate.
final class SherpaWorker {
  final SendPort _inbox;
  bool _closed = false;

  SherpaWorker._(this._inbox);

  /// Starts a worker. Set [loadNative] to false for workers that touch no
  /// sherpa objects.
  static Future<SherpaWorker> spawn(
    SherpaWorkerInit init,
    Object? arg, {
    bool loadNative = true,
  }) async {
    final ready = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<_Boot>(_entry, (
        ready.sendPort,
        init,
        arg,
        loadNative,
      ));
    } catch (e) {
      ready.close();
      throw InferenceException('Could not start the sherpa worker', e);
    }
    final reply = await ready.first as List<Object?>;
    ready.close();
    if (reply[0] == 'err') {
      isolate.kill();
      throw InferenceException(reply[1] as String);
    }
    return SherpaWorker._(reply[1] as SendPort);
  }

  /// Sends [message] to the worker and returns its answer.
  Future<T> request<T>(Object? message) async {
    if (_closed) throw const InferenceException('Sherpa worker is closed');
    final port = ReceivePort();
    _inbox.send((port.sendPort, message));
    final reply = await port.first as List<Object?>;
    port.close();
    if (reply[0] == 'err') throw InferenceException(reply[1] as String);
    return reply[1] as T;
  }

  /// Frees the native objects and stops the isolate.
  void close() {
    if (_closed) return;
    _closed = true;
    _inbox.send(null);
  }
}

Future<void> _entry(_Boot boot) async {
  final (ready, init, arg, loadNative) = boot;
  final inbox = ReceivePort();
  final SherpaWorkerSetup setup;
  try {
    if (loadNative) ensureSherpaBindings();
    setup = init(arg);
  } catch (e) {
    ready.send(['err', 'Sherpa worker failed to start: $e']);
    return;
  }
  ready.send(['ok', inbox.sendPort]);
  await for (final Object? message in inbox) {
    if (message == null) {
      setup.dispose();
      inbox.close();
      break;
    }
    final (SendPort reply, Object? request) = message as (SendPort, Object?);
    try {
      reply.send(['ok', await setup.handle(request)]);
    } catch (e) {
      reply.send(['err', '$e']);
    }
  }
}
