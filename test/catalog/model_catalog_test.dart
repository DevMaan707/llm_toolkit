import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/core/catalog/model_catalog.dart';
import 'package:llm_toolkit/src/core/model_info.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  test('tasks with a verified mobile model have entries', () {
    for (final task in ModelTask.values.where(
      (t) => t != ModelTask.videoGeneration,
    )) {
      expect(ModelCatalog.forTask(task), isNotEmpty, reason: task.name);
    }
    expect(ModelCatalog.forTask(ModelTask.videoGeneration), isEmpty);
  });

  test('entries are well formed', () {
    for (final m in ModelCatalog.all) {
      expect(m.repoId, matches(r'^[\w.-]+/[\w.-]+$'));
      expect(m.sizeBytes, greaterThan(0));
      expect(m.minRamBytes, greaterThan(0));
      expect(m.files.toSet(), hasLength(m.files.length));
    }
  });

  test('runtime agrees with what the task can run', () {
    for (final m in ModelCatalog.all.where((m) => m.isRunnable)) {
      final formats = {
        for (final f in m.files)
          if (ModelFormat.fromFilename(f) case final format?) format,
      };
      if (m.files.isEmpty) continue;
      expect(
        formats.any(m.task.runnableFormats.contains),
        isTrue,
        reason: '${m.repoId} ${m.files}',
      );
    }
    for (final m in ModelCatalog.forTask(ModelTask.imageGeneration)) {
      expect(m.isRunnable, isFalse);
    }
  });

  test('only sherpa entries are bundles', () {
    final bundles = ModelCatalog.all.where((m) => m.isBundle);
    expect(bundles, isNotEmpty);
    expect(
      bundles.every(
        (m) =>
            m.task == ModelTask.speechToText ||
            m.task == ModelTask.textToSpeech,
      ),
      isTrue,
    );
    expect(
      ModelCatalog.find('litert-community/whisper-tiny')!.isBundle,
      isFalse,
    );
  });

  group('forDevice', () {
    test('filters by memory and orders largest first', () {
      final small = ModelCatalog.forDevice(ModelTask.textGeneration, 2 * gb);
      expect(small.every((m) => m.minRamBytes <= 2 * gb), isTrue);
      expect(small.every((m) => m.isRunnable), isTrue);
      final sizes = [for (final m in small) m.sizeBytes];
      expect(sizes, [...sizes]..sort((a, b) => b.compareTo(a)));

      final big = ModelCatalog.forDevice(ModelTask.textGeneration, 8 * gb);
      expect(big.length, greaterThan(small.length));
    });

    test('nothing fits tiny memory', () {
      expect(ModelCatalog.forDevice(ModelTask.textGeneration, 1024), isEmpty);
    });

    test('image generation is empty unless non-runnable are included', () {
      expect(
        ModelCatalog.forDevice(ModelTask.imageGeneration, 16 * gb),
        isEmpty,
      );
      expect(
        ModelCatalog.forDevice(
          ModelTask.imageGeneration,
          16 * gb,
          runnableOnly: false,
        ),
        hasLength(2),
      );
    });
  });

  test('find matches repo and file', () {
    expect(
      ModelCatalog.find(
        'litert-community/whisper-tiny',
        file: 'whisper_tiny_30s_f32.tflite',
      )!.name,
      contains('float32'),
    );
    expect(ModelCatalog.find('nope/none'), isNull);
  });
}
