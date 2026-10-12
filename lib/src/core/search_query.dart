import 'model_info.dart';

/// Result ordering supported by the Hugging Face Hub.
enum ModelSort {
  downloads('downloads'),
  likes('likes'),
  lastModified('lastModified'),
  createdAt('createdAt'),
  trending('trendingScore');

  const ModelSort(this.apiValue);

  /// Value of the Hub's `sort` query parameter.
  final String apiValue;
}

/// Common Hub `pipeline_tag` values.
abstract final class PipelineTags {
  static const textGeneration = 'text-generation';
  static const imageTextToText = 'image-text-to-text';
  static const featureExtraction = 'feature-extraction';
  static const speechRecognition = 'automatic-speech-recognition';
  static const textToSpeech = 'text-to-speech';
}

/// Parameters of a model search.
class SearchQuery {
  final String text;

  /// Only models that ship one of these formats; empty means any.
  final Set<ModelFormat> formats;

  /// Tasks to search for (Hub `pipeline_tag`); a model matches any of them.
  final Set<ModelTask> tasks;

  /// Extra raw Hub `pipeline_tag` values searched in addition to [tasks].
  final Set<String> pipelineTags;

  /// Hub library tag such as `transformers`.
  final String? library;
  final String? author;

  /// Drops files larger than this and models left without files.
  final int? maxSizeBytes;
  final int? minDownloads;
  final int limit;
  final ModelSort sort;
  final bool descending;

  /// Keep only models some built-in engine can run (`ModelInfo.runnableBy`).
  ///
  /// With [tasks] set and no [formats], only the formats runnable for those
  /// tasks are searched.
  final bool onlyRunnable;

  /// Fetch per-file sizes and hashes (one extra request per result).
  final bool includeFileSizes;

  const SearchQuery({
    this.text = '',
    this.formats = const {},
    this.tasks = const {},
    this.pipelineTags = const {},
    this.library,
    this.author,
    this.maxSizeBytes,
    this.minDownloads,
    this.limit = 20,
    this.sort = ModelSort.downloads,
    this.descending = true,
    this.onlyRunnable = true,
    this.includeFileSizes = true,
  }) : assert(limit > 0, 'limit must be positive');

  /// Every `pipeline_tag` to query: those of [tasks] plus [pipelineTags].
  Set<String> get allPipelineTags => {
    for (final t in tasks) ...t.pipelineTags,
    ...pipelineTags,
  };

  /// Formats to search: [formats], or the runnable ones of [tasks] when only
  /// runnable models are wanted.
  Set<ModelFormat> get searchFormats {
    if (formats.isNotEmpty || !onlyRunnable || tasks.isEmpty) return formats;
    return {for (final t in tasks) ...t.runnableFormats};
  }

  /// Whether no model can match: runnable-only search for tasks the toolkit
  /// cannot run locally.
  bool get isUnsatisfiable =>
      formats.isEmpty &&
      onlyRunnable &&
      tasks.isNotEmpty &&
      pipelineTags.isEmpty &&
      searchFormats.isEmpty;
}
