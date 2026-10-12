import 'package:flutter_test/flutter_test.dart';
import 'package:llm_toolkit/src/chat/prompt_template.dart';
import 'package:llm_toolkit/src/core/config.dart';

void main() {
  PromptTemplate? match(String jinja, {ModelFamily? hint}) =>
      PromptTemplate.fromGgufTemplate(jinja, familyHint: hint);

  const chatMl =
      "{% for message in messages %}{{'<|im_start|>' + message['role'] + '\\n' "
      "+ message['content'] + '<|im_end|>' + '\\n'}}{% endfor %}"
      "{% if add_generation_prompt %}{{ '<|im_start|>assistant\\n' }}{% endif %}";

  test('chatml', () {
    expect(match(chatMl), isA<ChatMlTemplate>());
    expect(match(chatMl)!.name, 'chatml');
  });

  test('chatml with a family hint', () {
    expect(match(chatMl, hint: ModelFamily.yi), isA<YiTemplate>());
    expect(match(chatMl, hint: ModelFamily.internLm), isA<InternLmTemplate>());
    expect(match(chatMl, hint: ModelFamily.miniCpm), isA<MiniCpmTemplate>());
    expect(match(chatMl, hint: ModelFamily.smolLm), isA<SmolLmTemplate>());
    expect(match(chatMl, hint: ModelFamily.olmo), isA<Olmo3Template>());
    expect(match(chatMl, hint: ModelFamily.qwen), isA<QwenTemplate>());
    expect(match(chatMl, hint: ModelFamily.llama), isA<ChatMlTemplate>());
  });

  test('qwen3 markers', () {
    const jinja =
        '{%- if tools %}<|im_start|>system ... <tools></tools> ... '
        '<tool_call>\\n{"name": <function-name>}\\n</tool_call><|im_end|>'
        "{%- endif %}{%- if enable_thinking is defined and enable_thinking is false %}"
        "{{- '<think>\\n\\n</think>\\n\\n' }}{%- endif %}<|im_start|>";
    expect(match(jinja), isA<QwenTemplate>());
  });

  test('llama 3', () {
    const jinja =
        "{% set loop_messages = messages %}{% for message in loop_messages %}"
        "{% set content = '<|start_header_id|>' + message['role'] + "
        "'<|end_header_id|>\\n\\n'+ message['content'] | trim + '<|eot_id|>' %}"
        "{{ content }}{% endfor %}";
    expect(match(jinja), isA<Llama3Template>());
  });

  test('gemma', () {
    const jinja =
        "{{ bos_token }}{% for message in messages %}"
        "{{ '<start_of_turn>' + role + '\\n' + message['content'] | trim + "
        "'<end_of_turn>\\n' }}{% endfor %}";
    expect(match(jinja), isA<GemmaTemplate>());
  });

  test('mistral and llama 2', () {
    const jinja =
        "{{ bos_token }}{% for message in messages %}{% if message['role'] == "
        "'user' %}{{ '[INST] ' + message['content'] + ' [/INST]' }}"
        "{% elif message['role'] == 'assistant' %}"
        "{{ ' ' + message['content'] + eos_token}}{% endif %}{% endfor %}";
    expect(match(jinja), isA<MistralTemplate>());
  });

  test('phi 3', () {
    const jinja =
        "{% for message in messages %}{% if message['role'] == 'system' %}"
        "{{'<|system|>\\n' + message['content'] + '<|end|>\\n'}}"
        "{% elif message['role'] == 'user' %}"
        "{{'<|user|>\\n' + message['content'] + '<|end|>\\n'}}{% endif %}"
        "{% endfor %}{% if add_generation_prompt %}{{ '<|assistant|>\\n' }}"
        '{% endif %}';
    expect(match(jinja), isA<Phi3Template>());
  });

  test('phi 4 style im_sep templates are not guessed', () {
    expect(
      match(
        "{{'<|im_start|>' + role + '<|im_sep|>' + content + '<|im_end|>'}}",
      ),
      isNull,
    );
  });

  test('kimi', () {
    const jinja =
        "{%- macro render_role(m) -%}{%- if m['role'] == 'user' -%}"
        '<|im_user|>{{m.get("name", m["role"])}}<|im_middle|>'
        "{%- elif m['role'] == 'assistant' -%}<|im_assistant|>"
        "{%- else -%}<|im_system|>{%- endif -%}{%- endmacro -%}";
    expect(match(jinja), isA<KimiTemplate>());
  });

  test('glm 4', () {
    const jinja =
        '[gMASK]<sop>{%- if tools -%}<|system|>\\n# Tools{%- endif -%}'
        '{%- for msg in messages %}{%- if msg.role == "user" %}'
        '{{ "<|user|>\\n" + msg.content }}{%- endif %}{%- endfor %}'
        '{%- if add_generation_prompt -%}<|assistant|>{%- endif -%}';
    expect(match(jinja), isA<GlmTemplate>());
  });

  test('granite', () {
    const jinja =
        "{%- for message in messages %}{{- '<|start_of_role|>' + message['role'] "
        "+ '<|end_of_role|>' }}{{- message['content'] + '<|end_of_text|>\\n' }}"
        "{%- endfor %}";
    expect(match(jinja), isA<GraniteTemplate>());
  });

  test('command-r', () {
    const jinja =
        "{{ bos_token }}{% for message in messages %}"
        "{{ '<|START_OF_TURN_TOKEN|><|USER_TOKEN|>' + message['content'] + "
        "'<|END_OF_TURN_TOKEN|>' }}{% endfor %}";
    expect(match(jinja), isA<CohereTemplate>());
  });

  test('deepseek r1', () {
    const jinja =
        "{{bos_token}}{% for message in messages %}{% if message['role'] == "
        "'user' %}{{'<｜User｜>' + message['content']}}{% elif "
        "message['role'] == 'assistant' %}{{'<｜Assistant｜>' + "
        "message['content'] + '<｜end▁of▁sentence｜>'}}{% endif %}{% endfor %}";
    expect(match(jinja), isA<DeepSeekTemplate>());
  });

  test('gpt-oss harmony', () {
    const jinja =
        '{{- "<|start|>system<|message|>" }}{{- "# Valid channels: analysis, '
        'commentary, final." }}{{- "<|end|>" }}'
        '{{- "<|start|>assistant<|channel|>final<|message|>" }}';
    expect(match(jinja), isA<GptOssTemplate>());
  });

  test('smollm3', () {
    const jinja =
        '{%- set enable_thinking = true -%}{{- "## Metadata\\n\\n" }}'
        '{{- "Reasoning Mode: /think" }}{%- if "/system_override" in x %}'
        "{% endif %}<|im_start|><tool_call>";
    expect(match(jinja), isA<SmolLm3Template>());
  });

  test('lfm2', () {
    const jinja =
        '{{- bos_token -}}<|startoftext|>{%- for m in messages -%}'
        "{{- '<|im_start|>' + m['role'] + '\\n' -}}<|tool_call_start|>"
        "<|im_end|>{%- endfor -%}";
    expect(match(jinja), isA<LiquidTemplate>());
  });

  test('olmo 2', () {
    const jinja =
        '{{ bos_token }}{% for message in messages %}'
        "{% if message['role'] == 'user' %}{{ '<|user|>\\n' + content + '\\n' }}"
        "{% elif message['role'] == 'assistant' %}{{ '<|assistant|>\\n' + "
        "content + eos_token + '\\n' }}{% endif %}{% endfor %}";
    expect(match(jinja, hint: ModelFamily.olmo), isA<Olmo2Template>());
    expect(match(jinja), isNull);
  });

  test('unknown formats return null', () {
    expect(match(''), isNull);
    expect(match('{{ messages[0].content }}'), isNull);
  });

  group('forModelName', () {
    test('maps names through the detector', () {
      expect(
        PromptTemplate.forModelName('Qwen3-8B-Q4_K_M.gguf'),
        isA<QwenTemplate>(),
      );
      expect(
        PromptTemplate.forModelName('gemma-3-4b-it.gguf'),
        isA<GemmaTemplate>(),
      );
      expect(
        PromptTemplate.forModelName('Kimi-K2-Instruct'),
        isA<KimiTemplate>(),
      );
      expect(
        PromptTemplate.forModelName('mystery-model'),
        isA<ChatMlTemplate>(),
      );
    });

    test('tells model generations apart', () {
      expect(
        PromptTemplate.forModelName('SmolLM3-3B-Q8_0.gguf'),
        isA<SmolLm3Template>(),
      );
      expect(
        PromptTemplate.forModelName('SmolLM2-1.7B-Instruct'),
        isA<SmolLmTemplate>(),
      );
      expect(
        PromptTemplate.forModelName('OLMo-2-1124-7B-Instruct'),
        isA<Olmo2Template>(),
      );
      expect(
        PromptTemplate.forModelName('Olmo-3-7B-Instruct'),
        isA<Olmo3Template>(),
      );
    });
  });
}
