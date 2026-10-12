import '../../core/config.dart';
import '../prompt_template.dart';

/// Picks a template from the Jinja source in a GGUF `tokenizer.chat_template`
/// by looking for each format's distinctive tokens. Returns null when nothing
/// matches. [familyHint] disambiguates ChatML-style templates.
PromptTemplate? matchGgufTemplate(String jinja, ModelFamily? familyHint) {
  bool has(String s) => jinja.contains(s);

  if (has('<|start|>') && has('<|message|>')) return GptOssTemplate();
  if (has('<|im_system|>')) return const KimiTemplate();
  if (has('[gMASK]')) return const GlmTemplate();
  if (has('<|START_OF_TURN_TOKEN|>')) return const CohereTemplate();
  if (has('<|start_of_role|>')) return const GraniteTemplate();
  if (has('<｜User｜>') || has('<|User|>')) return const DeepSeekTemplate();
  if (has('<start_of_turn>')) return const GemmaTemplate();
  if (has('<|start_header_id|>')) return const Llama3Template();
  if (has('<|im_sep|>')) return null;
  if (has('<|im_start|>')) return _chatMlFlavour(jinja, familyHint);
  if (has('[INST]')) return const MistralTemplate();
  if (has('<|end|>') && has('<|user|>')) return const Phi3Template();
  if (has('<|user|>') &&
      has('<|assistant|>') &&
      (has('<|endoftext|>') || familyHint == ModelFamily.olmo)) {
    return const Olmo2Template();
  }
  return null;
}

PromptTemplate _chatMlFlavour(String jinja, ModelFamily? hint) {
  if (jinja.contains('/system_override') || jinja.contains('Reasoning Mode')) {
    return SmolLm3Template();
  }
  if (jinja.contains('<|tool_call_start|>') ||
      jinja.contains('<|startoftext|>') ||
      hint == ModelFamily.liquid) {
    return const LiquidTemplate();
  }
  if (hint != null) {
    switch (hint) {
      case ModelFamily.qwen:
        return const QwenTemplate();
      case ModelFamily.smolLm:
        return const SmolLmTemplate();
      case ModelFamily.internLm:
        return const InternLmTemplate();
      case ModelFamily.miniCpm:
        return const MiniCpmTemplate();
      case ModelFamily.yi:
        return const YiTemplate();
      case ModelFamily.olmo:
        return const Olmo3Template();
      default:
        break;
    }
  }
  if (jinja.contains('<tool_call>') ||
      jinja.contains('<tool_response>') ||
      jinja.contains('enable_thinking')) {
    return const QwenTemplate();
  }
  return const ChatMlTemplate();
}
