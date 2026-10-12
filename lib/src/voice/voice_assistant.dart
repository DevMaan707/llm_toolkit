import 'dart:typed_data';

import '../chat/chat_session.dart';
import '../chat/chat_usage.dart';
import '../core/inference/asr/pcm_recorder.dart';
import '../core/inference/base_inference_engine.dart';
import '../core/inference/sherpa/sherpa_asr_engine.dart';
import '../core/logging/toolkit_logger.dart';
import 'sentence_splitter.dart';

const _tag = 'Voice';

/// Something that happened during a voice turn.
sealed class VoiceEvent {
  const VoiceEvent();
}

/// The running hypothesis of a streaming recognizer; replaces the previous one.
class VoicePartialTranscript extends VoiceEvent {
  final String text;
  const VoicePartialTranscript(this.text);
}

/// What the user said, once recognised.
class VoiceTranscript extends VoiceEvent {
  final String text;
  const VoiceTranscript(this.text);
}

/// A piece of the assistant's reply text, for showing it as it is written.
class VoiceReplyToken extends VoiceEvent {
  final String text;
  const VoiceReplyToken(this.text);
}

/// One spoken sentence: [wav] is a complete WAV file, ready to play. Events
/// arrive in order; queue them in your audio player.
class VoiceSpeech extends VoiceEvent {
  final String text;
  final Uint8List wav;
  const VoiceSpeech(this.text, this.wav);
}

/// The turn finished (or was interrupted).
class VoiceTurnDone extends VoiceEvent {
  final String reply;
  final ChatUsage? usage;
  final bool interrupted;
  const VoiceTurnDone(this.reply, {this.usage, this.interrupted = false});
}

/// A non-fatal problem, such as one sentence that could not be synthesised.
/// The turn continues.
class VoiceWarning extends VoiceEvent {
  final String message;
  const VoiceWarning(this.message);
}

/// Speech in, speech out: recognised text goes to a [ChatSession], and the
/// reply is spoken sentence by sentence as it is generated.
///
/// The assistant produces audio but does not play it; feed every
/// [VoiceSpeech.wav] to the audio player of your choice. While a reply is
/// being produced, further microphone input is buffered rather than
/// processed, and [interrupt] stops the current turn.
class VoiceAssistant {
  final ChatSession chat;
  final SpeechSynthesizer synthesizer;

  /// Passed to [SpeechSynthesizer.synthesize] (speaker id or name).
  final String? voice;

  /// Minimum sentence length before a chunk is sent to the synthesizer.
  final int minSentenceLength;

  bool _interrupted = false;

  VoiceAssistant({
    required this.chat,
    required this.synthesizer,
    this.voice,
    this.minSentenceLength = 20,
  });

  /// Stops the turn in progress. The partial reply stays in the chat history.
  void interrupt() {
    _interrupted = true;
    chat.cancel();
  }

  /// One turn from typed or already recognised text.
  Stream<VoiceEvent> respondToText(String userText) async* {
    final text = userText.trim();
    if (text.isEmpty) return;
    _interrupted = false;
    final splitter = SentenceSplitter(minLength: minSentenceLength);
    final reply = StringBuffer();
    try {
      await for (final chunk in chat.send(text)) {
        if (_interrupted) break;
        reply.write(chunk);
        yield VoiceReplyToken(chunk);
        for (final sentence in splitter.add(chunk)) {
          yield* _speak(sentence);
          if (_interrupted) break;
        }
      }
      if (!_interrupted) {
        final rest = splitter.flush();
        if (rest != null) yield* _speak(rest);
      }
    } finally {
      // Keep the history consistent if the consumer stops listening.
      if (_interrupted) chat.cancel();
    }
    yield VoiceTurnDone(
      reply.toString().trim(),
      usage: chat.lastUsage,
      interrupted: _interrupted,
    );
  }

  /// One turn from recorded audio (a WAV file or 16 kHz PCM16, whatever
  /// [recognizer] accepts).
  Stream<VoiceEvent> respondToAudio(
    Uint8List audio,
    SpeechRecognizer recognizer,
  ) async* {
    final text = (await recognizer.transcribe(audio)).trim();
    if (text.isEmpty) {
      yield const VoiceWarning('No speech recognised');
      return;
    }
    yield VoiceTranscript(text);
    yield* respondToText(text);
  }

  /// Hands-free loop: records the microphone, recognises utterances with a
  /// streaming (or VAD-enabled) sherpa model, and answers each one. Cancel the
  /// subscription to stop listening; the microphone is released then.
  Stream<VoiceEvent> listen({
    required SherpaAsrEngine recognizer,
    PcmRecorder? recorder,
  }) async* {
    final mic = recorder ?? RecordPcmRecorder();
    if (!await mic.hasPermission()) {
      throw StateError('Microphone permission was not granted');
    }
    final pcm = await mic.start(16000);
    try {
      await for (final update in recognizer.transcribeUpdates(pcm)) {
        if (!update.isFinal) {
          yield VoicePartialTranscript(update.text);
          continue;
        }
        final text = update.text.trim();
        if (text.isEmpty) continue;
        yield VoiceTranscript(text);
        yield* respondToText(text);
      }
    } finally {
      await mic.stop();
      if (recorder == null) await mic.dispose();
    }
  }

  Stream<VoiceEvent> _speak(String sentence) async* {
    try {
      yield VoiceSpeech(
        sentence,
        await synthesizer.synthesize(sentence, voice: voice),
      );
    } catch (e) {
      ToolkitLog.warning(_tag, 'Could not speak "$sentence": $e');
      yield VoiceWarning('Could not synthesise speech: $e');
    }
  }
}
