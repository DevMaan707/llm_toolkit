import 'dart:math' as math;

import '../core/config.dart';
import '../core/inference/base_inference_engine.dart';
import '../exceptions/llm_toolkit_exceptions.dart';
import 'chat_message.dart';
import 'prompt_template.dart';

/// Estimates the token count of a string.
typedef TokenCounter = int Function(String text);

/// Rough estimate of ~4 characters per token.
int approximateTokenCount(String text) => (text.length / 4).ceil();

/// Cuts a stream of text at the first stop sequence, holding back chunk
/// suffixes that might still turn into one.
class StopSequenceFilter {
  final List<String> _stops;
  String _held = '';
  bool _stopped = false;

  StopSequenceFilter(Iterable<String> stops)
    : _stops = [
        for (final s in stops)
          if (s.isNotEmpty) s,
      ];

  /// True once a stop sequence was seen; further input is discarded.
  bool get stopped => _stopped;

  /// Returns the text that is safe to emit for [chunk].
  String add(String chunk) {
    if (_stopped) return '';
    final text = _held + chunk;
    var cut = -1;
    for (final s in _stops) {
      final i = text.indexOf(s);
      if (i >= 0 && (cut < 0 || i < cut)) cut = i;
    }
    if (cut >= 0) {
      _stopped = true;
      _held = '';
      return text.substring(0, cut);
    }
    var hold = 0;
    for (final s in _stops) {
      for (var k = math.min(s.length - 1, text.length); k > hold; k--) {
        if (text.endsWith(s.substring(0, k))) {
          hold = k;
          break;
        }
      }
    }
    _held = text.substring(text.length - hold);
    return text.substring(0, text.length - hold);
  }

  /// Emits whatever is still held back once the source stream ended.
  String flush() {
    final rest = _stopped ? '' : _held;
    _held = '';
    return rest;
  }
}

/// Streams a reply for [messages] from [engine], preferring its native
/// [ChatGenerator] and otherwise formatting with [template] for
/// [TextGenerator]. Stop sequences are enforced on the text path.
Stream<String> streamReply(
  Object engine,
  List<ChatMessage> messages, {
  required PromptTemplate template,
  required GenerationParams params,
}) {
  if (engine is ChatGenerator) {
    final turns = [
      for (final m in messages)
        ChatTurn(m.role.name, m.content, images: m.images),
    ];
    return engine.generateChat(turns, params);
  }
  if (engine is TextGenerator) {
    final stops = {...params.stopSequences, ...template.stopSequences}.toList();
    final prompt = template.format(messages);
    return _filtered(
      engine.generateText(prompt, params.copyWith(stopSequences: stops)),
      StopSequenceFilter(stops),
    );
  }
  throw const UnsupportedCapabilityException(
    'Engine implements neither ChatGenerator nor TextGenerator',
  );
}

Stream<String> _filtered(
  Stream<String> source,
  StopSequenceFilter filter,
) async* {
  await for (final chunk in source) {
    final out = filter.add(chunk);
    if (out.isNotEmpty) yield out;
    if (filter.stopped) return;
  }
  final rest = filter.flush();
  if (rest.isNotEmpty) yield rest;
}

/// Collects a whole reply into one string.
Future<String> collectReply(
  Object engine,
  List<ChatMessage> messages, {
  required PromptTemplate template,
  required GenerationParams params,
}) => streamReply(engine, messages, template: template, params: params).join();
