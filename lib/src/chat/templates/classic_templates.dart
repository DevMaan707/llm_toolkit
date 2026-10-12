import '../chat_message.dart';
import '../prompt_template.dart';
import 'template_utils.dart';

/// Llama 3 / 3.1 header-id format.
class Llama3Template extends PromptTemplate {
  /// Whether to emit `<|begin_of_text|>` (engines that add BOS themselves
  /// should pass false).
  final bool addBos;

  const Llama3Template({this.addBos = true});

  @override
  String get name => 'llama3';

  @override
  List<String> get stopSequences => const ['<|eot_id|>', '<|end_of_text|>'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(addBos ? '<|begin_of_text|>' : '');
    for (final m in messages) {
      final role = m.role == ChatRole.tool ? 'ipython' : m.role.name;
      b.write(
        '<|start_header_id|>$role<|end_header_id|>\n\n${templateText(m)}'
        '<|eot_id|>',
      );
    }
    if (addGenerationPrompt) {
      b.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
    }
    return b.toString();
  }
}

/// Gemma `<start_of_turn>` format. There is no system role, so the system
/// prompt is folded into the first user turn.
class GemmaTemplate extends PromptTemplate {
  final bool addBos;

  const GemmaTemplate({this.addBos = true});

  @override
  String get name => 'gemma';

  @override
  List<String> get stopSequences => const ['<end_of_turn>'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(addBos ? '<bos>' : '');
    for (final m in foldSystem(messages)) {
      final role = m.role == ChatRole.assistant ? 'model' : 'user';
      b.write('<start_of_turn>$role\n${m.content}<end_of_turn>\n');
    }
    if (addGenerationPrompt) b.write('<start_of_turn>model\n');
    return b.toString();
  }
}

/// Mistral / Llama 2 `[INST]` format; the system prompt is folded into the
/// first instruction.
class MistralTemplate extends PromptTemplate {
  final bool addBos;

  const MistralTemplate({this.addBos = true});

  @override
  String get name => 'mistral';

  @override
  List<String> get stopSequences => const ['</s>', '[INST]'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(addBos ? '<s>' : '');
    for (final m in foldSystem(messages)) {
      if (m.role == ChatRole.assistant) {
        b.write(' ${m.content}</s>');
      } else {
        b.write('[INST] ${m.content} [/INST]');
      }
    }
    return b.toString();
  }
}

/// Phi-3 `<|user|>` / `<|assistant|>` format.
class Phi3Template extends PromptTemplate {
  const Phi3Template();

  @override
  String get name => 'phi3';

  @override
  List<String> get stopSequences => const ['<|end|>', '<|endoftext|>'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer();
    for (final m in messages) {
      final role = m.role == ChatRole.tool ? 'user' : m.role.name;
      b.write('<|$role|>\n${templateText(m)}<|end|>\n');
    }
    if (addGenerationPrompt) b.write('<|assistant|>\n');
    return b.toString();
  }
}
