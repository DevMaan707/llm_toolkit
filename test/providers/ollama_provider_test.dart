import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/model_info.dart';
import 'package:llm_toolkit/src/core/providers/ollama/ollama_provider.dart';
import 'package:llm_toolkit/src/core/search_query.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

import 'fake_adapter.dart';

void main() {
  late FakeAdapter adapter;
  late OllamaProvider provider;

  void make(FakeHandler handler) {
    adapter = FakeAdapter(handler);
    provider = OllamaProvider(
      baseUrl: 'http://ollama.test:1234',
      dio: FakeAdapter.dio(adapter),
    );
  }

  test('lists, filters and parses installed models', () async {
    make(
      (o) => FakeAdapter.json({
        'models': [
          {
            'name': 'llama3.2:1b',
            'size': 1300000000,
            'modified_at': '2026-01-02T03:04:05Z',
            'details': {
              'family': 'llama',
              'parameter_size': '1.2B',
              'quantization_level': 'Q8_0',
            },
          },
          {
            'name': 'qwen2.5:7b',
            'size': 4700000000,
            'details': {'parameter_size': '7.6B'},
          },
        ],
      }),
    );
    final all = await provider.searchModels(const SearchQuery());
    expect(
      adapter.requests.single.uri.toString(),
      'http://ollama.test:1234/api/tags',
    );
    expect(all.map((m) => m.id), ['llama3.2:1b', 'qwen2.5:7b']);
    expect(all.first.quantization, 'Q8_0');
    expect(all.first.parameterCount, 1200000000);
    expect(all.first.sizeBytes, 1300000000);
    expect(all.first.totalSizeBytes, 1300000000);

    final small = await provider.searchModels(
      const SearchQuery(text: 'QWEN', maxSizeBytes: 5000000000),
    );
    expect(small.single.id, 'qwen2.5:7b');
    expect(
      await provider.searchModels(
        const SearchQuery(formats: {ModelFormat.onnx}),
      ),
      isEmpty,
    );
  });

  test('show returns details', () async {
    make((o) {
      expect(
        jsonDecode(o.data is String ? o.data as String : jsonEncode(o.data)),
        {'model': 'm:1'},
      );
      return FakeAdapter.json({
        'license': 'Apache License\nVersion 2.0',
        'details': {
          'family': 'llama',
          'parameter_size': '8.0B',
          'quantization_level': 'Q4_0',
        },
        'model_info': {
          'general.parameter_count': 8030261248,
          'llama.context_length': 131072,
        },
      });
    });
    final m = await provider.getModelDetails('m:1');
    expect(m.license, 'Apache License');
    expect(m.parameterCount, 8030261248);
    expect(m.contextLength, 131072);
    expect(m.quantization, 'Q4_0');
  });

  test(
    'unreachable and missing models map to ModelProviderException',
    () async {
      make((o) => FakeAdapter.json({'error': 'nope'}, status: 404));
      await expectLater(
        provider.getModelDetails('x'),
        throwsA(
          isA<ModelProviderException>().having(
            (e) => e.message,
            'm',
            contains('not installed'),
          ),
        ),
      );
    },
  );

  test('pull streams progress across layers', () async {
    make((o) {
      final lines = [
        {'status': 'pulling manifest'},
        {'status': 'pulling a', 'digest': 'a', 'total': 100, 'completed': 50},
        {'status': 'pulling b', 'digest': 'b', 'total': 100, 'completed': 0},
        {'status': 'pulling a', 'digest': 'a', 'total': 100, 'completed': 100},
        {'status': 'pulling b', 'digest': 'b', 'total': 100, 'completed': 100},
        {'status': 'success'},
      ].map(jsonEncode).join('\n');
      return FakeAdapter.text('$lines\n');
    });
    final fractions = <double>[];
    final path = await provider.downloadModel(
      'm:1',
      '',
      onProgress: fractions.add,
    );
    expect(path, 'm:1');
    expect(fractions.last, 1.0);
    expect(fractions, contains(0.25));
  });

  test('pull errors surface', () async {
    make(
      (o) => FakeAdapter.text(
        '${jsonEncode({'error': 'pull model manifest: file does not exist'})}\n',
      ),
    );
    await expectLater(
      provider.downloadModel('nope', ''),
      throwsA(
        isA<ModelProviderException>().having(
          (e) => e.message,
          'm',
          contains('does not exist'),
        ),
      ),
    );
  });
}
