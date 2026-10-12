import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart' hide ProgressCallback;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../base_provider.dart';
import '../../logging/toolkit_logger.dart';
import '../../model_info.dart';
import '../../search_query.dart';
import '../../storage/download_manager.dart';
import '../../storage/model_store.dart';
import 'hf_parser.dart';

const _tag = 'HuggingFace';

/// Searches and downloads models from the Hugging Face Hub.
///
/// Search costs one list request (using the Hub's `expand` parameter) plus,
/// when file sizes are wanted, one detail request per result, issued with
/// bounded concurrency.
class HuggingFaceProvider extends BaseModelProvider {
  final String? apiKey;
  final String endpoint;
  final int detailConcurrency;
  final Dio _dio;
  final DownloadManager _downloads;
  final ModelStore? _store;
  final bool _ownsDownloads;

  HuggingFaceProvider({
    this.apiKey,
    this.endpoint = 'https://huggingface.co',
    this.detailConcurrency = 6,
    Dio? dio,
    DownloadManager? downloads,
    ModelStore? store,
  }) : assert(detailConcurrency > 0),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ),
       _downloads = downloads ?? DownloadManager(),
       _ownsDownloads = downloads == null,
       _store = store;

  @override
  String get id => 'huggingface';

  static const _formatTags = {
    ModelFormat.gguf: 'gguf',
    ModelFormat.litertlm: 'litert-lm',
    ModelFormat.task: 'litert-lm',
    ModelFormat.tflite: 'tflite',
    ModelFormat.onnx: 'onnx',
    ModelFormat.safetensors: 'safetensors',
  };

  @override
  Future<List<ModelInfo>> searchModels(SearchQuery query) async {
    final tags = {for (final f in query.formats) _formatTags[f]!};
    final pipelines =
        query.pipelineTags.isEmpty
            ? <String?>[null]
            : query.pipelineTags.toList();

    final requests = [
      for (final tag in tags.isEmpty ? <String?>[null] : tags.toList())
        for (final pipeline in pipelines) _listUri(query, tag, pipeline),
    ];
    final pages = await Future.wait(requests.map(_getJsonList));

    final byId = <String, ModelInfo>{};
    for (final page in pages) {
      for (final json in page) {
        final model = HfParser.model(
          json as Map<String, dynamic>,
          endpoint: endpoint,
        );
        byId.putIfAbsent(model.id, () => model);
      }
    }

    var models = byId.values.where((m) => _matches(m, query)).toList();
    if (requests.length > 1) {
      models.sort((a, b) => _compare(a, b, query));
    }
    models = models.take(query.limit).toList();

    if (query.includeFileSizes || query.maxSizeBytes != null) {
      models = await _withSizes(models);
    }
    final maxSize = query.maxSizeBytes;
    if (maxSize != null) {
      models = [
        for (final m in models)
          if (_limitSize(m, maxSize) case final fitted?) fitted,
      ];
    }
    return models;
  }

  @override
  Future<ModelInfo> getModelDetails(String modelId) async {
    final uri = _apiUri('models/$modelId', {
      'blobs': 'true',
      'expand[]': HfParser.expandFields,
    });
    final json = await _getJson(uri, notFound: 'Model "$modelId" not found');
    return HfParser.model(json as Map<String, dynamic>, endpoint: endpoint);
  }

  @override
  Future<DownloadTask> startDownload(String modelId, String filename) async {
    final details = await getModelDetails(modelId);
    final file = details.files.where((f) => f.filename == filename).firstOrNull;
    final store = _store ?? await ModelStore.defaultStore();
    final request = DownloadRequest(
      url: HfParser.resolveUrl(endpoint, modelId, filename),
      destination: store.pathFor(modelId, filename),
      headers: _authHeaders,
      sha256: file?.sha256,
      expectedSize: file?.sizeBytes,
    );
    ToolkitLog.info(_tag, 'Downloading $modelId/$filename');
    return _downloads.enqueue(request);
  }

  @override
  void dispose() {
    super.dispose();
    if (_ownsDownloads) _downloads.close();
  }

  Map<String, String> get _authHeaders => {
    if (apiKey != null) 'Authorization': 'Bearer $apiKey',
  };

  Uri _apiUri(String path, Map<String, Object> params) {
    final base = Uri.parse(endpoint);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        'api',
        ...path.split('/'),
      ],
      queryParameters: params,
    );
  }

  Uri _listUri(SearchQuery q, String? formatTag, String? pipeline) {
    return _apiUri('models', {
      if (q.text.trim().isNotEmpty) 'search': q.text.trim(),
      if (q.author != null) 'author': q.author!,
      if (formatTag != null || q.library != null)
        'filter': [
          if (formatTag != null) formatTag,
          if (q.library != null) q.library!,
        ],
      if (pipeline != null) 'pipeline_tag': pipeline,
      'sort': q.sort.apiValue,
      'direction': q.descending ? '-1' : '1',
      'limit': '${q.limit}',
      'expand[]': HfParser.expandFields,
    });
  }

  bool _matches(ModelInfo m, SearchQuery q) {
    if (q.minDownloads != null && m.downloads < q.minDownloads!) return false;
    if (q.formats.isNotEmpty) {
      return m.files.any((f) => q.formats.contains(f.format));
    }
    return !q.onlyRunnable || m.hasLoadableFiles;
  }

  int _compare(ModelInfo a, ModelInfo b, SearchQuery q) {
    final result = switch (q.sort) {
      ModelSort.downloads => a.downloads.compareTo(b.downloads),
      ModelSort.likes => a.likes.compareTo(b.likes),
      ModelSort.lastModified || ModelSort.createdAt => (a.lastModified ??
              DateTime(0))
          .compareTo(b.lastModified ?? DateTime(0)),
      ModelSort.trending => 0,
    };
    return q.descending ? -result : result;
  }

  ModelInfo? _limitSize(ModelInfo m, int maxSize) {
    final files = [
      for (final f in m.files)
        if (f.sizeBytes != null && f.sizeBytes! <= maxSize) f,
    ];
    return files.isEmpty ? null : m.copyWith(files: files);
  }

  Future<List<ModelInfo>> _withSizes(List<ModelInfo> models) {
    return _pool(models, detailConcurrency, (m) async {
      try {
        return await getModelDetails(m.id);
      } on ModelProviderException catch (e) {
        ToolkitLog.warning(_tag, 'No file sizes for ${m.id}', e);
        return m;
      }
    });
  }

  Future<Object?> _getJson(Uri uri, {String? notFound}) async {
    try {
      final response = await _dio.getUri<String>(
        uri,
        options: Options(
          headers: _authHeaders,
          responseType: ResponseType.plain,
        ),
      );
      return jsonDecode(response.data ?? 'null');
    } on DioException catch (e) {
      throw _mapError(e, notFound);
    } on FormatException catch (e) {
      throw ModelProviderException('Hugging Face returned invalid JSON', e);
    }
  }

  Future<List<Object?>> _getJsonList(Uri uri) async {
    final json = await _getJson(uri);
    if (json is! List) {
      throw const ModelProviderException(
        'Unexpected Hugging Face search response',
      );
    }
    return json;
  }

  ModelProviderException _mapError(DioException e, String? notFound) {
    final status = e.response?.statusCode;
    final message = switch (status) {
      401 => 'Hugging Face rejected the access token (HTTP 401)',
      403 =>
        'Access forbidden (HTTP 403): the model is gated or the token lacks '
            'permission',
      404 => notFound ?? 'Hugging Face resource not found (HTTP 404)',
      429 =>
        'Hugging Face rate limit reached (HTTP 429), retry after '
            '${e.response?.headers.value('retry-after') ?? 'a short wait'}',
      final int s when s >= 500 => 'Hugging Face is unavailable (HTTP $s)',
      _ => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'Hugging Face request timed out',
        DioExceptionType.connectionError =>
          'Could not reach Hugging Face; check the network connection',
        _ => 'Hugging Face request failed: ${e.message ?? e.error}',
      },
    };
    return ModelProviderException(message, e);
  }
}

/// Maps [items] with at most [limit] calls in flight, keeping order.
Future<List<R>> _pool<T, R>(
  List<T> items,
  int limit,
  Future<R> Function(T) fn,
) async {
  final results = List<R?>.filled(items.length, null);
  final next = Queue<int>.from(List.generate(items.length, (i) => i));
  Future<void> worker() async {
    while (next.isNotEmpty) {
      final i = next.removeFirst();
      results[i] = await fn(items[i]);
    }
  }

  await Future.wait(
    List.generate(limit.clamp(1, items.length + 1), (_) => worker()),
  );
  return [for (final r in results) r as R];
}
