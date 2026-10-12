import '../chat_message.dart';
import '../prompt_template.dart';
import 'template_utils.dart';

/// DeepSeek (V3 / R1 / R1-distill) with full-width special tokens.
///
/// System messages follow the BOS directly (joined with a blank line), and
/// reasoning before `</think>` is dropped from earlier assistant turns, as in
/// the official template. Tool calls are rendered as `<tool_call>` tags rather
/// than DeepSeek's native tool tokens.
class DeepSeekTemplate extends PromptTemplate {
  final bool addBos;

  /// Ends the generation prompt with `<think>\n`, as the updated R1 templates
  /// do. The model then continues inside its reasoning block, so the opening
  /// tag does not appear in the generated text.
  final bool prefillThink;

  const DeepSeekTemplate({this.addBos = true, this.prefillThink = false});

  static const _bos = '<｜begin▁of▁sentence｜>';
  static const _eos = '<｜end▁of▁sentence｜>';
  static const _user = '<｜User｜>';
  static const _assistant = '<｜Assistant｜>';

  @override
  String get name => 'deepseek';

  @override
  List<String> get stopSequences => const [_eos];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(addBos ? _bos : '')..write(
      messages
          .where((m) => m.role == ChatRole.system)
          .map((m) => m.content)
          .join('\n\n'),
    );
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          break;
        case ChatRole.user || ChatRole.tool:
          b.write('$_user${templateText(m)}');
        case ChatRole.assistant:
          final content =
              m.toolCalls.isEmpty ? stripThink(m.content) : m.content;
          b.write('$_assistant${templateText(m, content)}$_eos');
      }
    }
    if (addGenerationPrompt) {
      b.write(prefillThink ? '$_assistant<think>\n' : _assistant);
    }
    return b.toString();
  }
}
