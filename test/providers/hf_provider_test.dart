import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/model_info.dart';
import 'package:llm_toolkit/src/core/providers/huggingface/hf_provider.dart';
import 'package:llm_toolkit/src/core/search_query.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

import 'fake_adapter.dart';

const _sha = 'e6bb6b4ac3fbfbcc6babf3f18ec1d93b7aa34e2f2e9325c6029b8f216da64e22';

Map<String, dynamic> _listItem(
  String id,
  int downloads, {
  Object gated = false,
}) => {
  'id': id,
  'author': id.split('/').first,
  'downloads': downloads,
  'likes': 10,
  'gated': gated,
  'lastModified': '2026-08-24T02:45:24.000Z',
  'pipeline_tag': 'text-generation',
  'library_name': 'gguf',
  'tags': ['gguf', 'license:apache-2.0'],
  'cardData': {'license': 'apache-2.0'},
  'gguf': {'total': 1000000000, 'context_length': 32768},
  'siblings': [
    {'rfilename': 'README.md'},
    {'rfilename': 'm-Q4_K_M.gguf'},
    {'rfilename': 'dir/m-Q8_0.gguf'},
  ],
};

Map<String, dynamic> _detail(String id, int downloads) => {
  ..._listItem(id, downloads),
  'siblings': [
    {'rfilename': 'README.md', 'size': 10},
    {
      'rfilename': 'm-Q4_K_M.gguf',
      'size': 700,
      'lfs': {'sha256': _sha, 'size': 700},
    },
    {
      'rfilename': 'dir/m-Q8_0.gguf',
      'size': 2000,
      'lfs': {'sha256': 'ab', 'size': 2000},
    },
  ],
};

