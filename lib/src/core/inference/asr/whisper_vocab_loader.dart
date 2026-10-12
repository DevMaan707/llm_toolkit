import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import '../../logging/toolkit_logger.dart';
import 'whisper_tokenizer.dart';

const _tag = 'ASR';
const _assetPath = 'assets/models/vocab.json';
const _remoteUrl =
    'https://huggingface.co/openai/whisper-tiny/resolve/main/vocab.json';

/// Finds a Whisper `vocab.json`, trying in order: [explicitPath], a
/// `vocab.json` next to the model, the app asset `assets/models/vocab.json`,
/// and finally a download (cached next to the model when possible).
Future<WhisperTokenizer> loadWhisperTokenizer(
  String modelPath, {
  String? explicitPath,
  http.Client? client,
}) async {
  final sibling = File(p.join(p.dirname(modelPath), 'vocab.json'));

  if (explicitPath != null) {
    final file = File(explicitPath);
    if (!await file.exists()) {
      throw InferenceException('Vocabulary file not found: $explicitPath');
    }
    return WhisperTokenizer.fromJson(await file.readAsString());
  }
  if (await sibling.exists()) {
    return WhisperTokenizer.fromJson(await sibling.readAsString());
  }
  try {
    return WhisperTokenizer.fromJson(await rootBundle.loadString(_assetPath));
  } catch (e) {
    ToolkitLog.debug(_tag, 'No bundled vocabulary ($e); downloading');
  }

  final http.Client c = client ?? http.Client();
  try {
    final response = await c.get(Uri.parse(_remoteUrl));
    if (response.statusCode != 200) {
      throw InferenceException(
        'Failed to download vocab.json (HTTP ${response.statusCode})',
      );
    }
    final body = response.body;
    final tokenizer = WhisperTokenizer.fromJson(body);
    try {
      await sibling.writeAsString(body);
    } on FileSystemException catch (e) {
      ToolkitLog.debug(_tag, 'Could not cache vocabulary: ${e.message}');
    }
    return tokenizer;
  } on http.ClientException catch (e) {
    throw InferenceException('Failed to download vocab.json', e);
  } finally {
    if (client == null) c.close();
  }
}
