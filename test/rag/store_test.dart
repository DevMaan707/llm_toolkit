import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/exceptions/llm_toolkit_exceptions.dart';
import 'package:llm_toolkit/src/rag/rag.dart';

VectorRecord rec(String id, List<double> v, {Map<String, Object?>? meta}) =>
    VectorRecord(id: id, embedding: v, text: 'text $id', metadata: meta ?? {});

void sharedStoreTests(Future<VectorStore> Function() make) {
  test('upsert, query ordering, topK and minScore', () async {
    final s = await make();
    await s.upsert([
      rec('a', [1, 0]),
      rec('b', [1, 1]),
      rec('c', [0, 1]),
    ]);
    final r = await s.query([1, 0.1], topK: 2);
    expect(r.map((e) => e.record.id), ['a', 'b']);
    expect(r.first.score, greaterThan(r.last.score));
    final strict = await s.query([1, 0], minScore: 0.9);
    expect(strict.map((e) => e.record.id), ['a']);
    expect(await s.count(), 3);
  });

  test('upsert replaces by id', () async {
    final s = await make();
    await s.upsert([
      rec('a', [1, 0]),
    ]);
    await s.upsert([
      rec('a', [0, 1]),
    ]);
    expect(await s.count(), 1);
    expect((await s.query([0, 1])).single.score, closeTo(1, 1e-6));
  });

  test('metadata filter on query, delete by id and filter', () async {
    final s = await make();
    await s.upsert([
      rec('a', [1, 0], meta: {'src': 'x'}),
      rec('b', [1, 0.1], meta: {'src': 'y'}),
      rec('c', [1, 0.2], meta: {'src': 'y'}),
    ]);
    expect((await s.query([1, 0], filter: {'src': 'y'})).length, 2);
    expect(
      await s.count(
        filter: {
          'src': ['x', 'y'],
        },
      ),
      3,
    );
    expect(await s.delete(filter: {'src': 'y'}), 2);
    expect(await s.delete(ids: ['a', 'missing']), 1);
    expect(await s.count(), 0);
  });

  test('dimension mismatch throws VectorStorageException', () async {
    final s = await make();
    await s.upsert([
      rec('a', [1, 0]),
    ]);
    expect(
      () => s.upsert([
        rec('b', [1, 0, 0]),
      ]),
      throwsA(isA<VectorStorageException>()),
    );
    expect(() => s.query([1, 0, 0]), throwsA(isA<VectorStorageException>()));
  });

  test('clear empties and allows new dimension', () async {
    final s = await make();
    await s.upsert([
      rec('a', [1, 0]),
    ]);
    await s.clear();
    await s.upsert([
      rec('b', [1, 0, 0]),
    ]);
    expect(await s.count(), 1);
  });
}

void main() {
  group('InMemoryVectorStore', () {
    sharedStoreTests(() async => InMemoryVectorStore());

    test('isolate search matches inline search', () async {
      final inline = InMemoryVectorStore();
      final iso = InMemoryVectorStore(isolateThreshold: 1);
      final records = [
        for (var i = 0; i < 50; i++) rec('r$i', [i + 1.0, 50.0 - i, 3]),
      ];
      await inline.upsert(records);
      await iso.upsert(records);
      final a = await inline.query([1, 2, 3], topK: 5);
      final b = await iso.query([1, 2, 3], topK: 5);
      expect(b.map((e) => e.record.id), a.map((e) => e.record.id));
    });
  });

  group('FileVectorStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rag_store_'));
    tearDown(() => dir.deleteSync(recursive: true));

    sharedStoreTests(() async {
      final d = Directory.systemTemp.createTempSync('rag_shared_');
      addTearDown(() => d.deleteSync(recursive: true));
      return FileVectorStore(d);
    });

    test('survives restart and keeps text, metadata and vectors', () async {
      final first = FileVectorStore(dir);
      await first.upsert([
        rec('a', [1, 0, 0], meta: {'n': 1, 's': 'x'}),
        rec('b', [0, 1, 0]),
      ]);
      await first.close();

      final second = FileVectorStore(dir);
      expect(await second.count(), 2);
      final r = await second.query([1, 0, 0], topK: 1);
      expect(r.single.record.id, 'a');
      expect(r.single.record.text, 'text a');
      expect(r.single.record.metadata, {'n': 1, 's': 'x'});
      expect(r.single.score, closeTo(1, 1e-6));
    });

    test('persists deletes and leaves no temp file', () async {
      final s = FileVectorStore(dir);
      await s.upsert([
        rec('a', [1, 0]),
        rec('b', [0, 1]),
      ]);
      await s.delete(ids: ['a']);
      await s.close();
      expect(File('${dir.path}/vectors.jsonl.tmp').existsSync(), isFalse);
      expect(await FileVectorStore(dir).count(), 1);
    });

    test('dimension mismatch against persisted data is clear', () async {
      final s = FileVectorStore(dir);
      await s.upsert([
        rec('a', [1, 0]),
      ]);
      await s.close();
      final reopened = FileVectorStore(dir);
      expect(
        () => reopened.upsert([
          rec('b', [1, 0, 0]),
        ]),
        throwsA(
          isA<VectorStorageException>().having(
            (e) => e.message,
            'message',
            contains('dimension mismatch'),
          ),
        ),
      );
    });

    test('corrupt file raises VectorStorageException', () async {
      File('${dir.path}/vectors.jsonl').writeAsStringSync('not json\n');
      expect(
        () => FileVectorStore(dir).count(),
        throwsA(isA<VectorStorageException>()),
      );
    });
  });
}