void main() {
  late FakeAdapter adapter;
  late HuggingFaceProvider provider;

  HuggingFaceProvider make(FakeHandler handler, {String? apiKey}) {
    adapter = FakeAdapter(handler);
    return provider = HuggingFaceProvider(
      dio: FakeAdapter.dio(adapter),
      apiKey: apiKey,
      detailConcurrency: 2,
    );
  }

  ResponseBody hub(RequestOptions o) {
    final path = o.uri.path;
    if (path == '/api/models') {
      return FakeAdapter.json([_listItem('a/one', 50), _listItem('b/two', 90)]);
    }
    final id = path.replaceFirst('/api/models/', '');
    return FakeAdapter.json(_detail(id, id == 'a/one' ? 50 : 90));
  }

  test(
    'search issues one list request plus one detail request per model',
    () async {
      make(hub, apiKey: 'tok');
      final results = await provider.searchModels(
        const SearchQuery(
          text: 'gemma',
          formats: {ModelFormat.gguf},
          pipelineTags: {PipelineTags.textGeneration},
          sort: ModelSort.likes,
          limit: 5,
        ),
      );

      expect(adapter.requests, hasLength(3));
      final list = adapter.requests.first.uri;
      expect(list.path, '/api/models');
      expect(list.queryParametersAll['search'], ['gemma']);
      expect(list.queryParametersAll['filter'], ['gguf']);
      expect(list.queryParametersAll['pipeline_tag'], ['text-generation']);
      expect(list.queryParametersAll['sort'], ['likes']);
      expect(list.queryParametersAll['direction'], ['-1']);
      expect(list.queryParametersAll['limit'], ['5']);
      expect(list.queryParametersAll['expand[]'], contains('siblings'));
      expect(adapter.requests.first.headers['Authorization'], 'Bearer tok');
      expect(
        adapter.requests
            .skip(1)
            .every((r) => r.uri.queryParameters['blobs'] == 'true'),
        isTrue,
      );

      expect(results.map((m) => m.id), ['a/one', 'b/two']);
    },
  );

  test('parses model metadata and file details', () async {
    make(hub);
    final m = (await provider.searchModels(const SearchQuery())).first;
    expect(m.provider, 'huggingface');
    expect(m.author, 'a');
    expect(m.downloads, 50);
    expect(m.likes, 10);
    expect(m.pipelineTag, 'text-generation');
    expect(m.library, 'gguf');
    expect(m.license, 'apache-2.0');
    expect(m.gated, isFalse);
    expect(m.lastModified, DateTime.utc(2026, 8, 24, 2, 45, 24));
    expect(m.parameterCount, 1000000000);
    expect(m.contextLength, 32768);
    expect(m.files.map((f) => f.filename), [
      'm-Q4_K_M.gguf',
      'dir/m-Q8_0.gguf',
    ]);
    final f = m.files.first;
    expect(f.sizeBytes, 700);
    expect(f.sha256, _sha);
    expect(f.quantization, 'Q4_K_M');
    expect(
      f.downloadUrl,
      'https://huggingface.co/a/one/resolve/main/m-Q4_K_M.gguf',
    );
    expect(m.files.last.downloadUrl, endsWith('/resolve/main/dir/m-Q8_0.gguf'));
  });

  test('skips detail requests when sizes are not wanted', () async {
    make(hub);
    final results = await provider.searchModels(
      const SearchQuery(includeFileSizes: false),
    );
    expect(adapter.requests, hasLength(1));
    expect(results.first.files.first.sizeBytes, isNull);
  });

  test('maxSizeBytes removes large files and empty models', () async {
    make(hub);
    final results = await provider.searchModels(
      const SearchQuery(maxSizeBytes: 1000),
    );
    expect(results, hasLength(2));
    expect(results.first.files.map((f) => f.filename), ['m-Q4_K_M.gguf']);
    expect(
      await provider.searchModels(const SearchQuery(maxSizeBytes: 100)),
      isEmpty,
    );
  });

  test('multiple formats are merged, de-duplicated and sorted', () async {
    make((o) {
      if (o.uri.path == '/api/models') {
        final tag = o.uri.queryParameters['filter'];
        return FakeAdapter.json(
          tag == 'gguf'
              ? [_listItem('a/one', 50), _listItem('c/shared', 70)]
              : [_listItem('c/shared', 70), _listItem('d/four', 99)],
        );
      }
      return hub(o);
    });
    final results = await provider.searchModels(
      const SearchQuery(
        formats: {ModelFormat.gguf, ModelFormat.onnx},
        includeFileSizes: false,
      ),
    );
    expect(results.map((m) => m.id), ['d/four', 'c/shared', 'a/one']);
  });

  test('onlyRunnable drops models without runnable files', () async {
    make(
      (o) => FakeAdapter.json([
        {
          ..._listItem('a/st', 1),
          'siblings': [
            {'rfilename': 'x.safetensors'},
          ],
        },
        _listItem('a/ok', 2),
      ]),
    );
    final results = await provider.searchModels(
      const SearchQuery(includeFileSizes: false),
    );
    expect(results.map((m) => m.id), ['a/ok']);
  });

  test('detail failures keep the model without sizes', () async {
    make(
      (o) =>
          o.uri.path == '/api/models'
              ? FakeAdapter.json([_listItem('a/one', 1)])
              : FakeAdapter.json({'error': 'x'}, status: 500),
    );
    final results = await provider.searchModels(const SearchQuery());
    expect(results.single.files.first.sizeBytes, isNull);
  });

  test('gated flag is read from "manual" and "auto"', () async {
    make((o) => FakeAdapter.json(_listItem('g/m', 1, gated: 'manual')));
    expect((await provider.getModelDetails('g/m')).gated, isTrue);
  });

  group('error mapping', () {
    Future<ModelProviderException> fail(
      int status, {
      Map<String, List<String>>? headers,
    }) async {
      make(
        (o) =>
            FakeAdapter.json({'error': 'x'}, status: status, headers: headers),
      );
      try {
        await provider.getModelDetails('a/b');
      } on ModelProviderException catch (e) {
        return e;
      }
      throw StateError('expected failure');
    }

    test(
      '401',
      () async => expect((await fail(401)).message, contains('token')),
    );
    test(
      '403',
      () async => expect((await fail(403)).message, contains('gated')),
    );
    test(
      '404',
      () async =>
          expect((await fail(404)).message, contains('"a/b" not found')),
    );
    test('429', () async {
      final e = await fail(
        429,
        headers: {
          'retry-after': ['30'],
        },
      );
      expect(e.message, contains('rate limit'));
      expect(e.message, contains('30'));
    });
    test('5xx', () async => expect((await fail(503)).message, contains('503')));

    test('invalid JSON', () async {
      make((o) => FakeAdapter.text('<html>'));
      expect(
        provider.searchModels(const SearchQuery()),
        throwsA(isA<ModelProviderException>()),
      );
    });

    test('non-list search payload', () async {
      make((o) => FakeAdapter.json({'a': 1}));
      expect(
        provider.searchModels(const SearchQuery()),
        throwsA(isA<ModelProviderException>()),
      );
    });
  });
}
