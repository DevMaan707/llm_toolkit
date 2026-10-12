import 'package:llm_toolkit/src/core/config.dart';
import 'package:llm_toolkit/src/core/inference/base_inference_engine.dart';

/// Scripted [TextGenerator]: each call pops the next reply and streams it in
/// [chunkSize] pieces. Records the prompts it received.
class FakeTextGenerator implements TextGenerator {
  final List<String> replies;
  final int chunkSize;
  final prompts = <String>[];
  final paramsSeen = <GenerationParams>[];

  FakeTextGenerator(this.replies, {this.chunkSize = 3});

  @override
  Stream<String> generateText(String prompt, GenerationParams params) async* {
    prompts.add(prompt);
    paramsSeen.add(params);
    final reply = replies.removeAt(0);
    for (var i = 0; i < reply.length; i += chunkSize) {
      yield reply.substring(i, (i + chunkSize).clamp(0, reply.length));
    }
  }
}

class FakeChatGenerator implements ChatGenerator {
  final String reply;
  final calls = <List<ChatTurn>>[];

  FakeChatGenerator(this.reply);

  @override
  Stream<String> generateChat(
    List<ChatTurn> messages,
    GenerationParams params,
  ) {
    calls.add(messages);
    return Stream.value(reply);
  }
}
