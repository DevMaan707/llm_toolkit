import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/chat/chat_message.dart';
import 'package:llm_toolkit/src/chat/prompt_template.dart';

void main() {
  const conversation = [
    ChatMessage.system('Be brief.'),
    ChatMessage.user('Hi'),
    ChatMessage.assistant('Hello'),
    ChatMessage.user('Bye'),
  ];
  const noGen = false;

  group('kimi', () {
    test('formats turns without separators', () {
      expect(
        const KimiTemplate().format(conversation),
        '<|im_system|>system<|im_middle|>Be brief.<|im_end|>'
        '<|im_user|>user<|im_middle|>Hi<|im_end|>'
        '<|im_assistant|>assistant<|im_middle|>Hello<|im_end|>'
        '<|im_user|>user<|im_middle|>Bye<|im_end|>'
        '<|im_assistant|>assistant<|im_middle|>',
      );
    });

    test('adds the default system prompt when none is given', () {
      expect(
        const KimiTemplate().format(const [ChatMessage.user('Hi')]),
        '<|im_system|>system<|im_middle|>'
        'You are Kimi, an AI assistant created by Moonshot AI.<|im_end|>'
        '<|im_user|>user<|im_middle|>Hi<|im_end|>'
        '<|im_assistant|>assistant<|im_middle|>',
      );
      expect(
        const KimiTemplate(
          defaultSystemPrompt: null,
        ).format(const [ChatMessage.user('Hi')], addGenerationPrompt: noGen),
        '<|im_user|>user<|im_middle|>Hi<|im_end|>',
      );
    });

    test('renders tool calls and results', () {
      expect(
        const KimiTemplate(defaultSystemPrompt: null).format(const [
          ChatMessage.assistant(
            '',
            toolCalls: [
              ToolCall('w', {'c': 'Oslo'}),
            ],
          ),
          ChatMessage.tool('rain', name: 'functions.w:0'),
        ], addGenerationPrompt: noGen),
        '<|im_assistant|>assistant<|im_middle|>'
        '<|tool_calls_section_begin|><|tool_call_begin|>functions.w:0'
        '<|tool_call_argument_begin|>{"c":"Oslo"}<|tool_call_end|>'
        '<|tool_calls_section_end|><|im_end|>'
        '<|im_system|>tool<|im_middle|>## Return of functions.w:0\nrain'
        '<|im_end|>',
      );
    });

    test('stop sequences', () {
      expect(const KimiTemplate().stopSequences, contains('<|im_end|>'));
    });
  });

  group('glm', () {
    test('formats turns', () {
      expect(
        const GlmTemplate().format(conversation),
        '[gMASK]<sop><|system|>\nBe brief.<|user|>\nHi'
        '<|assistant|>\nHello<|user|>\nBye<|assistant|>',
      );
    });

    test('bos can be disabled and tool results are observations', () {
      expect(
        const GlmTemplate(
          addBos: false,
        ).format(const [ChatMessage.tool('42')], addGenerationPrompt: noGen),
        '<|observation|>\n42',
      );
    });

    test('stops on the next role', () {
      expect(
        const GlmTemplate().stopSequences,
        containsAll(['<|user|>', '<|observation|>']),
      );
    });
  });

  group('qwen', () {
    test('plain conversation matches ChatML', () {
      expect(
        const QwenTemplate().format(conversation),
        const ChatMlTemplate().format(conversation),
      );
    });

    test('non-thinking mode prefills an empty think block', () {
      expect(
        const QwenTemplate(
          enableThinking: false,
        ).format(const [ChatMessage.user('Hi')]),
        '<|im_start|>user\nHi<|im_end|>\n'
        '<|im_start|>assistant\n<think>\n\n</think>\n\n',
      );
    });

    test('thinking mode adds nothing after the assistant header', () {
      expect(
        const QwenTemplate().format(const [ChatMessage.user('Hi')]),
        endsWith('<|im_start|>assistant\n'),
      );
    });

    test('drops reasoning from earlier assistant turns only', () {
      final out = const QwenTemplate().format(const [
        ChatMessage.user('a'),
        ChatMessage.assistant('<think>\nhmm\n</think>\n\nold'),
        ChatMessage.user('b'),
        ChatMessage.assistant('<think>\nnew\n</think>\n\nanswer'),
      ], addGenerationPrompt: noGen);
      expect(
        out,
        '<|im_start|>user\na<|im_end|>\n'
        '<|im_start|>assistant\nold<|im_end|>\n'
        '<|im_start|>user\nb<|im_end|>\n'
        '<|im_start|>assistant\n<think>\nnew\n</think>\n\nanswer<|im_end|>\n',
      );
    });

    test('consecutive tool results share one user turn', () {
      expect(
        const QwenTemplate().format(const [
          ChatMessage.user('q'),
          ChatMessage.tool('a'),
          ChatMessage.tool('b'),
        ], addGenerationPrompt: noGen),
        '<|im_start|>user\nq<|im_end|>\n'
        '<|im_start|>user\n<tool_response>\na\n</tool_response>'
        '\n<tool_response>\nb\n</tool_response><|im_end|>\n',
      );
    });

    test('no_think soft switch passes through untouched', () {
      expect(
        const QwenTemplate().format(const [
          ChatMessage.user('Hi /no_think'),
        ], addGenerationPrompt: noGen),
        '<|im_start|>user\nHi /no_think<|im_end|>\n',
      );
    });
  });

  group('deepseek', () {
    test('strips reasoning from assistant history', () {
      expect(
        const DeepSeekTemplate().format(const [
          ChatMessage.user('a'),
          ChatMessage.assistant('<think>\nhmm\n</think>\n\nanswer'),
          ChatMessage.user('b'),
        ]),
        '<｜begin▁of▁sentence｜>'
        '<｜User｜>a'
        '<｜Assistant｜>\n\nanswer<｜end▁of▁sentence｜>'
        '<｜User｜>b<｜Assistant｜>',
      );
    });

    test('joins system messages after the bos', () {
      expect(
        const DeepSeekTemplate().format(const [
          ChatMessage.system('one'),
          ChatMessage.system('two'),
          ChatMessage.user('x'),
        ], addGenerationPrompt: noGen),
        '<｜begin▁of▁sentence｜>one\n\ntwo<｜User｜>x',
      );
    });

    test('prefillThink opens the reasoning block', () {
      expect(
        const DeepSeekTemplate(
          addBos: false,
          prefillThink: true,
        ).format(const [ChatMessage.user('x')]),
        '<｜User｜>x<｜Assistant｜><think>\n',
      );
    });
  });

  group('smollm', () {
    test('smollm2 adds the default system prompt', () {
      expect(
        const SmolLmTemplate().format(const [ChatMessage.user('Hi')]),
        '<|im_start|>system\n'
        'You are a helpful AI assistant named SmolLM, trained by Hugging Face'
        '<|im_end|>\n'
        '<|im_start|>user\nHi<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
    });

    test('smollm2 keeps a given system prompt', () {
      expect(
        const SmolLmTemplate().format(
          conversation.take(2).toList(),
          addGenerationPrompt: noGen,
        ),
        '<|im_start|>system\nBe brief.<|im_end|>\n'
        '<|im_start|>user\nHi<|im_end|>\n',
      );
    });

    test('smollm3 thinking mode', () {
      expect(
        SmolLm3Template(date: DateTime(2025, 6, 28)).format(conversation),
        '<|im_start|>system\n## Metadata\n\n'
        'Knowledge Cutoff Date: June 2025\n'
        'Today Date: 28 June 2025\n'
        'Reasoning Mode: /think\n\n'
        '## Custom Instructions\n\nBe brief.\n\n<|im_end|>\n'
        '<|im_start|>user\nHi<|im_end|>\n'
        '<|im_start|>assistant\nHello<|im_end|>\n'
        '<|im_start|>user\nBye<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
    });

    test('smollm3 no_think mode prefills an empty think block', () {
      final out = SmolLm3Template(
        enableThinking: false,
        date: DateTime(2025, 6, 28),
      ).format(conversation);
      expect(out, contains('Reasoning Mode: /no_think'));
      expect(
        out,
        contains('<|im_start|>assistant\n<think>\n\n</think>\nHello<|im_end|>'),
      );
      expect(out, endsWith('<|im_start|>assistant\n<think>\n\n</think>\n'));
    });
  });

  group('liquid', () {
    test('formats turns with bos', () {
      expect(
        const LiquidTemplate().format(conversation),
        '<|startoftext|><|im_start|>system\nBe brief.<|im_end|>\n'
        '<|im_start|>user\nHi<|im_end|>\n'
        '<|im_start|>assistant\nHello<|im_end|>\n'
        '<|im_start|>user\nBye<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
    });

    test('renders pythonic tool calls and tool role', () {
      expect(
        const LiquidTemplate(addBos: false).format(const [
          ChatMessage.assistant(
            '',
            toolCalls: [
              ToolCall('w', {'c': "O'slo", 'n': 2, 'on': true}),
            ],
          ),
          ChatMessage.tool('rain'),
        ], addGenerationPrompt: noGen),
        "<|im_start|>assistant\n<|tool_call_start|>[w(c='O\\'slo', n=2, on=True)]"
        '<|tool_call_end|><|im_end|>\n'
        '<|im_start|>tool\nrain<|im_end|>\n',
      );
    });
  });

  group('granite', () {
    test('formats turns', () {
      expect(
        const GraniteTemplate().format(conversation),
        '<|start_of_role|>system<|end_of_role|>Be brief.<|end_of_text|>\n'
        '<|start_of_role|>user<|end_of_role|>Hi<|end_of_text|>\n'
        '<|start_of_role|>assistant<|end_of_role|>Hello<|end_of_text|>\n'
        '<|start_of_role|>user<|end_of_role|>Bye<|end_of_text|>\n'
        '<|start_of_role|>assistant<|end_of_role|>',
      );
    });

    test('tool calls and responses', () {
      expect(
        const GraniteTemplate().format(const [
          ChatMessage.assistant(
            '',
            toolCalls: [
              ToolCall('w', {'c': 'Oslo'}),
            ],
          ),
          ChatMessage.tool('rain'),
        ], addGenerationPrompt: noGen),
        '<|start_of_role|>assistant<|end_of_role|>'
        '<|tool_call|>[{"name":"w","arguments":{"c":"Oslo"}}]'
        '<|end_of_text|>\n'
        '<|start_of_role|>tool_response<|end_of_role|>rain<|end_of_text|>\n',
      );
    });

    test('stop sequence', () {
      expect(const GraniteTemplate().stopSequences, ['<|end_of_text|>']);
    });
  });

  group('cohere', () {
    test('formats turns', () {
      expect(
        const CohereTemplate().format(conversation),
        '<BOS_TOKEN>'
        '<|START_OF_TURN_TOKEN|><|SYSTEM_TOKEN|>Be brief.<|END_OF_TURN_TOKEN|>'
        '<|START_OF_TURN_TOKEN|><|USER_TOKEN|>Hi<|END_OF_TURN_TOKEN|>'
        '<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>Hello<|END_OF_TURN_TOKEN|>'
        '<|START_OF_TURN_TOKEN|><|USER_TOKEN|>Bye<|END_OF_TURN_TOKEN|>'
        '<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>',
      );
    });

    test('stop sequence and bos switch', () {
      expect(const CohereTemplate().stopSequences, ['<|END_OF_TURN_TOKEN|>']);
      expect(
        const CohereTemplate(addBos: false).format(const []),
        '<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>',
      );
    });
  });

  group('olmo', () {
    test('olmo2 formats turns', () {
      expect(
        const Olmo2Template().format(conversation),
        '<|endoftext|>'
        '<|system|>\nBe brief.\n'
        '<|user|>\nHi\n'
        '<|assistant|>\nHello<|endoftext|>\n'
        '<|user|>\nBye\n'
        '<|assistant|>\n',
      );
    });

    test('olmo3 is ChatML with an environment role', () {
      expect(
        const Olmo3Template().format(const [
          ChatMessage.user('Hi'),
          ChatMessage.tool('ok'),
        ]),
        '<|im_start|>user\nHi<|im_end|>\n'
        '<|im_start|>environment\nok<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
    });
  });

  group('internlm', () {
    test('formats turns with bos', () {
      expect(
        const InternLmTemplate().format(conversation.take(2).toList()),
        '<s><|im_start|>system\nBe brief.<|im_end|>\n'
        '<|im_start|>user\nHi<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
    });

    test('stops and bos switch', () {
      expect(
        const InternLmTemplate().stopSequences,
        containsAll(['<|im_end|>', '</s>']),
      );
      expect(
        const InternLmTemplate(addBos: false).format(const []),
        '<|im_start|>assistant\n',
      );
    });
  });

  test('minicpm and yi are ChatML', () {
    final chatMl = const ChatMlTemplate().format(conversation);
    expect(const MiniCpmTemplate().format(conversation), chatMl);
    expect(const YiTemplate().format(conversation), chatMl);
    expect(const YiTemplate().stopSequences, ['<|im_end|>']);
  });

  group('gpt-oss', () {
    final template = GptOssTemplate(date: DateTime(2025, 6, 28));
    const system =
        '<|start|>system<|message|>'
        'You are ChatGPT, a large language model trained by OpenAI.\n'
        'Knowledge cutoff: 2024-06\n'
        'Current date: 2025-06-28\n\n'
        'Reasoning: medium\n\n'
        '# Valid channels: analysis, commentary, final. '
        'Channel must be included for every message.<|end|>';

    test('formats harmony turns', () {
      expect(
        template.format(conversation),
        '$system'
        '<|start|>developer<|message|># Instructions\n\nBe brief.\n\n<|end|>'
        '<|start|>user<|message|>Hi<|end|>'
        '<|start|>assistant<|channel|>final<|message|>Hello<|end|>'
        '<|start|>user<|message|>Bye<|end|>'
        '<|start|>assistant',
      );
    });

    test('omits the developer block without system messages', () {
      expect(
        template.format(const [ChatMessage.user('Hi')]),
        '$system<|start|>user<|message|>Hi<|end|><|start|>assistant',
      );
    });

    test('reasoning effort is configurable', () {
      expect(
        GptOssTemplate(
          reasoningEffort: 'high',
          date: DateTime(2025, 6, 28),
        ).format(const []),
        contains('Reasoning: high'),
      );
    });

    test('finalChannelOnly skips the analysis channel', () {
      final t = GptOssTemplate(
        date: DateTime(2025, 6, 28),
        finalChannelOnly: true,
      );
      expect(
        t.format(const [ChatMessage.user('Hi')]),
        endsWith('<|start|>assistant<|channel|>final<|message|>'),
      );
      expect(t.stopSequences, contains('<|end|>'));
      expect(template.stopSequences, isNot(contains('<|end|>')));
      expect(template.stopSequences, containsAll(['<|return|>', '<|call|>']));
    });

    test('tool calls and results', () {
      expect(
        template.format(const [
          ChatMessage.assistant(
            '',
            toolCalls: [
              ToolCall('w', {'c': 'Oslo'}),
            ],
          ),
          ChatMessage.tool('rain', name: 'w'),
        ], addGenerationPrompt: noGen),
        '$system'
        '<|start|>assistant to=functions.w<|channel|>commentary json<|message|>'
        '{"c":"Oslo"}<|call|>'
        '<|start|>functions.w to=assistant<|channel|>commentary<|message|>'
        '"rain"<|end|>',
      );
    });
  });
}
