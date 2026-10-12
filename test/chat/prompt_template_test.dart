import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/chat/chat_message.dart';
import 'package:llm_toolkit/src/chat/prompt_template.dart';
import 'package:llm_toolkit/src/core/config.dart';

void main() {
  const conversation = [
    ChatMessage.system('Be brief.'),
    ChatMessage.user('Hi'),
    ChatMessage.assistant('Hello'),
    ChatMessage.user('Bye'),
  ];

  test('chatml', () {
    expect(
      const ChatMlTemplate().format(conversation),
      '<|im_start|>system\nBe brief.<|im_end|>\n'
      '<|im_start|>user\nHi<|im_end|>\n'
      '<|im_start|>assistant\nHello<|im_end|>\n'
      '<|im_start|>user\nBye<|im_end|>\n'
      '<|im_start|>assistant\n',
    );
  });

  test('chatml without generation prompt', () {
    expect(
      const ChatMlTemplate().format([
        const ChatMessage.user('Hi'),
      ], addGenerationPrompt: false),
      '<|im_start|>user\nHi<|im_end|>\n',
    );
  });

  test('qwen wraps tool results and renders tool calls', () {
    final out = const QwenTemplate().format([
      const ChatMessage.user('weather?'),
      const ChatMessage.assistant(
        '',
        toolCalls: [
          ToolCall('w', {'c': 'Oslo'}),
        ],
      ),
      const ChatMessage.tool('rain', name: 'w'),
    ]);
    expect(
      out,
      '<|im_start|>user\nweather?<|im_end|>\n'
      '<|im_start|>assistant\n<tool_call>\n{"name":"w","arguments":{"c":"Oslo"}}'
      '\n</tool_call><|im_end|>\n'
      '<|im_start|>user\n<tool_response>\nrain\n</tool_response><|im_end|>\n'
      '<|im_start|>assistant\n',
    );
  });

  test('llama3', () {
    expect(
      const Llama3Template().format(conversation),
      '<|begin_of_text|>'
      '<|start_header_id|>system<|end_header_id|>\n\nBe brief.<|eot_id|>'
      '<|start_header_id|>user<|end_header_id|>\n\nHi<|eot_id|>'
      '<|start_header_id|>assistant<|end_header_id|>\n\nHello<|eot_id|>'
      '<|start_header_id|>user<|end_header_id|>\n\nBye<|eot_id|>'
      '<|start_header_id|>assistant<|end_header_id|>\n\n',
    );
    expect(
      const Llama3Template(addBos: false).format(conversation),
      isNot(startsWith('<|begin_of_text|>')),
    );
  });

  test('gemma folds system into first user turn', () {
    expect(
      const GemmaTemplate().format(conversation),
      '<bos><start_of_turn>user\nBe brief.\n\nHi<end_of_turn>\n'
      '<start_of_turn>model\nHello<end_of_turn>\n'
      '<start_of_turn>user\nBye<end_of_turn>\n'
      '<start_of_turn>model\n',
    );
  });

  test('mistral', () {
    expect(
      const MistralTemplate().format(conversation),
      '<s>[INST] Be brief.\n\nHi [/INST] Hello</s>[INST] Bye [/INST]',
    );
  });

  test('phi3', () {
    expect(
      const Phi3Template().format(conversation),
      '<|system|>\nBe brief.<|end|>\n'
      '<|user|>\nHi<|end|>\n'
      '<|assistant|>\nHello<|end|>\n'
      '<|user|>\nBye<|end|>\n'
      '<|assistant|>\n',
    );
  });

  test('deepseek', () {
    expect(
      const DeepSeekTemplate().format(conversation),
      '<｜begin▁of▁sentence｜>Be brief.'
      '<｜User｜>Hi'
      '<｜Assistant｜>Hello<｜end▁of▁sentence｜>'
      '<｜User｜>Bye<｜Assistant｜>',
    );
  });

  test('forFamily maps every family', () {
    final names = {
      for (final f in ModelFamily.values) f: PromptTemplate.forFamily(f).name,
    };
    expect(names, {
      ModelFamily.generic: 'chatml',
      ModelFamily.gemma: 'gemma',
      ModelFamily.deepSeek: 'deepseek',
      ModelFamily.qwen: 'qwen',
      ModelFamily.llama: 'llama3',
      ModelFamily.phi: 'phi3',
      ModelFamily.mistral: 'mistral',
      ModelFamily.kimi: 'kimi',
      ModelFamily.glm: 'glm4',
      ModelFamily.smolLm: 'smollm',
      ModelFamily.liquid: 'lfm2',
      ModelFamily.granite: 'granite',
      ModelFamily.cohere: 'cohere',
      ModelFamily.olmo: 'olmo3',
      ModelFamily.internLm: 'internlm',
      ModelFamily.miniCpm: 'minicpm',
      ModelFamily.yi: 'yi',
      ModelFamily.openAiOss: 'gpt-oss',
    });
  });

  test('stop sequences', () {
    expect(const ChatMlTemplate().stopSequences, ['<|im_end|>']);
    expect(const Llama3Template().stopSequences, contains('<|eot_id|>'));
    expect(const GemmaTemplate().stopSequences, ['<end_of_turn>']);
    expect(const MistralTemplate().stopSequences, contains('</s>'));
    expect(const Phi3Template().stopSequences, contains('<|end|>'));
    expect(const QwenTemplate().stopSequences, contains('<|endoftext|>'));
    expect(const DeepSeekTemplate().stopSequences, hasLength(1));
  });
}
