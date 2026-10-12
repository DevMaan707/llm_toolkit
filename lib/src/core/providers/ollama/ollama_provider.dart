import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' hide ProgressCallback;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../base_provider.dart';
import '../../model_info.dart';
import '../../search_query.dart';
import '../../storage/download_manager.dart';

/// Models held by a local Ollama server (<https://ollama.com>).
///
/// "Downloading" pulls the model into the server's own store, so
/// [downloadModel] returns the model name rather than a file path and
/// [startDownload] is unsupported.
class OllamaProvider extends BaseModelProvider {
  final String baseUrl;
  final Dio _dio;
  final _pulls = <String, CancelToken>{};

  OllamaProvider({this.baseUrl = 'http://localhost:11434', Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  @override
  String get id => 'ollama';

  @override
  Future<List<ModelInfo>> searchModels(SearchQuery query) async {
    if (query.formats.isNotEmpty && !query.formats.contains(ModelFormat.gguf)) {
      return [];
    }
    final json = await _send<Map<String, dynamic>>('GET', '/api/tags');
    final text = query.text.trim().toLowerCase();
    final models = <ModelInfo>[
      for (final m in json['models'] as List? ?? const [])
        _parse(m as Map<String, dynamic>),
    ];
    final filtered =
        models.where((m) {
          if (text.isNotEmpty && !m.id.toLowerCase().contains(text)) {
            return false;
          }
          final max = query.maxSizeBytes;
          return max == null || (m.sizeBytes ?? 0) <= max;
        }).toList();

    filtered.sort((a, b) {
      final result = switch (query.sort) {
        ModelSort.lastModified || ModelSort.createdAt => (a.lastModified ??
                DateTime(0))
            .compareTo(b.lastModified ?? DateTime(0)),
        _ => a.id.compareTo(b.id),
      };
      final byDate =
          query.sort == ModelSort.lastModified ||
          query.sort == ModelSort.createdAt;
      return byDate && query.descending ? -result : result;
    });
    return filtered.take(query.limit).toList();
  }

  @override
  Future<ModelInfo> getModelDetails(String modelId) async {
    final json = await _send<Map<String, dynamic>>(
      'POST',
      '/api/show',
      data: {'model': modelId},
      notFound: 'Model "$modelId" is not installed in Ollama',
    );
    final details = json['details'] as Map<String, dynamic>? ?? const {};
    final info = json['model_info'] as Map<String, dynamic>? ?? const {};
    final context =
        info.entries
            .where((e) => e.key.endsWith('.context_length'))
            .map((e) => (e.value as num).toInt())
            .firstOrNull;
    final license = (json['license'] as String?)?.trim().split('\n').first;
    return ModelInfo(
      id: modelId,
      name: modelId,
      provider: id,
      description: json['modelfile'] as String? ?? '',
      pipelineTag: PipelineTags.textGeneration,
      runtime: EngineIds.ollama,
      library: 'ollama',
      license: license,
      parameterCount:
          (info['general.parameter_count'] as num?)?.toInt() ??
          _parameters(details['parameter_size']),
      contextLength: context,
      quantization: details['quantization_level'] as String?,
      tags: [if (details['family'] case final String family) family],
    );
  }

  @override
  Future<DownloadTask> startDownload(String modelId, String filename) {
    throw const ModelProviderException(
      'Ollama pulls models into the server; use downloadModel',
    );
  }

  /// Pulls [modelId] (for example `llama3.2:1b`). [filename] is ignored.
  /// Returns the model name once the server reports success.
  @override
  Future<String> downloadModel(
    String modelId,
    String filename, {
    ProgressCallback? onProgress,
    DownloadProgressCallback? onDetailedProgress,
  }) async {
    final token = _pulls[modelId] = CancelToken();
    final layers = <String, (int, int)>{};
    final clock = Stopwatch()..start();
    try {
      final response = await _dio.post<ResponseBody>(
        '$baseUrl/api/pull',
        data: {'model': modelId, 'stream': true},
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      final lines = response.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;
        if (event['error'] case final String error) {
          throw ModelProviderException('Ollama pull failed: $error');
        }
        final digest = event['digest'] as String?;
        final total = (event['total'] as num?)?.toInt();
        if (digest != null && total != null) {
          layers[digest] = ((event['completed'] as num?)?.toInt() ?? 0, total);
          _report(layers, clock, onProgress, onDetailedProgress);
        }
      }
      onProgress?.call(1);
      return modelId;
    } on DioException catch (e) {
      throw _map(e, 'Model "$modelId" was not found in the Ollama library');
    } finally {
      _pulls.remove(modelId);
    }
  }

  @override
  bool cancelDownload(String modelId, String filename) {
    final token = _pulls[modelId];
    token?.cancel('cancelled');
    return token != null;
  }

  @override
  void dispose() {
    for (final token in _pulls.values) {
      token.cancel('disposed');
    }
    _pulls.clear();
    super.dispose();
  }

  void _report(
    Map<String, (int, int)> layers,
    Stopwatch clock,
    ProgressCallback? onProgress,
    DownloadProgressCallback? onDetailed,
  ) {
    final done = layers.values.fold(0, (s, l) => s + l.$1);
    final total = layers.values.fold(0, (s, l) => s + l.$2);
    if (total == 0) return;
    final seconds = clock.elapsedMilliseconds / 1000;
    onProgress?.call(done / total);
    onDetailed?.call(
      DownloadProgress(
        state: DownloadState.downloading,
        receivedBytes: done,
        totalBytes: total,
        bytesPerSecond: seconds > 0 ? done / seconds : 0,
      ),
    );
  }

  ModelInfo _parse(Map<String, dynamic> m) {
    final name = (m['name'] ?? m['model']) as String;
    final details = m['details'] as Map<String, dynamic>? ?? const {};
    return ModelInfo(
      id: name,
      name: name,
      provider: id,
      library: 'ollama',
      pipelineTag: PipelineTags.textGeneration,
      runtime: EngineIds.ollama,
      lastModified: DateTime.tryParse(m['modified_at'] as String? ?? ''),
      sizeBytes: (m['size'] as num?)?.toInt(),
      parameterCount:
          _parameters(details['parameter_size']) ??
          ModelNaming.parameterCount(name),
      quantization: details['quantization_level'] as String?,
      tags: [if (details['family'] case final String family) family],
    );
  }

  static int? _parameters(Object? text) =>
      text is String ? ModelNaming.parameterCount(text) : null;

  Future<T> _send<T>(
    String method,
    String path, {
    Object? data,
    String? notFound,
  }) async {
    try {
      final response = await _dio.request<T>(
        '$baseUrl$path',
        data: data,
        options: Options(method: method),
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _map(e, notFound);
    }
  }

  ModelProviderException _map(DioException e, String? notFound) {
    if (e.type == DioExceptionType.cancel) {
      return const ModelProviderException('Ollama request cancelled');
    }
    final status = e.response?.statusCode;
    final message = switch (status) {
      404 => notFound ?? 'Ollama endpoint not found (HTTP 404)',
      final int s => 'Ollama returned HTTP $s',
      null =>
        'Could not reach Ollama at $baseUrl; is the server running? '
            '(${e.type.name})',
    };
    return ModelProviderException(message, e);
  }
}
