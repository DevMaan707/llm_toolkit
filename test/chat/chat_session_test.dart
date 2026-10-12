import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/chat/chat_backend.dart';
import 'package:llm_toolkit/src/chat/chat_message.dart';
import 'package:llm_toolkit/src/chat/chat_session.dart';
import 'package:llm_toolkit/src/core/config.dart';

import 'fakes.dart';

void main() {
  group('StopSequenceFilter', () {
    test('cuts across chunk boundaries and holds partial matches', () {
      final f = StopSequenceFilter(['<|im_end|>']);
      final out = StringBuffer();
      for (final c in ['Hel', 'lo<|im', '_end|>junk', 'more']) {
        out.write(f.add(c));
      }
      out.write(f.flush());
      expect(out.toString(), 'Hello');
      expect(f.stopped, isTrue);
    });

    test('releases held text that turns out not to be a stop', () {
      final f = StopSequenceFilter(['<end>']);
      expect(f.add('a<en'), 'a');
      expect(f.add('x'), '<enx');
      expect(f.flush(), '');
    });
  });

  group('ChatSession', () {
    test(
      'streams, stores reply, formats with template, enforces stop',
      () async {
        final engine = FakeTextGenerator(['Hello there<|im_end|>garbage']);
        final s = ChatSession(engine, systemPrompt: 'sys');
        final chunks = await s.send('Hi').toList();
        expect(chunks.join(), 'Hello there');
        expect(s.history.map((m) => m.role), [
          ChatRole.user,
          ChatRole.assistant,
        ]);
        expect(s.history.last.content, 'Hello there');
        expect(
          engine.prompts.single,
          '<|im_start|>system\nsys<|im_end|>\n'
          '<|im_start|>user\nHi<|im_end|>\n'
          '<|im_start|>assistant\n',
        );
        expect(engine.paramsSeen.single.stopSequences, ['<|im_end|>']);
      },
    );

    test('prefers ChatGenerator', () async {
      final engine = FakeChatGenerator('yo');
      final s = ChatSession(engine, systemPrompt: 'sys');
      expect((await s.send('Hi').toList()).join(), 'yo');
      expect(engine.calls.single.map((t) => t.role), ['system', 'user']);
    });

    test('rejects engines without generation capability', () {
      expect(() => ChatSession(Object()), throwsArgumentError);
    });

    test('trims oldest turns but keeps system and latest turn', () async {
      final engine = FakeTextGenerator(List.generate(4, (_) => 'ok'));
      final s = ChatSession(
        engine,
        systemPrompt: 'S' * 40, // 10 + 4
        contextSize: 100,
        params: const GenerationParams(maxTokens: 20),
        tokenCounter: (t) => t.length,
      );
      // budget = 100 - 20 - 44 = 36; each turn: (u 1+4) + (a 2+4) = 11
      for (final t in ['a', 'b', 'c']) {
        await s.send(t).drain<void>();
      }
      expect(s.history, hasLength(6));
      final prompt = s.promptMessages();
      expect(prompt.first.role, ChatRole.system);
      expect(prompt.skip(1).where((m) => m.role == ChatRole.user).length, 3);
      await s.send('d').drain<void>();
      final trimmed = s.promptMessages();
      expect(trimmed.first.role, ChatRole.system);
      expect(
        trimmed.where((m) => m.role == ChatRole.user).map((m) => m.content),
        ['b', 'c', 'd'],
      );
      expect(s.history, hasLength(8));
    });

    test('latest turn survives even if over budget', () async {
      final s = ChatSession(
        FakeTextGenerator(['ok']),
        contextSize: 10,
        tokenCounter: (t) => t.length,
      );
      await s.send('x' * 500).drain<void>();
      s.addMessage(const ChatMessage.user('y'));
      expect(s.promptMessages().single.content, 'y');
    });

    test('undo, regenerate, reset', () async {
      final engine = FakeTextGenerator(['one', 'two', 'three']);
      final s = ChatSession(engine);
      await s.send('q').drain<void>();
      await s.regenerate().drain<void>();
      expect(s.history.map((m) => m.content), ['q', 'two']);
      expect(engine.prompts.last, engine.prompts.first);
      expect(s.undo(), isTrue);
      expect(s.history, isEmpty);
      expect(s.undo(), isFalse);
      await s.send('q2').drain<void>();
      s.reset();
      expect(s.history, isEmpty);
      expect(s.lastUsage, isNull);
    });

    test('cancel keeps partial reply', () async {
      final s = ChatSession(FakeTextGenerator(['abcdefghi'], chunkSize: 3));
      final got = <String>[];
      await for (final c in s.send('hi')) {
        got.add(c);
        s.cancel();
      }
      expect(got, ['abc']);
      expect(s.history.last.content, 'abc');
      expect(s.isGenerating, isFalse);
    });

    test('rolls back user message on error', () async {
      final s = ChatSession(_Failing());
      await expectLater(s.send('hi').drain<void>(), throwsStateError);
      expect(s.history, isEmpty);
      expect(s.isGenerating, isFalse);
    });

    test('usage stats with injected clock', () async {
      var now = DateTime(2024);
      final clock = _TickingClock(() => now, (d) => now = now.add(d));
      final s = ChatSession(
        _Slow(clock),
        tokenCounter: (t) => t.length,
        clock: clock.call,
      );
      await s.send('hello').drain<void>();
      final u = s.lastUsage!;
      expect(u.promptTokens, 5 + 4);
      expect(u.completionTokens, 5);
      expect(u.timeToFirstToken, const Duration(milliseconds: 500));
      expect(u.totalTime, const Duration(milliseconds: 1500));
      expect(u.tokensPerSecond, closeTo(4.0, 1e-9));
      expect(s.totalUsage.completionTokens, 5);
    });

    test('toJson / fromJson round trip', () async {
      final s = ChatSession(FakeTextGenerator(['reply']), systemPrompt: 'sys');
      s.addMessage(
        ChatMessage.user(
          'img',
          images: [
            Uint8List.fromList([1, 2, 3]),
          ],
        ),
      );
      await s.generate().drain<void>();
      final restored = ChatSession.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
        FakeTextGenerator([]),
      );
      expect(restored.systemPrompt, 'sys');
      expect(restored.history.map((m) => m.content), ['img', 'reply']);
      expect(restored.history.first.images.single, [1, 2, 3]);
    });
  });
}

class _Failing extends FakeTextGenerator {
  _Failing() : super([]);

  @override
  Stream<String> generateText(String prompt, GenerationParams params) =>
      Stream.error(StateError('boom'));
}

class _TickingClock {
  final DateTime Function() now;
  final void Function(Duration) advance;
  _TickingClock(this.now, this.advance);
  DateTime call() => now();
}

class _Slow extends FakeTextGenerator {
  final _TickingClock clock;
  _Slow(this.clock) : super([]);

  @override
  Stream<String> generateText(String prompt, GenerationParams params) async* {
    clock.advance(const Duration(milliseconds: 500));
    yield 'hel';
    clock.advance(const Duration(milliseconds: 1000));
    yield 'lo';
  }
}
