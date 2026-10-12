import 'dart:convert';

import '../chat_message.dart';
import '../prompt_template.dart';
import 'template_utils.dart';

/// Moonshot Kimi (K2 / Moonlight): `<|im_user|>user<|im_middle|>...<|im_end|>`
/// with no separators between turns.
///
/// Like the official template it adds [defaultSystemPrompt] when the
/// conversation has no leading system message (pass null to disable). Tool
/// results are sent with the `tool` role and a `## Return of` header.
class KimiTemplate extends PromptTemplate {
  static const defaultSystem =
      'You are Kimi, an AI assistant created by Moonshot AI.';

  final String? defaultSystemPrompt;

  const KimiTemplate({this.defaultSystemPrompt = defaultSystem});

  @override
  String get name => 'kimi';

  @override
  List<String> get stopSequences => const ['<|im_end|>', '[EOS]'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer();
    if (defaultSystemPrompt != null &&
        (messages.isEmpty || messages.first.role != ChatRole.system)) {
      b.write('<|im_system|>system<|im_middle|>$defaultSystemPrompt<|im_end|>');
    }
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          b.write('<|im_system|>system<|im_middle|>${m.content}<|im_end|>');
        case ChatRole.user:
          b.write('<|im_user|>user<|im_middle|>${m.content}<|im_end|>');
        case ChatRole.assistant:
          b.write('<|im_assistant|>assistant<|im_middle|>${m.content}');
          if (m.toolCalls.isNotEmpty) {
            b.write('<|tool_calls_section_begin|>');
            for (final (i, c) in m.toolCalls.indexed) {
              b.write(
                '<|tool_call_begin|>functions.${c.name}:$i'
                '<|tool_call_argument_begin|>${jsonEncode(c.arguments)}'
                '<|tool_call_end|>',
              );
            }
            b.write('<|tool_calls_section_end|>');
          }
          b.write('<|im_end|>');
        case ChatRole.tool:
          b.write(
            '<|im_system|>tool<|im_middle|>'
            '## Return of ${m.toolName ?? 'tool'}\n${m.content}<|im_end|>',
          );
      }
    }
    if (addGenerationPrompt) b.write('<|im_assistant|>assistant<|im_middle|>');
    return b.toString();
  }
}

/// GLM-4 (0414 generation): `[gMASK]<sop><|user|>\n...<|assistant|>`.
///
/// Tool results use the `<|observation|>` role. The GLM-4.5 and later
/// thinking variants are not modelled.
class GlmTemplate extends PromptTemplate {
  final bool addBos;

  const GlmTemplate({this.addBos = true});

  @override
  String get name => 'glm4';

  @override
  List<String> get stopSequences => const [
    '<|user|>',
    '<|observation|>',
    '<|endoftext|>',
  ];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(addBos ? '[gMASK]<sop>' : '');
    for (final m in messages) {
      final role = m.role == ChatRole.tool ? 'observation' : m.role.name;
      b.write('<|$role|>\n${templateText(m)}');
    }
    if (addGenerationPrompt) b.write('<|assistant|>');
    return b.toString();
  }
}

/// IBM Granite 3 / 4: `<|start_of_role|>user<|end_of_role|>...<|end_of_text|>`.
///
/// No default system prompt is injected (the official template adds a dated
/// "You are Granite" preamble). Tool results use the `tool_response` role and
/// assistant tool calls the `<|tool_call|>[...]` JSON list.
class GraniteTemplate extends PromptTemplate {
  const GraniteTemplate();

  @override
  String get name => 'granite';

  @override
  List<String> get stopSequences => const ['<|end_of_text|>'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer();
    for (final m in messages) {
      final role = m.role == ChatRole.tool ? 'tool_response' : m.role.name;
      final calls =
          m.toolCalls.isEmpty
              ? ''
              : '<|tool_call|>${jsonEncode([for (final c in m.toolCalls) c.toJson()])}';
      b.write(
        '<|start_of_role|>$role<|end_of_role|>${m.content}$calls'
        '<|end_of_text|>\n',
      );
    }
    if (addGenerationPrompt) {
      b.write('<|start_of_role|>assistant<|end_of_role|>');
    }
    return b.toString();
  }
}

/// Cohere Command-R / Command-R+ / Command-R7B / Aya.
///
/// The official template is verified only from memory of the model cards;
/// tool results are sent as user turns.
class CohereTemplate extends PromptTemplate {
  final bool addBos;

  const CohereTemplate({this.addBos = true});

  @override
  String get name => 'cohere';

