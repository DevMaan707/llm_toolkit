import '../chat_message.dart';
import '../prompt_template.dart';
import 'template_utils.dart';

/// `<|im_start|>role ... <|im_end|>` (OpenAI ChatML).
class ChatMlTemplate extends PromptTemplate {
  const ChatMlTemplate();

  @override
  String get name => 'chatml';

  @override
  List<String> get stopSequences => const ['<|im_end|>'];

  /// Text written before the first turn (BOS for variants that emit one).
  String get prefix => '';

  /// Role label written after `<|im_start|>`.
  String roleOf(ChatMessage m) => m.role.name;

  /// Messages as rendered, e.g. with a default system prompt added.
  List<ChatMessage> prepare(List<ChatMessage> messages) => messages;

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(prefix);
    for (final m in prepare(messages)) {
      b.write('<|im_start|>${roleOf(m)}\n${templateText(m)}<|im_end|>\n');
    }
    if (addGenerationPrompt) b.write('<|im_start|>assistant\n');
    return b.toString();
  }
}

/// ChatML variant used by Qwen 2.5 / Qwen3: tool results come back as user
/// turns wrapped in `<tool_response>` tags (consecutive results share one
/// turn) and reasoning from earlier turns is dropped.
///
/// Qwen3 can also be switched to non-thinking mode, either per message with a
/// `/no_think` suffix in the user text or with [enableThinking] set to false,
/// which pre-fills an empty `<think>` block like the official template.
class QwenTemplate extends ChatMlTemplate {
  final bool enableThinking;

  const QwenTemplate({this.enableThinking = true});

  @override
  String get name => 'qwen';

  @override
  List<String> get stopSequences => const ['<|im_end|>', '<|endoftext|>'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer();
    final lastUser = lastUserIndex(messages);
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      switch (m.role) {
        case ChatRole.tool:
          if (i == 0 || messages[i - 1].role != ChatRole.tool) {
            b.write('<|im_start|>user');
          }
          b.write('\n<tool_response>\n${m.content}\n</tool_response>');
          if (i == messages.length - 1 ||
              messages[i + 1].role != ChatRole.tool) {
            b.write('<|im_end|>\n');
          }
        case ChatRole.assistant:
          final content =
              i < lastUser
                  ? stripThink(m.content, trimLeadingNewlines: true)
                  : m.content;
          b.write(
            '<|im_start|>assistant\n${templateText(m, content)}<|im_end|>\n',
          );
        case ChatRole.system || ChatRole.user:
          b.write('<|im_start|>${m.role.name}\n${m.content}<|im_end|>\n');
      }
    }
    if (addGenerationPrompt) {
      b.write('<|im_start|>assistant\n');
      if (!enableThinking) b.write('<think>\n\n</think>\n\n');
    }
    return b.toString();
  }
}

/// SmolLM2: ChatML with a default system prompt when none is given.
class SmolLmTemplate extends ChatMlTemplate {
  static const defaultSystem =
      'You are a helpful AI assistant named SmolLM, trained by Hugging Face';

  const SmolLmTemplate();

  @override
  String get name => 'smollm';

  @override
  List<ChatMessage> prepare(List<ChatMessage> messages) =>
      messages.isNotEmpty && messages.first.role == ChatRole.system
          ? messages
          : [const ChatMessage.system(defaultSystem), ...messages];
}

/// SmolLM3: ChatML with a metadata block in the system turn and a
/// `/think` / `/no_think` reasoning switch.
///
/// Tool results are sent as user turns. A system message containing
/// `/system_override` replaces the metadata block, as in the official
/// template.
class SmolLm3Template extends ChatMlTemplate {
  final bool enableThinking;

  /// Date shown in the metadata block; defaults to the current day.
  final DateTime? date;

  const SmolLm3Template({this.enableThinking = true, this.date});

  static const _emptyThink = '<think>\n\n</think>\n';

  @override
  String get name => 'smollm3';

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final system = [
      for (final m in messages)
        if (m.role == ChatRole.system) m.content,
    ].join('\n\n');
    final override = system.contains('/system_override');
    final mode = enableThinking ? '/think' : '/no_think';
    final custom = system.isEmpty ? SmolLmTemplate.defaultSystem : system;
    final b =
        StringBuffer('<|im_start|>system\n')
          ..write(
            override
                ? custom.replaceAll('/system_override', '').trim()
                : '## Metadata\n\n'
                    'Knowledge Cutoff Date: June 2025\n'
                    'Today Date: ${longDate(date ?? DateTime.now())}\n'
                    'Reasoning Mode: $mode\n\n'
                    '## Custom Instructions\n\n$custom\n',
          )
          ..write('\n<|im_end|>\n');
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          break;
        case ChatRole.assistant:
          b.write(
            '<|im_start|>assistant\n${enableThinking ? '' : _emptyThink}'
            '${templateText(m)}<|im_end|>\n',
          );
        case ChatRole.user || ChatRole.tool:
          b.write('<|im_start|>user\n${templateText(m)}<|im_end|>\n');
      }
    }
    if (addGenerationPrompt) {
      b.write('<|im_start|>assistant\n${enableThinking ? '' : _emptyThink}');
    }
    return b.toString();
  }
}

/// Liquid LFM2: ChatML with a `<|startoftext|>` BOS. Tool calls use the
/// pythonic `<|tool_call_start|>[fn(arg='x')]<|tool_call_end|>` form.
class LiquidTemplate extends ChatMlTemplate {
  final bool addBos;

  const LiquidTemplate({this.addBos = true});

  @override
  String get name => 'lfm2';

  @override
  String get prefix => addBos ? '<|startoftext|>' : '';

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(prefix);
    for (final m in messages) {
      final calls =
          m.toolCalls.isEmpty
              ? ''
              : '<|tool_call_start|>[${[
                for (final c in m.toolCalls) '${c.name}(${[for (final MapEntry(:key, :value) in c.arguments.entries) '$key=${pythonLiteral(value)}'].join(', ')})',
              ].join(', ')}]<|tool_call_end|>';
      b.write('<|im_start|>${m.role.name}\n${m.content}$calls<|im_end|>\n');
    }
    if (addGenerationPrompt) b.write('<|im_start|>assistant\n');
    return b.toString();
  }
}

/// InternLM2 / InternLM3: ChatML preceded by `<s>`; tool results use the
/// `environment` role.
class InternLmTemplate extends ChatMlTemplate {
  final bool addBos;

  const InternLmTemplate({this.addBos = true});

  @override
  String get name => 'internlm';

  @override
  List<String> get stopSequences => const ['<|im_end|>', '</s>'];

  @override
  String get prefix => addBos ? '<s>' : '';

  @override
  String roleOf(ChatMessage m) =>
      m.role == ChatRole.tool ? 'environment' : m.role.name;
}

/// MiniCPM3 / MiniCPM4: plain ChatML (BOS is added by the tokenizer).
class MiniCpmTemplate extends ChatMlTemplate {
  const MiniCpmTemplate();

  @override
  String get name => 'minicpm';
}

/// Yi-1.5 chat: plain ChatML (BOS is added by the tokenizer).
class YiTemplate extends ChatMlTemplate {
  const YiTemplate();

  @override
  String get name => 'yi';
}

/// OLMo 3: ChatML where tool results use the `environment` role.
class Olmo3Template extends ChatMlTemplate {
  const Olmo3Template();

  @override
  String get name => 'olmo3';

  @override
  String roleOf(ChatMessage m) =>
      m.role == ChatRole.tool ? 'environment' : m.role.name;
}
