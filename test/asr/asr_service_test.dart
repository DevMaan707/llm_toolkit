import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/asr/asr.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';
import 'package:llm_toolkit/src/services/asr_service.dart';

import 'helpers.dart';

class FakeRecognizer implements SpeechRecognizer {
  final List<Uint8List> calls = [];
  final List<String> replies;
  Object? failWith;

  FakeRecognizer([this.replies = const ['hello world']]);

  @override
  Future<String> transcribe(Uint8List audio) async {
    calls.add(audio);
    if (failWith != null) throw failWith!;
    return replies[(calls.length - 1).clamp(0, replies.length - 1)];
  }
}

class FakeRecorder implements PcmRecorder {
  bool permission = true;
  bool disposed = false;
  int? startedAt;
  StreamController<Uint8List>? _controller;

  void emit(Uint8List pcm) => _controller!.add(pcm);

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> start(int sampleRate) async {
    startedAt = sampleRate;
    _controller = StreamController<Uint8List>();
    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    await _controller?.close();
  }

  @override
  Future<void> dispose() async => disposed = true;
}

Uint8List _secondOf(double hz, {double seconds = 1, double amp = 0.5}) =>
    toPcm16(sine(hz, 16000, seconds, amp: amp));

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  const oneSecondWindows = ASRConfig(
    chunkDuration: Duration(seconds: 1),
    overlapDuration: Duration(milliseconds: 250),
  );

  group('transcription', () {
    test(
      'transcribeBytes wraps raw PCM16 in a WAV carrying the sample rate',
      () async {
        final recognizer = FakeRecognizer();
        final service = ASRService.withRecognizer(recognizer);
        final text = await service.transcribeBytes(
          _secondOf(440, seconds: 0.1),
          format: AudioFormat.pcm16,
          sampleRate: 8000,
        );
        expect(text, 'hello world');
        final sent = decodeAudio(recognizer.calls.single);
        expect(sent.sampleRate, 8000);
        expect(sent.samples.length, 1600);
      },
    );

    test('WAV input is passed through untouched', () async {
      final recognizer = FakeRecognizer();
      final wav = encodeWav16(sine(440, 16000, 0.1), 16000);
      await ASRService.withRecognizer(recognizer).transcribeBytes(wav);
      expect(recognizer.calls.single, wav);
    });

    test('float32 input is converted to WAV', () async {
      final recognizer = FakeRecognizer();
      final tone = sine(440, 16000, 0.1);
      await ASRService.withRecognizer(
        recognizer,
      ).transcribeBytes(tone.buffer.asUint8List(), format: AudioFormat.float32);
      expect(decodeAudio(recognizer.calls.single).samples.length, tone.length);
    });

    test('requires initialisation', () {
      expect(
        ASRService().transcribeBytes(Uint8List(4)),
        throwsA(isA<InferenceException>()),
      );
    });

    test('transcribeFile reports a missing file', () {
      final service = ASRService.withRecognizer(FakeRecognizer());
      expect(
        service.transcribeFile('/definitely/not/here.wav'),
        throwsA(isA<InferenceException>()),
      );
    });

    test('initialize is refused when a recognizer was injected', () {
      final service = ASRService.withRecognizer(FakeRecognizer());
      expect(service.initialize('model.tflite'), throwsStateError);
    });
  });

  group('recording', () {
    test('start/stop transcribes everything captured', () async {
      final recognizer = FakeRecognizer(['recorded text']);
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(recognizer, recorder: recorder);

      await service.startRecording();
      expect(service.isRecording, isTrue);
      expect(recorder.startedAt, 16000);
      recorder.emit(_secondOf(300, seconds: 0.2));
      recorder.emit(_secondOf(300, seconds: 0.2));
      await _tick();

      expect(await service.stopRecording(), 'recorded text');
      expect(service.isRecording, isFalse);
      expect(decodeAudio(recognizer.calls.single).samples.length, 6400);
    });

    test('permission denied leaves the service idle', () async {
      final recorder = FakeRecorder()..permission = false;
      final service = ASRService.withRecognizer(
        FakeRecognizer(),
        recorder: recorder,
      );
      await expectLater(
        service.startRecording(),
        throwsA(isA<InferenceException>()),
      );
      expect(service.isRecording, isFalse);
      expect(await service.testMicrophoneAccess(), isFalse);
    });

    test('cannot start twice or stop when idle', () async {
      final service = ASRService.withRecognizer(
        FakeRecognizer(),
        recorder: FakeRecorder(),
      );
      await expectLater(
        service.stopRecording(),
        throwsA(isA<InferenceException>()),
      );
      await service.startRecording();
      await expectLater(
        service.startRecording(),
        throwsA(isA<InferenceException>()),
      );
      await service.stopRecording();
    });

    test(
      'an empty recording yields an empty string without calling the model',
      () async {
        final recognizer = FakeRecognizer();
        final service = ASRService.withRecognizer(
          recognizer,
          recorder: FakeRecorder(),
        );
        await service.startRecording();
        expect(await service.stopRecording(), '');
        expect(recognizer.calls, isEmpty);
      },
    );

    test('recordAndTranscribe records for the duration', () async {
      final recognizer = FakeRecognizer(['timed']);
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(recognizer, recorder: recorder);
      final future = service.recordAndTranscribe(
        const Duration(milliseconds: 30),
      );
      await _tick();
      recorder.emit(_secondOf(300, seconds: 0.1));
      expect(await future, 'timed');
    });
  });

  group('recordWithVAD', () {
    test('stops on its own after silence following speech', () async {
      final recognizer = FakeRecognizer(['voice command']);
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(recognizer, recorder: recorder);

      final future = service.recordWithVAD(
        silenceTimeout: const Duration(milliseconds: 500),
        maxDuration: const Duration(seconds: 5),
      );
      await _tick();
      recorder.emit(_secondOf(300, seconds: 0.5));
      recorder.emit(Uint8List(16000)); // 0.5 s of silence
      expect(await future, 'voice command');
      expect(service.isRecording, isFalse);
    });

    test('maxDuration ends a recording that never goes quiet', () async {
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(
        FakeRecognizer(['x']),
        recorder: recorder,
      );
      final future = service.recordWithVAD(
        maxDuration: const Duration(milliseconds: 50),
        silenceTimeout: const Duration(seconds: 10),
      );
      await _tick();
      recorder.emit(_secondOf(300, seconds: 0.1));
      expect(await future, 'x');
    });
  });

  group('streaming', () {
    test('emits de-duplicated text for overlapping windows', () async {
      final recognizer = FakeRecognizer([
        'good morning everyone welcome',
        'everyone welcome to the show',
      ]);
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(
        recognizer,
        config: oneSecondWindows,
        recorder: recorder,
      );

      final received = <String>[];
      final done = Completer<void>();
      service.startStreamingTranscription().listen(
        received.add,
        onDone: done.complete,
      );
      await _tick();
      expect(service.isStreaming, isTrue);

      recorder.emit(_secondOf(300)); // first window
      await _tick();
      recorder.emit(
        _secondOf(300, seconds: 0.75),
      ); // second window (0.25 s carried)
      await _tick();
      await service.stopStreamingTranscription();
      await done.future;

      expect(received, ['good morning everyone welcome', 'to the show']);
      expect(recognizer.calls, hasLength(2));
      expect(decodeAudio(recognizer.calls.first).samples.length, 16000);
      expect(service.isStreaming, isFalse);
    });

    test('skips silent windows when VAD is enabled', () async {
      final recognizer = FakeRecognizer();
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(
        recognizer,
        config: oneSecondWindows.copyWith(enableVAD: true),
        recorder: recorder,
      );
      final received = <String>[];
      service.startStreamingTranscription().listen(received.add);
      await _tick();
      recorder.emit(Uint8List(32000)); // 1 s silence
      await _tick();
      await service.stopStreamingTranscription();
      expect(recognizer.calls, isEmpty);
      expect(received, isEmpty);
    });

    test('the remaining audio is transcribed on stop', () async {
      final recognizer = FakeRecognizer(['tail words']);
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(
        recognizer,
        config: oneSecondWindows,
        recorder: recorder,
      );
      final received = <String>[];
      service.startStreamingTranscription().listen(received.add);
      await _tick();
      recorder.emit(_secondOf(300, seconds: 0.6));
      await _tick();
      await service.stopStreamingTranscription();
      expect(received, ['tail words']);
    });

    test('meaningless output and recognizer failures are skipped', () async {
      final recognizer = FakeRecognizer(['[BLANK_AUDIO]']);
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(
        recognizer,
        config: oneSecondWindows,
        recorder: recorder,
      );
      final received = <String>[];
      service.startStreamingTranscription().listen(received.add);
      await _tick();
      recorder.emit(_secondOf(300));
      await _tick();
      recognizer.failWith = StateError('boom');
      recorder.emit(_secondOf(300));
      await _tick();
      await service.stopStreamingTranscription();
      expect(received, isEmpty);
      expect(recognizer.calls.length, greaterThanOrEqualTo(2));
    });

    test('permission failure surfaces as a stream error', () async {
      final recorder = FakeRecorder()..permission = false;
      final service = ASRService.withRecognizer(
        FakeRecognizer(),
        recorder: recorder,
      );
      await expectLater(
        service.startStreamingTranscription(),
        emitsError(isA<InferenceException>()),
      );
      expect(service.isStreaming, isFalse);
    });

    test('cancelling the subscription stops the microphone', () async {
      final recorder = FakeRecorder();
      final service = ASRService.withRecognizer(
        FakeRecognizer(),
        recorder: recorder,
      );
      final sub = service.startStreamingTranscription().listen((_) {});
      await _tick();
      await sub.cancel();
      await _tick();
      expect(service.isStreaming, isFalse);
    });
  });

  test('dispose stops capture and releases the recorder', () async {
    final recorder = FakeRecorder();
    final service = ASRService.withRecognizer(
      FakeRecognizer(),
      recorder: recorder,
    );
    await service.startRecording();
    await service.dispose();
    expect(service.isRecording, isFalse);
    expect(recorder.disposed, isTrue);
  });
}
