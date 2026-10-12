import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/model_info.dart';
import 'package:llm_toolkit/src/core/providers/huggingface/hf_parser.dart';
import 'package:llm_toolkit/src/core/providers/huggingface/hf_provider.dart';
import 'package:llm_toolkit/src/core/search_query.dart';

import 'fake_adapter.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/providers/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

ModelInfo _parse(String name) =>
    HfParser.model(_fixture(name), endpoint: 'https://huggingface.co');

void main() {
  group('ModelTask', () {
    test('maps Hub pipeline tags', () {
      expect(
        ModelTask.fromPipelineTag('automatic-speech-recognition'),
        ModelTask.speechToText,
      );
      expect(
        ModelTask.fromPipelineTag('text-to-speech'),
        ModelTask.textToSpeech,
      );
      expect(
        ModelTask.fromPipelineTag('text-to-image'),
        ModelTask.imageGeneration,
      );
      expect(
        ModelTask.fromPipelineTag('text-to-video'),
        ModelTask.videoGeneration,
      );
      expect(
        ModelTask.fromPipelineTag('feature-extraction'),
        ModelTask.embedding,
      );
      expect(
        ModelTask.fromPipelineTag('sentence-similarity'),
        ModelTask.embedding,
      );
      expect(ModelTask.fromPipelineTag('image-text-to-text'), ModelTask.vision);
      expect(
        ModelTask.fromPipelineTag('text2text-generation'),
        ModelTask.textGeneration,
      );
      expect(ModelTask.fromPipelineTag('fill-mask'), isNull);
      expect(ModelTask.fromPipelineTag(null), isNull);
    });

    test('format hub tags', () {
      expect(ModelFormat.litert.hubTag, 'litert');
      expect(ModelFormat.tflite.hubTag, 'tflite');
      expect(ModelFormat.fromFilename('x.litert'), ModelFormat.litert);
      expect(ModelFormat.litert.isRunnable, isFalse);
    });
  });

  group('runnableBy (real Hub responses)', () {
    test('Whisper TFLite runs on the ASR engine', () {
      final m = _parse('whisper_tiny_model.json');
      expect(m.task, ModelTask.speechToText);
      expect(m.runnableBy, EngineIds.asr);
      expect(m.bundle, isNull);
    });

    test('sherpa folder is detected from its files', () {
      final m = _parse('moonshine_model.json');
      expect(m.pipelineTag, isNull);
      expect(m.bundle, ModelBundle.sherpaOnnx);
      expect(
        m.copyWith(files: m.files).bundle,
        ModelBundle.sherpaOnnx,
        reason: 'copyWith keeps the bundle',
      );
    });

    ModelInfo info(
      String id,
      String? pipeline,
      List<String> files, {
      ModelBundle? bundle,
    }) => ModelInfo(
      id: id,
      name: id,
      provider: 'huggingface',
      pipelineTag: pipeline,
      bundle: bundle,
      files: [
        for (final f in files) ModelFile(filename: f, downloadUrl: 'u/$f'),
      ],
    );

    test('per task rules', () {
      expect(
        info('a/m', 'text-generation', ['m.gguf']).runnableBy,
        EngineIds.llama,
      );
      expect(
        info('a/m', 'text-generation', ['m.litertlm']).runnableBy,
        EngineIds.litert,
      );
      expect(
        info('a/m', 'image-text-to-text', ['m.task']).runnableBy,
        EngineIds.litert,
      );
      expect(
        info('a/m', 'feature-extraction', ['m.gguf']).runnableBy,
        EngineIds.llama,
      );
      expect(
        info('a/m', 'feature-extraction', ['m.tflite']).runnableBy,
        isNull,
      );
      expect(info('a/m', null, ['m.gguf']).runnableBy, EngineIds.llama);
      expect(
        info('a/m', 'text-generation', ['m.safetensors']).runnableBy,
        isNull,
      );
    });

    test('speech models', () {
      expect(
        info('o/whisper-tiny', 'automatic-speech-recognition', [
          'a.tflite',
        ]).runnableBy,
        EngineIds.asr,
      );
      expect(
        info('l/moonshine-tiny', 'automatic-speech-recognition', [
          'a.tflite',
        ]).runnableBy,
        isNull,
      );
      expect(
        info('x/whisper', 'automatic-speech-recognition', [
          'm.onnx',
        ]).runnableBy,
        isNull,
        reason: 'plain ONNX without a sherpa layout',
      );
      expect(
        info('x/s', 'automatic-speech-recognition', [
          'm.onnx',
        ], bundle: ModelBundle.sherpaOnnx).runnableBy,
        EngineIds.sherpaAsr,
      );
      expect(
        info('x/k', 'text-to-speech', [
          'm.onnx',
        ], bundle: ModelBundle.sherpaOnnx).runnableBy,
        EngineIds.sherpaTts,
      );
      expect(info('x/k', 'text-to-speech', ['m.onnx']).runnableBy, isNull);
    });

    test('image and video generation are never runnable', () {
      expect(info('a/z', 'text-to-image', ['z.tflite']).runnableBy, isNull);
      expect(info('a/v', 'text-to-video', ['v.onnx']).runnableBy, isNull);
    });

    test('an explicit runtime wins', () {
      const m = ModelInfo(
        id: 'llama3',
        name: 'llama3',
        provider: 'ollama',
        runtime: EngineIds.ollama,
      );
      expect(m.runnableBy, EngineIds.ollama);
    });
  });

  group('HuggingFaceProvider task search', () {
    late FakeAdapter adapter;
    late HuggingFaceProvider provider;

    HuggingFaceProvider make(Map<String, dynamic> Function(String tag) item) {
      adapter = FakeAdapter(
        (o) => FakeAdapter.json([
          item(o.uri.queryParameters['pipeline_tag'] ?? ''),
        ]),
      );
      return provider = HuggingFaceProvider(dio: FakeAdapter.dio(adapter));
    }

    Map<String, dynamic> whisper(String _) =>
        _fixture('whisper_tiny_model.json');

    test(
      'tasks become pipeline_tag and runnable formats become filters',
      () async {
        make(whisper);
        final results = await provider.searchModels(
          const SearchQuery(
            tasks: {ModelTask.speechToText},
            includeFileSizes: false,
          ),
        );
        final queries =
            adapter.requests.map((r) => r.uri.queryParametersAll).toList();
        expect(queries, hasLength(2));
        expect(queries.expand((q) => q['pipeline_tag']!).toSet(), {
          'automatic-speech-recognition',
        });
        expect(queries.expand((q) => q['filter']!).toSet(), {'tflite', 'onnx'});
        expect(results.map((m) => m.id), ['litert-community/whisper-tiny']);
      },
    );

    test('explicit formats override the implicit ones', () async {
      make(whisper);
      await provider.searchModels(
        const SearchQuery(
          tasks: {ModelTask.speechToText},
          formats: {ModelFormat.litert},
          includeFileSizes: false,
          onlyRunnable: false,
        ),
      );
      expect(adapter.requests.single.uri.queryParameters['filter'], 'litert');
    });

    test('formats map to the Hub tags', () async {
      make(whisper);
      await provider.searchModels(
        const SearchQuery(
          formats: {ModelFormat.gguf, ModelFormat.onnx, ModelFormat.tflite},
          includeFileSizes: false,
          onlyRunnable: false,
        ),
      );
      expect(
        adapter.requests.map((r) => r.uri.queryParameters['filter']).toSet(),
        {'gguf', 'onnx', 'tflite'},
      );
    });

    test('runnable-only image search needs no request', () async {
      make(whisper);
      final results = await provider.searchModels(
        const SearchQuery(tasks: {ModelTask.imageGeneration}),
      );
      expect(results, isEmpty);
      expect(adapter.requests, isEmpty);
    });

    test('image search with onlyRunnable: false returns the models', () async {
      make(
        (_) => {
          'id': 'litert-community/Z-Image-Turbo-LiteRT',
          'pipeline_tag': 'text-to-image',
          'tags': ['litert'],
          'siblings': [
            {'rfilename': 'zc_main0.tflite', 'size': 908480960},
          ],
        },
      );
      final results = await provider.searchModels(
        const SearchQuery(
          tasks: {ModelTask.imageGeneration},
          onlyRunnable: false,
          includeFileSizes: false,
        ),
      );
      expect(
        adapter.requests.single.uri.queryParameters['pipeline_tag'],
        'text-to-image',
      );
      expect(results.single.task, ModelTask.imageGeneration);
      expect(results.single.runnableBy, isNull);
    });

    test('onlyRunnable drops non-Whisper tflite ASR models', () async {
      make(
        (_) => {
          'id': 'litert-community/moonshine-tiny',
          'pipeline_tag': 'automatic-speech-recognition',
          'siblings': [
            {'rfilename': 'moonshine_tiny_5s_i8.tflite'},
          ],
        },
      );
      const base = SearchQuery(
        tasks: {ModelTask.speechToText},
        includeFileSizes: false,
      );
      expect(await provider.searchModels(base), isEmpty);
      final all = await provider.searchModels(
        const SearchQuery(
          tasks: {ModelTask.speechToText},
          includeFileSizes: false,
          onlyRunnable: false,
        ),
      );
      expect(all, hasLength(1));
    });
  });
}
