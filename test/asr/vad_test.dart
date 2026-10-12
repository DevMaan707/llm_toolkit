import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/asr/asr.dart';

import 'helpers.dart';

void main() {
  const vad = VoiceActivityDetector(threshold: 0.05, frameSamples: 1600);
  final silence = Float32List(16000);
  final speech = sine(300, 16000, 1);

  test('rms of silence, DC and sine', () {
    expect(rms(silence), 0);
    expect(rms(Float32List.fromList([0.5, 0.5, 0.5])), closeTo(0.5, 1e-9));
    expect(rms(speech), closeTo(0.5 / 1.41421356, 1e-3));
    expect(rms(Float32List(0)), 0);
  });

  test('speechRatio counts frames above the threshold', () {
    final mixed = Float32List.fromList([...silence, ...speech]);
    expect(vad.speechRatio(silence), 0);
    expect(vad.speechRatio(speech), 1);
    expect(vad.speechRatio(mixed), closeTo(0.5, 1e-9));
  });

  test('containsSpeech respects minRatio and empty input', () {
    final mostlySilent = Float32List.fromList([
      ...silence,
      ...speech.sublist(0, 1600),
    ]);
    expect(vad.containsSpeech(mostlySilent), isTrue);
    expect(vad.containsSpeech(mostlySilent, minRatio: 0.5), isFalse);
    expect(vad.containsSpeech(silence), isFalse);
    expect(vad.containsSpeech(Float32List(0), minRatio: 0), isFalse);
  });

  group('EndpointDetector', () {
    EndpointDetector make() => EndpointDetector(
      vad: vad,
      sampleRate: 16000,
      silenceTimeout: const Duration(milliseconds: 500),
    );

    test('stops after the silence timeout following speech', () {
      final d = make();
      expect(d.feed(speech), isFalse);
      expect(d.heardSpeech, isTrue);
      expect(d.feed(Float32List(4000)), isFalse); // 250 ms
      expect(d.feed(Float32List(4000)), isTrue); // 500 ms
    });

    test('speech resets the silence counter', () {
      final d = make();
      d.feed(Float32List(6000));
      d.feed(speech.sublist(0, 1600));
      expect(d.feed(Float32List(6000)), isFalse);
      expect(d.feed(Float32List(2000)), isTrue);
    });

    test('also ends if nobody ever speaks', () {
      final d = make();
      expect(d.feed(Float32List(8000)), isTrue);
      expect(d.heardSpeech, isFalse);
    });
  });
}
