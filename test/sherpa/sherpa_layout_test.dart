import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/inference/sherpa/sherpa_layout.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('sherpa_layout'));
  tearDown(() => root.deleteSync(recursive: true));

  Directory model(
    String name,
    List<String> files, {
    List<String> dirs = const [],
  }) {
    final dir = Directory(p.join(root.path, name))..createSync();
    for (final f in files) {
      File(p.join(dir.path, f)).writeAsBytesSync(const []);
    }
    for (final d in dirs) {
      Directory(p.join(dir.path, d)).createSync();
    }
    return dir;
  }

  SherpaAsrLayout asr(Directory d, {bool? streaming, bool preferInt8 = true}) =>
      SherpaModelLayout.detect(d, streaming: streaming, preferInt8: preferInt8)
          as SherpaAsrLayout;

  SherpaTtsLayout tts(Directory d) =>
      SherpaModelLayout.detect(d) as SherpaTtsLayout;

  group('ASR', () {
    test('whisper with int8 files and prefixed tokens', () {
      final l = asr(
        model('sherpa-onnx-whisper-tiny.en', [
          'tiny.en-encoder.int8.onnx',
          'tiny.en-encoder.onnx',
          'tiny.en-decoder.int8.onnx',
          'tiny.en-decoder.onnx',
          'tiny.en-tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.whisper);
      expect(
        p.basename(l.path(SherpaFileRole.encoder)),
        'tiny.en-encoder.int8.onnx',
      );
      expect(
        p.basename(l.path(SherpaFileRole.decoder)),
        'tiny.en-decoder.int8.onnx',
      );
      expect(p.basename(l.tokens), 'tiny.en-tokens.txt');
    });

    test('preferInt8 false picks full precision', () {
      final d = model('whisper-base', [
        'base-encoder.int8.onnx',
        'base-encoder.onnx',
        'base-decoder.int8.onnx',
        'base-decoder.onnx',
        'tokens.txt',
      ]);
      expect(
        p.basename(asr(d, preferInt8: false).path(SherpaFileRole.encoder)),
        'base-encoder.onnx',
      );
    });

    test('moonshine v1 with cached and uncached decoders', () {
      final l = asr(
        model('sherpa-onnx-moonshine-tiny-en-int8', [
          'preprocess.onnx',
          'encode.int8.onnx',
          'uncached_decode.int8.onnx',
          'cached_decode.int8.onnx',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.moonshine);
      expect(
        l.files.keys,
        containsAll([
          SherpaFileRole.preprocessor,
          SherpaFileRole.encoder,
          SherpaFileRole.uncachedDecoder,
          SherpaFileRole.cachedDecoder,
        ]),
      );
    });

    test('moonshine with a merged decoder', () {
      final l = asr(
        model('moonshine-base', [
          'preprocess.onnx',
          'encode.onnx',
          'merged_decode.onnx',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.moonshine);
      expect(l.files, contains(SherpaFileRole.mergedDecoder));
    });

    test('nemo parakeet transducer', () {
      final l = asr(
        model('sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8', [
          'encoder.int8.onnx',
          'decoder.int8.onnx',
          'joiner.int8.onnx',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.transducer);
      expect(l.files, contains(SherpaFileRole.joiner));
    });

    test('zipformer transducer', () {
      final l = asr(
        model('sherpa-onnx-zipformer-small-en-2023-06-26', [
          'encoder-epoch-99-avg-1.int8.onnx',
          'decoder-epoch-99-avg-1.int8.onnx',
          'joiner-epoch-99-avg-1.int8.onnx',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.transducer);
    });

    test('streaming zipformer keeps one chunk variant together', () {
      final l = asr(
        model('sherpa-onnx-streaming-zipformer-en-2023-06-26', [
          for (final role in ['encoder', 'decoder', 'joiner'])
            for (final chunk in ['left-128', 'left-64'])
              '$role-epoch-99-avg-1-chunk-16-$chunk.int8.onnx',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.streamingTransducer);
      expect(l.architecture.isStreaming, isTrue);
      for (final role in [
        SherpaFileRole.encoder,
        SherpaFileRole.decoder,
        SherpaFileRole.joiner,
      ]) {
        expect(l.path(role), contains('left-128'));
      }
    });

    test('streaming flag overrides the folder name', () {
      final d = model('my-model', [
        'encoder.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      ]);
      expect(asr(d).architecture, SherpaAsrArchitecture.transducer);
      expect(
        asr(d, streaming: true).architecture,
        SherpaAsrArchitecture.streamingTransducer,
      );
    });

    test('streaming is recognised from encoder metadata', () {
      final d = model('renamed', ['decoder.onnx', 'joiner.onnx', 'tokens.txt']);
      File(
        p.join(d.path, 'encoder.onnx'),
      ).writeAsStringSync('graph bytes...decode_chunk_len\x00 32');
      expect(asr(d).architecture, SherpaAsrArchitecture.streamingTransducer);
    });

    test('nemo ctc single model', () {
      final l = asr(
        model('sherpa-onnx-nemo-ctc-en-conformer-small', [
          'model.onnx',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.nemoCtc);
    });

    test('streaming nemo ctc', () {
      final l = asr(
        model('sherpa-onnx-streaming-nemo-ctc-en', [
          'model.onnx',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.streamingNemoCtc);
    });

    test('zipformer ctc', () {
      expect(
        asr(
          model('sherpa-onnx-zipformer-ctc-en', ['model.onnx', 'tokens.txt']),
        ).architecture,
        SherpaAsrArchitecture.zipformerCtc,
      );
      expect(
        asr(
          model('sherpa-onnx-streaming-zipformer-ctc-en', [
            'model.onnx',
            'tokens.txt',
          ]),
        ).architecture,
        SherpaAsrArchitecture.streamingZipformerCtc,
      );
    });

    test('sense voice', () {
      final l = asr(
        model('sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17', [
          'model.int8.onnx',
          'model.onnx',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaAsrArchitecture.senseVoice);
      expect(p.basename(l.path(SherpaFileRole.model)), 'model.int8.onnx');
    });

    test('paraformer offline and streaming', () {
      expect(
        asr(
          model('sherpa-onnx-paraformer-zh-2023-09-14', [
            'model.int8.onnx',
            'tokens.txt',
          ]),
        ).architecture,
        SherpaAsrArchitecture.paraformer,
      );
      expect(
        asr(
          model('sherpa-onnx-streaming-paraformer-bilingual-zh-en', [
            'encoder.int8.onnx',
            'decoder.int8.onnx',
            'tokens.txt',
          ]),
        ).architecture,
        SherpaAsrArchitecture.streamingParaformer,
      );
    });

    test('silero vad file is ignored', () {
      final l = asr(
        model('sherpa-onnx-sense-voice', [
          'model.onnx',
          'silero_vad.onnx',
          'tokens.txt',
        ]),
      );
      expect(p.basename(l.path(SherpaFileRole.model)), 'model.onnx');
    });
  });

  group('TTS', () {
    test('piper vits', () {
      final l = tts(
        model(
          'vits-piper-en_US-amy-low',
          ['en_US-amy-low.onnx', 'en_US-amy-low.onnx.json', 'tokens.txt'],
          dirs: ['espeak-ng-data'],
        ),
      );
      expect(l.architecture, SherpaTtsArchitecture.vits);
      expect(p.basename(l.model), 'en_US-amy-low.onnx');
      expect(p.basename(l.dataDir), 'espeak-ng-data');
    });

    test('melo vits with lexicon and fsts', () {
      final l = tts(
        model('vits-melo-tts-zh_en', [
          'model.onnx',
          'lexicon.txt',
          'tokens.txt',
          'date.fst',
          'number.fst',
        ]),
      );
      expect(l.architecture, SherpaTtsArchitecture.vits);
      expect(p.basename(l.lexicon), 'lexicon.txt');
      expect(l.ruleFsts.split(',').map(p.basename), ['date.fst', 'number.fst']);
    });

    test('kokoro multi language', () {
      final l = tts(
        model(
          'kokoro-multi-lang-v1_0',
          [
            'model.onnx',
            'voices.bin',
            'tokens.txt',
            'lexicon-us-en.txt',
            'lexicon-zh.txt',
          ],
          dirs: ['espeak-ng-data'],
        ),
      );
      expect(l.architecture, SherpaTtsArchitecture.kokoro);
      expect(p.basename(l.voices), 'voices.bin');
      expect(l.lexicon.split(','), hasLength(2));
    });

    test('kitten', () {
      final l = tts(
        model('kitten-nano-en-v0_1-fp16', [
          'model.fp16.onnx',
          'voices.bin',
          'tokens.txt',
        ]),
      );
      expect(l.architecture, SherpaTtsArchitecture.kitten);
    });

    test('matcha with and without vocoder', () {
      final without = tts(
        model('matcha-icefall-en_US-ljspeech', [
          'model-steps-3.onnx',
          'tokens.txt',
        ]),
      );
      expect(without.architecture, SherpaTtsArchitecture.matcha);
      expect(without.vocoder, isEmpty);
      final withVocoder = tts(
        model('matcha-zh', [
          'model-steps-3.onnx',
          'vocos-22khz-univ.onnx',
          'tokens.txt',
        ]),
      );
      expect(p.basename(withVocoder.vocoder), 'vocos-22khz-univ.onnx');
      expect(p.basename(withVocoder.model), 'model-steps-3.onnx');
    });
  });

  group('errors', () {
    test('missing directory', () {
      expect(
        () => SherpaModelLayout.detect(Directory(p.join(root.path, 'nope'))),
        throwsA(isA<InferenceException>()),
      );
    });

    test('missing tokens', () {
      expect(
        () => SherpaModelLayout.detect(model('no-tokens', ['model.onnx'])),
        throwsA(
          isA<InferenceException>().having(
            (e) => e.message,
            'message',
            contains('tokens.txt'),
          ),
        ),
      );
    });

    test('no onnx files', () {
      expect(
        () => SherpaModelLayout.detect(model('empty', ['tokens.txt'])),
        throwsA(isA<InferenceException>()),
      );
    });

    test('unsupported encoder/decoder pair', () {
      expect(
        () => SherpaModelLayout.detect(
          model('canary-180m', ['encoder.onnx', 'decoder.onnx', 'tokens.txt']),
        ),
        throwsA(isA<InferenceException>()),
      );
    });

    test('transducer missing joiner partner', () {
      expect(
        () => SherpaModelLayout.detect(
          model('half', ['joiner.onnx', 'tokens.txt']),
        ),
        throwsA(isA<InferenceException>()),
      );
    });
  });
}
