import 'dart:convert';

import '../core/logging/toolkit_logger.dart';
import 'chat_message.dart';
import 'chat_session.dart';
import 'tools.dart';

/// Outcome of one tool invocation.
class ToolExecution {
  final ToolCall call;

  /// Text fed back to the model.
  final String result;
  final bool isError;

  const ToolExecution(this.call, this.result, {this.isError = false});
}

/// Result of [ToolRunner.run].
class ToolRunResult {
  /// The model's last reply (the final answer unless [reachedLimit]).
  final String text;
  final List<ToolExecution> executions;

  /// Number of model replies generated.
  final int iterations;

  /// True when the model was still calling tools after `maxIterations`.
  final bool reachedLimit;

  const ToolRunResult(
    this.text,
    this.executions,
    this.iterations, {
    this.reachedLimit = false,
  });
}

/// Agent loop: generate, execute requested tools, feed results back as tool
/// messages, repeat until the model answers without a tool call.
class ToolRunner {
  final ChatSession session;
  final List<ToolDefinition> tools;
  final int maxIterations;

  ToolRunner(this.session, this.tools, {this.maxIterations = 5});

  /// Sends [text] and runs the loop. [onToken] receives every streamed chunk.
  Future<ToolRunResult> run(
    String text, {
    void Function(String chunk)? onToken,
  }) async {
    final originalSystem = session.systemPrompt;
    final instructions = toolInstructions(tools);
    session.systemPrompt =
        originalSystem == null || originalSystem.isEmpty
            ? instructions
            : '$originalSystem\n\n$instructions';
    final executions = <ToolExecution>[];
    var reply = '';
    try {
      for (var i = 1; i <= maxIterations; i++) {
        final stream = i == 1 ? session.send(text) : session.generate();
        final buffer = StringBuffer();
        await for (final chunk in stream) {
          buffer.write(chunk);
          onToken?.call(chunk);
        }
        reply = buffer.toString().trim();
        final calls = parseToolCalls(reply);
        if (calls.isEmpty) return ToolRunResult(reply, executions, i);
        for (final call in calls) {
          final execution = await _execute(call);
          executions.add(execution);
          session.addMessage(
            ChatMessage.tool(execution.result, name: call.name),
          );
        }
      }
      return ToolRunResult(
        reply,
        executions,
        maxIterations,
        reachedLimit: true,
      );
    } finally {
      session.systemPrompt = originalSystem;
    }
  }

  Future<ToolExecution> _execute(ToolCall call) async {
    final tool = tools.where((t) => t.name == call.name).firstOrNull;
    if (tool == null) {
      return ToolExecution(
        call,
        'Error: unknown tool "${call.name}"',
        isError: true,
      );
    }
    final problems = tool.parameters.validate(call.arguments);
    if (problems.isNotEmpty) {
      return ToolExecution(
        call,
        'Error: invalid arguments: ${problems.join('; ')}',
        isError: true,
      );
    }
    try {
      return ToolExecution(call, _encode(await tool.handler(call.arguments)));
    } catch (e) {
      ToolkitLog.warning('ToolRunner', 'Tool ${call.name} failed: $e');
      return ToolExecution(call, 'Error: $e', isError: true);
    }
  }

  static String _encode(Object? value) {
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }
}
