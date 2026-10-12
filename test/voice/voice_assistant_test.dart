import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/chat/chat_session.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';
import 'package:llm_toolkit/src/voice/sentence_splitter.dart';
import 'package:llm_toolkit/src/voice/voice_assistant.dart';

import '../chat/fakes.dart';

class _Tts implements SpeechSynthesizer {
  final spoken = <String>[];
  final String? failOn;
  _Tts({this.failOn});

  @override
  Future<Uint8List> synthesize(String text, {String? voice}) async {
    if (failOn != null && text.contains(failOn!)) throw StateError('boom');
    spoken.add('$text|${voice ?? ''}');
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _Asr implements SpeechRecognizer {
  final String text;
  _Asr(this.text);

  @override
  Future<String> transcribe(Uint8List audio) async => text;
}

void main() {
  group('SentenceSplitter', () {
    test('emits whole sentences across chunk boundaries', () {
      final s = SentenceSplitter(minLength: 10);
      final out = <String>[];
      for (final c in ['The sky is blue. It is', ' a nice day! Bye']) {
        out.addAll(s.add(c));
      }
      expect(out, ['The sky is blue.', 'It is a nice day!']);
      expect(s.flush(), 'Bye');
    });

    test('keeps decimals together and merges short fragments', () {
      final s = SentenceSplitter(minLength: 12);
      final out = <String>[
        ...s.add('Pi is about 3.14 and e is 2.71. Ok. Yes indeed. '),
      ];
      expect(out, ['Pi is about 3.14 and e is 2.71.', 'Ok. Yes indeed.']);
    });

    test('waits for whitespace after a trailing period', () {
      final s = SentenceSplitter(minLength: 5);
      expect(s.add('Version 3.'), isEmpty);
      expect(s.add('5 is out. '), ['Version 3.5 is out.']);
    });

    test('strips markdown', () {
      expect(
        SentenceSplitter.clean(
          '## Title\n- **bold** and `code` [link](http://x)',
        ),
        'Title bold and code link',
      );
    });
  });

  group('VoiceAssistant', () {
    test('speaks the reply sentence by sentence', () async {
      final tts = _Tts();
      final chat = ChatSession(
        FakeTextGenerator(['Hello there, friend. How are you doing today?']),
      );
      final va = VoiceAssistant(chat: chat, synthesizer: tts, voice: '3');
      final events = await va.respondToText('hi').toList();
      expect(tts.spoken, [
        'Hello there, friend.|3',
        'How are you doing today?|3',
      ]);
      expect(events.whereType<VoiceSpeech>().length, 2);
      final done = events.last as VoiceTurnDone;
      expect(done.reply, 'Hello there, friend. How are you doing today?');
      expect(done.interrupted, isFalse);
    });

    test(
      'a failing sentence becomes a warning and the turn continues',
      () async {
        final tts = _Tts(failOn: 'friend');
        final chat = ChatSession(
          FakeTextGenerator(['Hello there, friend. How are you doing today?']),
        );
        final events =
            await VoiceAssistant(
              chat: chat,
              synthesizer: tts,
            ).respondToText('hi').toList();
        expect(events.whereType<VoiceWarning>().length, 1);
        expect(tts.spoken.single, startsWith('How are you'));
        expect(events.last, isA<VoiceTurnDone>());
      },
    );

    test('respondToAudio transcribes first, empty speech warns', () async {
      final chat = ChatSession(
        FakeTextGenerator(['Sure thing, happy to help.']),
      );
      final va = VoiceAssistant(chat: chat, synthesizer: _Tts());
      final events =
          await va.respondToAudio(Uint8List(0), _Asr('hello')).toList();
      expect((events.first as VoiceTranscript).text, 'hello');
      final none = await va.respondToAudio(Uint8List(0), _Asr('  ')).toList();
      expect(none.single, isA<VoiceWarning>());
    });

    test('interrupt stops speaking and reports it', () async {
      final tts = _Tts();
      final chat = ChatSession(
        FakeTextGenerator([
          'First sentence is here. Second sentence follows. Third one too.',
        ]),
      );
      final va = VoiceAssistant(chat: chat, synthesizer: tts);
      final events = <VoiceEvent>[];
      await for (final e in va.respondToText('go')) {
        events.add(e);
        if (e is VoiceSpeech) va.interrupt();
      }
      expect(tts.spoken.length, 1);
      expect((events.last as VoiceTurnDone).interrupted, isTrue);
    });
  });
}
