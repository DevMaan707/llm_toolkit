import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/chat/chat_message.dart';
import 'package:llm_toolkit/src/chat/chat_session.dart';
import 'package:llm_toolkit/src/chat/json_schema.dart';
import 'package:llm_toolkit/src/chat/prompt_template.dart';
import 'package:llm_toolkit/src/chat/tool_runner.dart';
import 'package:llm_toolkit/src/chat/tools.dart';

import 'fakes.dart';

final weather = ToolDefinition(
  name: 'weather',
  description: 'Get weather',
  parameters: const JsonSchema.object(
    properties: {'city': JsonSchema.string()},
    required: ['city'],
  ),
  handler: (args) => {'city': args['city'], 'temp': 7},
);

void main() {
  group('parseToolCalls', () {
    test('tag style', () {
      final calls = parseToolCalls(
        'Let me check.\n<tool_call>\n{"name": "weather", "arguments": {"city": "Oslo"}}\n</tool_call>',
      );
      expect(calls.single.name, 'weather');
      expect(calls.single.arguments, {'city': 'Oslo'});
    });

    test('multiple tags and unterminated tag', () {
      final calls = parseToolCalls(
        '<tool_call>{"name":"a","arguments":{}}</tool_call>'
        '<tool_call>{"name":"b","arguments":{"x":1}}',
      );
      expect(calls.map((c) => c.name), ['a', 'b']);
    });

    test('bare JSON, fenced, parameters alias, string arguments', () {
      expect(
        parseToolCalls(
          '```json\n{"name":"a","parameters":{"x":1}}\n```',
        ).single.arguments,
        {'x': 1},
      );
      expect(
        parseToolCalls(
          r'{"name":"a","arguments":"{\"x\": 2}"}',
        ).single.arguments,
        {'x': 2},
      );
    });

    test('openai style and arrays', () {
      final calls = parseToolCalls(
        '{"tool_calls":[{"function":{"name":"a","arguments":{"k":1}}},'
        '{"name":"b"}]}',
      );
      expect(calls.map((c) => c.name), ['a', 'b']);
      expect(calls.first.arguments, {'k': 1});
    });

    test('plain answers and non-call JSON yield nothing', () {
      expect(parseToolCalls('It is sunny.'), isEmpty);
      expect(parseToolCalls('{"answer": 42}'), isEmpty);
    });
  });

  group('ToolRunner', () {
    test('executes tool, feeds result back, returns final answer', () async {
      final engine = FakeTextGenerator([
        '<tool_call>{"name":"weather","arguments":{"city":"Oslo"}}</tool_call>',
        'It is 7 degrees in Oslo.',
      ]);
      final session = ChatSession(
        engine,
        systemPrompt: 'Helper',
        template: const QwenTemplate(),
      );
      final runner = ToolRunner(session, [weather]);
      final result = await runner.run('Weather in Oslo?');
      expect(result.text, 'It is 7 degrees in Oslo.');
      expect(result.iterations, 2);
      expect(result.reachedLimit, isFalse);
      expect(result.executions.single.result, '{"city":"Oslo","temp":7}');
      expect(engine.prompts[0], contains('"name":"weather"'));
      expect(engine.prompts[0], contains('Helper'));
      expect(
        engine.prompts[1],
        contains('<tool_response>\n{"city":"Oslo","temp":7}\n</tool_response>'),
      );
      expect(session.history.map((m) => m.role), [
        ChatRole.user,
        ChatRole.assistant,
        ChatRole.tool,
        ChatRole.assistant,
      ]);
      expect(session.systemPrompt, 'Helper');
    });

    test(
      'handler errors, unknown tools and bad arguments are reported',
      () async {
        final failing = ToolDefinition(
          name: 'boom',
          description: 'x',
          handler: (_) => throw StateError('kaput'),
        );
        final engine = FakeTextGenerator([
          '<tool_call>{"name":"boom","arguments":{}}</tool_call>'
              '<tool_call>{"name":"nope","arguments":{}}</tool_call>'
              '<tool_call>{"name":"weather","arguments":{}}</tool_call>',
          'done',
        ]);
        final runner = ToolRunner(ChatSession(engine), [failing, weather]);
        final result = await runner.run('go');
        expect(result.text, 'done');
        expect(result.executions.every((e) => e.isError), isTrue);
        expect(result.executions[0].result, contains('kaput'));
        expect(result.executions[1].result, contains('unknown tool "nope"'));
        expect(result.executions[2].result, contains(r'$.city is required'));
      },
    );

    test('stops at maxIterations', () async {
      const call =
          '<tool_call>{"name":"weather","arguments":{"city":"A"}}</tool_call>';
      final engine = FakeTextGenerator([call, call, call]);
      final runner = ToolRunner(ChatSession(engine), [
        weather,
      ], maxIterations: 2);
      final result = await runner.run('loop');
      expect(result.reachedLimit, isTrue);
      expect(result.iterations, 2);
      expect(result.executions, hasLength(2));
      expect(engine.replies, hasLength(1));
    });
  });
}
