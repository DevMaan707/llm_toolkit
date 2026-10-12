import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/config.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';
import 'package:llm_toolkit/src/core/inference/sherpa/sherpa_asr_config.dart';
import 'package:llm_toolkit/src/core/inference/sherpa/sherpa_asr_engine.dart';
import 'package:llm_toolkit/src/core/inference/sherpa/sherpa_layout.dart';
import 'package:llm_toolkit/src/core/inference/sherpa/sherpa_tts_config.dart';
import 'package:llm_toolkit/src/core/inference/sherpa/sherpa_tts_engine.dart';
import 'package:llm_toolkit/src/core/inference/sherpa/sherpa_worker.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';
import 'package:path/path.dart' as p;

SherpaWorkerSetup _echo(Object? arg) => (
  handle: (Object? r) {
    if (r == 'boom') throw StateError('exploded');
    return '$arg:$r';
  },
  dispose: () {},
);

SherpaWorkerSetup _failingInit(Object? arg) => throw StateError('bad model');

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('sherpa_engine'));
  tearDown(() => root.deleteSync(recursive: true));

  Directory model(String name, List<String> files) {
    final dir = Directory(p.join(root.path, name))..createSync();
    for (final f in files) {
      File(p.join(dir.path, f)).writeAsBytesSync(const []);
    }
    return dir;
  }

  const config = InferenceConfig.defaults();

  group('SherpaAsrEngine', () {
    test('identity', () {
      final e = SherpaAsrEngine();
      expect(e.id, 'sherpa-asr');
      expect(e.capabilities, {ModelCapability.speechToText});
      expect(e.isModelLoaded, isFalse);
    });

    test(
      'rejects missing folder, plain file, unknown layout, no tokens',
      () async {
        final e = SherpaAsrEngine();
        await expectLater(
          e.loadModel(p.join(root.path, 'missing'), config),
          throwsA(isA<InferenceException>()),
        );
        final file = File(p.join(root.path, 'a.onnx'))
          ..writeAsBytesSync(const []);
        await expectLater(
          e.loadModel(file.path, config),
          throwsA(
            isA<InferenceException>().having(
              (x) => x.message,
              'm',
              contains('folders'),
            ),
          ),
        );
        await expectLater(
          e.loadModel(
            model('weird', ['tokens.txt', 'a.onnx', 'b.onnx']).path,
            config,
          ),
          throwsA(isA<InferenceException>()),
        );
        await expectLater(
          e.loadModel(model('notokens', ['model.onnx']).path, config),
          throwsA(
            isA<InferenceException>().having(
              (x) => x.message,
              'm',
              contains('tokens.txt'),
            ),
          ),
        );
        expect(e.isModelLoaded, isFalse);
      },
    );

    test('rejects a TTS folder and a missing VAD model', () async {
      final e = SherpaAsrEngine();
      await expectLater(
        e.loadModel(
          model('kokoro-x', ['model.onnx', 'voices.bin', 'tokens.txt']).path,
          config,
        ),
        throwsA(
          isA<InferenceException>().having(
            (x) => x.message,
            'm',
            contains('synthesis'),
          ),
        ),
      );
      final dir = model('sherpa-onnx-sense-voice', [
        'model.onnx',
        'tokens.txt',
      ]);
      await expectLater(
        e.loadModel(
          dir.path,
          config.copyWith(extra: {'vadModel': '/nope/silero.onnx'}),
        ),
        throwsA(
          isA<InferenceException>().having(
            (x) => x.message,
            'm',
            contains('VAD'),
          ),
        ),
      );
    });

    test('transcribe and streaming need a loaded model', () async {
      final e = SherpaAsrEngine();
      await expectLater(
        e.transcribe(Uint8List(4)),
        throwsA(isA<InferenceException>()),
      );
      await expectLater(
        e.transcribeStream(const Stream.empty()).toList(),
        throwsA(isA<InferenceException>()),
      );
    });

    test('options come from InferenceConfig', () {
      final o = SherpaAsrOptions.fromConfig(
        config.copyWith(
          threads: 3,
          extra: {
            'language': 'de',
            'provider': 'nnapi',
            'streaming': true,
            'vadModel': 'v.onnx',
          },
        ),
      );
      expect(o.numThreads, 3);
      expect(o.language, 'de');
      expect(o.provider, 'nnapi');
      expect(o.streaming, isTrue);
      expect(o.vadModel, 'v.onnx');
    });
  });

  group('recognizer configs', () {
    SherpaAsrLayout layout(String name, List<String> files) =>
        SherpaModelLayout.detect(model(name, files)) as SherpaAsrLayout;

    test('whisper maps encoder, decoder, language and threads', () {
      final l = layout('whisper-tiny', [
        't-encoder.onnx',
        't-decoder.onnx',
        'tokens.txt',
      ]);
      final c = buildOfflineConfig(
        l,
        const SherpaAsrOptions(language: 'en', numThreads: 4),
      );
      expect(c.model.whisper.encoder, l.path(SherpaFileRole.encoder));
      expect(c.model.whisper.language, 'en');
      expect(c.model.numThreads, 4);
      expect(c.model.tokens, l.tokens);
    });

    test('parakeet is tagged nemo_transducer', () {
      final l = layout('sherpa-onnx-nemo-parakeet-tdt', [
        'encoder.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      ]);
      expect(
        buildOfflineConfig(l, const SherpaAsrOptions()).model.modelType,
        'nemo_transducer',
      );
    });

    test('zipformer transducer has no model type', () {
      final l = layout('zipformer-en', [
        'encoder.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      ]);
      expect(
        buildOfflineConfig(l, const SherpaAsrOptions()).model.modelType,
        '',
      );
    });

    test('moonshine merged decoder', () {
      final l = layout('moonshine-tiny', [
        'preprocess.onnx',
        'encode.onnx',
        'merged_decode.onnx',
        'tokens.txt',
      ]);
      expect(
        buildOfflineConfig(
          l,
          const SherpaAsrOptions(),
        ).model.moonshine.mergedDecoder,
        isNotEmpty,
      );
    });

    test('streaming layouts build online configs only', () {
      final l = layout('streaming-zipformer-en', [
        'encoder.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      ]);
      expect(
        buildOnlineConfig(l, const SherpaAsrOptions()).model.transducer.joiner,
        isNotEmpty,
      );
      expect(
        () => buildOfflineConfig(l, const SherpaAsrOptions()),
        throwsArgumentError,
      );
    });

    test('offline layouts cannot build online configs', () {
      final l = layout('sense-voice', ['model.onnx', 'tokens.txt']);
      expect(
        () => buildOnlineConfig(l, const SherpaAsrOptions()),
        throwsArgumentError,
      );
      expect(
        buildOfflineConfig(l, const SherpaAsrOptions()).model.senseVoice.model,
        isNotEmpty,
      );
    });
  });

  group('SherpaTtsEngine', () {
    test('identity and unloaded state', () async {
      final e = SherpaTtsEngine();
      expect(e.id, 'sherpa-tts');
      expect(e.capabilities, {ModelCapability.textToSpeech});
      await expectLater(e.synthesize('hi'), throwsA(isA<InferenceException>()));
    });

    test('rejects missing folder and ASR folders', () async {
      final e = SherpaTtsEngine();
      await expectLater(
        e.loadModel(p.join(root.path, 'missing'), config),
        throwsA(isA<InferenceException>()),
      );
      await expectLater(
        e.loadModel(
          model('sense-voice', ['model.onnx', 'tokens.txt']).path,
          config,
        ),
        throwsA(
          isA<InferenceException>().having(
            (x) => x.message,
            'm',
            contains('recognition'),
          ),
        ),
      );
      await expectLater(
        e.loadModel(
          model('kokoro-nt', ['model.onnx', 'voices.bin']).path,
          config,
        ),
        throwsA(
          isA<InferenceException>().having(
            (x) => x.message,
            'm',
            contains('tokens.txt'),
          ),
        ),
      );
    });

    test('matcha without a vocoder is rejected', () {
      final l =
          SherpaModelLayout.detect(
                model('matcha-en', ['model-steps-3.onnx', 'tokens.txt']),
              )
              as SherpaTtsLayout;
      expect(
        () => buildTtsConfig(l, numThreads: 1),
        throwsA(isA<InferenceException>()),
      );
      final c = buildTtsConfig(l, numThreads: 1, vocoder: 'v.onnx');
      expect(c.model.matcha.vocoder, 'v.onnx');
    });

    test('kokoro config carries voices and lexicon', () {
      final l =
          SherpaModelLayout.detect(
                model('kokoro-v1', [
                  'model.onnx',
                  'voices.bin',
                  'tokens.txt',
                  'lexicon-us-en.txt',
                ]),
              )
              as SherpaTtsLayout;
      final c = buildTtsConfig(l, numThreads: 2, lang: 'en-us');
      expect(c.model.kokoro.voices, l.voices);
      expect(c.model.kokoro.lexicon, l.lexicon);
      expect(c.model.kokoro.lang, 'en-us');
      expect(c.model.numThreads, 2);
    });
  });

  group('SherpaWorker', () {
    test('round trips requests and reports handler errors', () async {
      final w = await SherpaWorker.spawn(_echo, 'x', loadNative: false);
      expect(await w.request<String>('hello'), 'x:hello');
      await expectLater(
        w.request<String>('boom'),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'm',
            contains('exploded'),
          ),
        ),
      );
      expect(await w.request<String>('again'), 'x:again');
      w.close();
      await expectLater(
        w.request<String>('late'),
        throwsA(isA<InferenceException>()),
      );
    });

    test('init failures surface from spawn', () async {
      await expectLater(
        SherpaWorker.spawn(_failingInit, null, loadNative: false),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'm',
            contains('bad model'),
          ),
        ),
      );
    });
  });
}
