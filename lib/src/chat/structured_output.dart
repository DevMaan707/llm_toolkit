import '../core/config.dart';
import '../exceptions/llm_toolkit_exceptions.dart';
import 'chat_backend.dart';
import 'chat_message.dart';
import 'json_extraction.dart';
import 'json_schema.dart';
import 'prompt_template.dart';

/// Asks [engine] (a `ChatGenerator` or `TextGenerator`) for JSON matching
/// [schema]. Output is extracted from the reply (fences, prose, minor syntax
/// errors are tolerated) and validated; on failure the model is shown its own
/// answer plus the problems and asked again, up to [maxRetries] more times.
///
/// Returns the decoded value, converted with [fromJson] when given. Throws
/// [StructuredOutputException] when no attempt validates.
Future<T> generateStructured<T>(
  Object engine, {
  required String prompt,
  required JsonSchema schema,
  PromptTemplate template = const ChatMlTemplate(),
  GenerationParams params = const GenerationParams(
    temperature: 0.2,
    maxTokens: 1024,
  ),
  String? systemPrompt,
  int maxRetries = 2,
  T Function(Object? json)? fromJson,
}) async {
  final messages = [
    ChatMessage.system(
      [
        if (systemPrompt != null) systemPrompt,
        schema.promptInstructions(),
      ].join('\n\n'),
    ),
    ChatMessage.user(prompt),
  ];
  var lastRaw = '';
  var lastProblem = 'no JSON found';
  for (var attempt = 0; attempt <= maxRetries; attempt++) {
    final raw = await collectReply(
      engine,
      messages,
      template: template,
      params: params,
    );
    lastRaw = raw;
    final problems = _check(raw, schema);
    if (problems.errors.isEmpty) {
      final value = problems.value;
      try {
        return fromJson != null ? fromJson(value) : value as T;
      } catch (e) {
        throw StructuredOutputException(
          'Could not convert structured output: $e',
          raw,
          e,
        );
      }
    }
    lastProblem = problems.errors.join('; ');
    messages
      ..add(ChatMessage.assistant(raw))
      ..add(
        ChatMessage.user(
          'That response was invalid: $lastProblem. Reply again with only '
          'the corrected JSON.',
        ),
      );
  }
  throw StructuredOutputException(
    'No valid JSON after ${maxRetries + 1} attempts: $lastProblem',
    lastRaw,
  );
}

/// Picks the first JSON value in [raw] that satisfies [schema].
({Object? value, List<String> errors}) _check(String raw, JsonSchema schema) {
  final candidates = extractJsonValues(raw);
  if (candidates.isEmpty) {
    return (value: null, errors: const ['the reply contained no JSON']);
  }
  List<String>? firstErrors;
  for (final c in candidates) {
    final errors = schema.validate(c);
    if (errors.isEmpty) return (value: c, errors: const []);
    firstErrors ??= errors;
  }
  return (value: null, errors: firstErrors!);
}