  @override
  List<String> get stopSequences => const ['<|END_OF_TURN_TOKEN|>'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(addBos ? '<BOS_TOKEN>' : '');
    for (final m in messages) {
      final token = switch (m.role) {
        ChatRole.system => 'SYSTEM',
        ChatRole.user || ChatRole.tool => 'USER',
        ChatRole.assistant => 'CHATBOT',
      };
      b.write(
        '<|START_OF_TURN_TOKEN|><|${token}_TOKEN|>${templateText(m)}'
        '<|END_OF_TURN_TOKEN|>',
      );
    }
    if (addGenerationPrompt) {
      b.write('<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>');
    }
    return b.toString();
  }
}

/// OLMo 2 Instruct: `<|user|>\n...\n<|assistant|>\n...<|endoftext|>`.
/// OLMo 3 uses ChatML instead, see [Olmo3Template].
class Olmo2Template extends PromptTemplate {
  final bool addBos;

  const Olmo2Template({this.addBos = true});

  @override
  String get name => 'olmo2';

  @override
  List<String> get stopSequences => const ['<|endoftext|>'];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(addBos ? '<|endoftext|>' : '');
    for (final m in messages) {
      if (m.role == ChatRole.assistant) {
        b.write('<|assistant|>\n${templateText(m)}<|endoftext|>\n');
      } else {
        final role = m.role == ChatRole.system ? 'system' : 'user';
        b.write('<|$role|>\n${templateText(m)}\n');
      }
    }
    if (addGenerationPrompt) b.write('<|assistant|>\n');
    return b.toString();
  }
}

/// OpenAI gpt-oss in the harmony format.
///
/// System messages become the developer `# Instructions` block. History keeps
/// only final-channel text. The model answers with an `analysis` (reasoning)
/// message first; stripping it from the output is the caller's job, unless
/// [finalChannelOnly] pre-fills `<|channel|>final<|message|>` so generation
/// starts directly in the answer (this skips reasoning).
class GptOssTemplate extends PromptTemplate {
  /// `low`, `medium` or `high`.
  final String reasoningEffort;
  final String knowledgeCutoff;

  /// Date shown in the system message; defaults to the current day.
  final DateTime? date;
  final bool finalChannelOnly;

  const GptOssTemplate({
    this.reasoningEffort = 'medium',
    this.knowledgeCutoff = '2024-06',
    this.date,
    this.finalChannelOnly = false,
  });

  @override
  String get name => 'gpt-oss';

  @override
  List<String> get stopSequences => [
    '<|return|>',
    '<|call|>',
    if (finalChannelOnly) '<|end|>',
  ];

  @override
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true}) {
    final b = StringBuffer(
      '<|start|>system<|message|>'
      'You are ChatGPT, a large language model trained by OpenAI.\n'
      'Knowledge cutoff: $knowledgeCutoff\n'
      'Current date: ${isoDate(date ?? DateTime.now())}\n\n'
      'Reasoning: $reasoningEffort\n\n'
      '# Valid channels: analysis, commentary, final. '
      'Channel must be included for every message.<|end|>',
    );
    final instructions = [
      for (final m in messages)
        if (m.role == ChatRole.system) m.content,
    ].join('\n\n');
    if (instructions.isNotEmpty) {
      b.write(
        '<|start|>developer<|message|># Instructions\n\n$instructions\n\n'
        '<|end|>',
      );
    }
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          break;
        case ChatRole.user:
          b.write('<|start|>user<|message|>${m.content}<|end|>');
        case ChatRole.assistant when m.toolCalls.isEmpty:
          b.write(
            '<|start|>assistant<|channel|>final<|message|>${m.content}<|end|>',
          );
        case ChatRole.assistant:
          if (m.content.isNotEmpty) {
            b.write(
              '<|start|>assistant<|channel|>analysis<|message|>${m.content}'
              '<|end|>',
            );
          }
          for (final c in m.toolCalls) {
            b.write(
              '<|start|>assistant to=functions.${c.name}'
              '<|channel|>commentary json<|message|>${jsonEncode(c.arguments)}'
              '<|call|>',
            );
          }
        case ChatRole.tool:
          b.write(
            '<|start|>functions.${m.toolName ?? 'tool'} to=assistant'
            '<|channel|>commentary<|message|>${jsonEncode(m.content)}<|end|>',
          );
      }
    }
    if (addGenerationPrompt) {
      b.write('<|start|>assistant');
      if (finalChannelOnly) b.write('<|channel|>final<|message|>');
    }
    return b.toString();
  }
}
