import 'dart:async';
import 'dart:convert';

import 'chat_message.dart';
import 'json_extraction.dart';
import 'json_schema.dart';

/// Implementation of a tool: receives the validated arguments.
typedef ToolHandler = FutureOr<Object?> Function(Map<String, dynamic> args);

/// A function the model may call.
class ToolDefinition {
  final String name;
  final String description;
  final JsonSchema parameters;
  final ToolHandler handler;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.handler,
    this.parameters = const JsonSchema.object(),
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'parameters': parameters.toJson(),
  };
}

/// System-prompt text that teaches a model to call [tools].
String toolInstructions(List<ToolDefinition> tools) =>
    'You can call these tools:\n'
    '${tools.map((t) => jsonEncode(t.toJson())).join('\n')}\n\n'
    'To call a tool, reply with only:\n'
    '<tool_call>\n{"name": "<tool name>", "arguments": {...}}\n</tool_call>\n'
    'You will receive the result in a tool message. When you have what you '
    'need, answer the user normally without a tool call.';

/// Extracts tool calls from model output.
///
/// Understands `<tool_call>{...}</tool_call>` tags and bare JSON in the forms
/// `{"name": .., "arguments": ..}`, `{"function": {"name": .., "arguments":
/// ..}}`, `{"tool_calls": [...]}` or an array of those. `parameters` is
/// accepted as an alias of `arguments`, and string-encoded arguments are
/// decoded.
List<ToolCall> parseToolCalls(String text) {
  final tagged = RegExp(
    r'<tool_call>([\s\S]*?)(?:</tool_call>|$)',
  ).allMatches(text);
  final calls = <ToolCall>[];
  if (tagged.isNotEmpty) {
    for (final m in tagged) {
      for (final v in extractJsonValues(m.group(1)!)) {
        _collect(v, calls);
      }
    }
    return calls;
  }
  for (final v in extractJsonValues(text)) {
    _collect(v, calls);
  }
  return calls;
}

void _collect(Object? value, List<ToolCall> out) {
  if (value is List) {
    for (final v in value) {
      _collect(v, out);
    }
  } else if (value is Map) {
    if (value['tool_calls'] is List) return _collect(value['tool_calls'], out);
    final inner = value['function'] is Map ? value['function'] as Map : value;
    final name = inner['name'];
    if (name is! String || name.isEmpty) return;
    var args = inner['arguments'] ?? inner['parameters'] ?? const {};
    if (args is String) {
      final decoded = extractJson(args);
      args = decoded ?? const {};
    }
    if (args is! Map) return;
    out.add(ToolCall(name, Map<String, dynamic>.from(args)));
  }
}
