import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/model_info.dart';
import 'package:llm_toolkit/src/core/providers/local/local_provider.dart';
import 'package:llm_toolkit/src/core/search_query.dart';
import 'package:llm_toolkit/src/core/storage/model_store.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';

Future<File> _write(String path, int size) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsBytes(List.filled(size, 1));
  return f;
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('store_test'));
  tearDown(() => tmp.delete(recursive: true));

  group('LocalProvider', () {
    test('finds supported model files recursively', () async {
      await _write('${tmp.path}/gemma-3-1b-it-Q4_K_M.gguf', 100);
      await _write('${tmp.path}/nested/whisper-tiny.tflite', 50);
      await _write('${tmp.path}/nested/gemma.litertlm', 70);
      await _write('${tmp.path}/notes.txt', 5);
      await _write('${tmp.path}/big.gguf.part', 5);

      final provider = LocalProvider([tmp, Directory('${tmp.path}/absent')]);
      final models = await provider.scan();
      expect(models.map((m) => m.name), [
        'gemma-3-1b-it-Q4_K_M.gguf',
        'gemma.litertlm',
        'whisper-tiny.tflite',
      ]);

      final gguf = models.first;
      expect(gguf.provider, 'local');
      expect(gguf.quantization, 'Q4_K_M');
      expect(gguf.parameterCount, 1000000000);
      expect(gguf.library, 'llama');
      expect(gguf.sizeBytes, 100);
      expect(models.last.library, 'asr');
    });

    test('search filters by text, format and size', () async {
      await _write('${tmp.path}/a-q4.gguf', 100);
      await _write('${tmp.path}/b.onnx', 10);
      final provider = LocalProvider([tmp], recursive: false);
      expect(
        (await provider.searchModels(
          const SearchQuery(text: 'A-'),
        )).single.name,
        'a-q4.gguf',
      );
      expect(
        (await provider.searchModels(
          const SearchQuery(formats: {ModelFormat.onnx}),
        )).single.name,
        'b.onnx',
      );
      expect(
        (await provider.searchModels(
          const SearchQuery(maxSizeBytes: 50),
        )).single.name,
        'b.onnx',
      );
    });

    test('details and download return the path', () async {
      final f = await _write('${tmp.path}/m.gguf', 3);
      final provider = LocalProvider([tmp]);
      expect(await provider.downloadModel(f.path, ''), f.path);
      await expectLater(
        provider.getModelDetails('${tmp.path}/none.gguf'),
        throwsA(isA<ModelProviderException>()),
      );
    });
  });

  group('ModelStore', () {
    late ModelStore store;
    setUp(() => store = ModelStore(Directory('${tmp.path}/models')));

    test('pathFor namespaces by model and rejects traversal', () {
      expect(
        store.pathFor('owner/repo', 'x.gguf'),
        '${tmp.path}/models/owner__repo/x.gguf',
      );
      expect(
        store.pathFor('owner/repo', 'sub/x.gguf'),
        endsWith('owner__repo/sub/x.gguf'),
      );
      expect(
        () => store.pathFor('o/r', '../../evil.gguf'),
        throwsArgumentError,
      );
      expect(() => store.pathFor('o/r', '/etc/passwd'), throwsArgumentError);
    });

    test('lists, sizes, tracks usage and deletes', () async {
      final a = await _write(store.pathFor('o/a', 'a.gguf'), 100);
      final b = await _write(store.pathFor('o/b', 'b.gguf'), 200);
      await _write('${b.path}.part', 40);
      expect(await store.contains('o/a', 'a.gguf'), isTrue);

      await store.markUsed(a.path, at: DateTime(2030));
      final listed = await store.list();
      expect(listed.map((m) => m.filename), ['a.gguf', 'b.gguf']);
      expect(listed.first.lastUsed, DateTime(2030));
      expect(listed.first.format, ModelFormat.gguf);
      expect(await store.totalSize(), greaterThanOrEqualTo(340));

      expect(await store.delete(b.path), isTrue);
      expect(await store.delete(b.path), isFalse);
      expect(await store.clearPartials(), 1);
      expect(await store.delete(a.path), isTrue);
      expect(Directory(a.parent.path).existsSync(), isFalse);
      await expectLater(
        store.delete('${tmp.path}/outside.gguf'),
        throwsA(isA<ModelProviderException>()),
      );
    });

    test('trimTo evicts least recently used first', () async {
      final a = await _write(store.pathFor('o/a', 'a.gguf'), 100);
      final b = await _write(store.pathFor('o/b', 'b.gguf'), 100);
      final c = await _write(store.pathFor('o/c', 'c.gguf'), 100);
      await store.markUsed(a.path, at: DateTime(2020));
      await store.markUsed(b.path, at: DateTime(2022));
      await store.markUsed(c.path, at: DateTime(2024));
      final removed = await store.trimTo(150);
      expect(removed, [a.path, b.path]);
      expect((await store.list()).single.filename, 'c.gguf');
    });

    test('clearPartials removes leftovers', () async {
      await _write('${store.pathFor('o/a', 'a.gguf')}.part', 5);
      expect(await store.clearPartials(), 1);
      expect(await store.list(), isEmpty);
    });

    test('empty store', () async {
      expect(await store.list(), isEmpty);
      expect(await store.totalSize(), 0);
    });
  });
}
