import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'sherpa_worker.dart';

/// Everything the recognition worker needs to build its native objects.
final class AsrWorkerArgs {
  final sherpa.OfflineRecognizerConfig? offline;
  final sherpa.OnlineRecognizerConfig? online;
  final sherpa.VadModelConfig? vad;

  const AsrWorkerArgs({this.offline, this.online, this.vad});
}

/// Requests understood by the recognition worker.
sealed class AsrRequest {
  const AsrRequest();
}

/// Transcribe a whole utterance of 16 kHz samples.
final class AsrDecode extends AsrRequest {
  final TransferableTypedData samples;
  const AsrDecode(this.samples);
}

/// Push live 16 kHz samples; answers `(finished texts, partial text)`.
final class AsrFeed extends AsrRequest {
  final TransferableTypedData samples;
  const AsrFeed(this.samples);
}

/// End of live input; answers the remaining finished texts.
final class AsrFinish extends AsrRequest {
  const AsrFinish();
}

const _rate = 16000;

/// Builds the recognizer (and optional VAD) inside the worker isolate.
SherpaWorkerSetup asrWorkerInit(Object? arg) {
  final a = arg as AsrWorkerArgs;
  final offline =
      a.offline == null ? null : sherpa.OfflineRecognizer(a.offline!);
  final online = a.online == null ? null : sherpa.OnlineRecognizer(a.online!);
  final vad =
      a.vad == null
          ? null
          : sherpa.VoiceActivityDetector(
            config: a.vad!,
            bufferSizeInSeconds: 60,
          );
  final windowSize = a.vad?.sileroVad.windowSize ?? 512;
  var pending = Float32List(0);
  sherpa.OnlineStream? live;

  String decodeOffline(Float32List samples) {
    final stream = offline!.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _rate);
      offline.decode(stream);
      return offline.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  String decodeOnline(Float32List samples) {
    final stream = online!.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _rate);
      stream.acceptWaveform(
        samples: Float32List(_rate ~/ 2),
        sampleRate: _rate,
      );
      stream.inputFinished();
      while (online.isReady(stream)) {
        online.decode(stream);
      }
      return online.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  List<String> drainVad() {
    final out = <String>[];
    while (!vad!.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      final text = decodeOffline(segment.samples);
      if (text.isNotEmpty) out.add(text);
    }
    return out;
  }

  Float32List samplesOf(TransferableTypedData data) =>
      data.materialize().asFloat32List();

  Object? handle(Object? request) {
    switch (request as AsrRequest) {
      case AsrDecode(:final samples):
        final audio = samplesOf(samples);
        return online != null ? decodeOnline(audio) : decodeOffline(audio);
      case AsrFeed(:final samples):
        final audio = samplesOf(samples);
        if (online != null) {
          final stream = live ??= online.createStream();
          stream.acceptWaveform(samples: audio, sampleRate: _rate);
          final finished = <String>[];
          while (online.isReady(stream)) {
            online.decode(stream);
          }
          final text = online.getResult(stream).text.trim();
          if (online.isEndpoint(stream)) {
            if (text.isNotEmpty) finished.add(text);
            online.reset(stream);
            return (finished, '');
          }
          return (finished, text);
        }
        final joined =
            Float32List(pending.length + audio.length)
              ..setAll(0, pending)
              ..setAll(pending.length, audio);
        final usable = joined.length - joined.length % windowSize;
        for (var i = 0; i < usable; i += windowSize) {
          vad!.acceptWaveform(
            Float32List.sublistView(joined, i, i + windowSize),
          );
        }
        pending = Float32List.fromList(joined.sublist(usable));
        return (drainVad(), '');
      case AsrFinish():
        if (online != null) {
          final stream = live;
          if (stream == null) return <String>[];
          stream.acceptWaveform(
            samples: Float32List(_rate ~/ 2),
            sampleRate: _rate,
          );
          stream.inputFinished();
          while (online.isReady(stream)) {
            online.decode(stream);
          }
          final text = online.getResult(stream).text.trim();
          stream.free();
          live = null;
          return [if (text.isNotEmpty) text];
        }
        if (pending.isNotEmpty) {
          final padded = Float32List(windowSize)..setAll(0, pending);
          vad!.acceptWaveform(padded);
          pending = Float32List(0);
        }
        vad!.flush();
        return drainVad();
    }
  }

  void dispose() {
    live?.free();
    vad?.free();
    offline?.free();
    online?.free();
  }

  return (handle: handle, dispose: dispose);
}
