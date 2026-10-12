import '../core/config.dart';
import '../core/model_detector.dart';
import 'chat_message.dart';
import 'templates/chatml_templates.dart';
import 'templates/classic_templates.dart';
import 'templates/deepseek_template.dart';
import 'templates/gguf_matcher.dart';
import 'templates/vendor_templates.dart';

export 'templates/chatml_templates.dart';
export 'templates/classic_templates.dart';
export 'templates/deepseek_template.dart';
export 'templates/vendor_templates.dart';

/// Turns a message list into the raw prompt string a model family expects.
abstract class PromptTemplate {
  const PromptTemplate();

  /// Template for the model [family]; unknown families get ChatML.
  ///
  /// Families that span incompatible generations get the most common one
  /// (SmolLM2, GLM-4 0414, OLMo 3). Use [forModelName] or [fromGgufTemplate]
  /// to tell them apart.
  factory PromptTemplate.forFamily(ModelFamily family) => switch (family) {
    ModelFamily.generic => const ChatMlTemplate(),
    ModelFamily.gemma => const GemmaTemplate(),
    ModelFamily.deepSeek => const DeepSeekTemplate(),
    ModelFamily.qwen => const QwenTemplate(),
    ModelFamily.llama => const Llama3Template(),
    ModelFamily.phi => const Phi3Template(),
    ModelFamily.mistral => const MistralTemplate(),
    ModelFamily.kimi => const KimiTemplate(),
    ModelFamily.glm => const GlmTemplate(),
    ModelFamily.smolLm => const SmolLmTemplate(),
    ModelFamily.liquid => const LiquidTemplate(),
    ModelFamily.granite => const GraniteTemplate(),
    ModelFamily.cohere => const CohereTemplate(),
    ModelFamily.olmo => const Olmo3Template(),
    ModelFamily.internLm => const InternLmTemplate(),
    ModelFamily.miniCpm => const MiniCpmTemplate(),
    ModelFamily.yi => const YiTemplate(),
    ModelFamily.openAiOss => GptOssTemplate(),
  };

  /// Template for a model file or repo name, e.g. `SmolLM3-3B-Q4_K_M.gguf`.
  /// Unknown names get ChatML.
  static PromptTemplate forModelName(String modelName) {
    final n = modelName.toLowerCase();
    if (n.contains('smollm3')) return SmolLm3Template();
    if (RegExp(r'olmo-?2').hasMatch(n)) return const Olmo2Template();
    return PromptTemplate.forFamily(ModelDetector.instance.detectFamily(n));
  }

  /// Guesses the template from the Jinja source stored in a GGUF file's
  /// `tokenizer.chat_template`, or returns null if the format is not
  /// recognised. [familyHint] resolves ChatML-style templates that differ only
  /// by model (Qwen, InternLM, Yi, ...).
  static PromptTemplate? fromGgufTemplate(
    String jinjaChatTemplate, {
    ModelFamily? familyHint,
  }) => matchGgufTemplate(jinjaChatTemplate, familyHint);

  String get name;

  /// Strings that mark the end of an assistant turn.
  List<String> get stopSequences;

  /// Renders [messages]. With [addGenerationPrompt] the result ends with the
  /// opening of an assistant turn so the model continues from there.
  String format(List<ChatMessage> messages, {bool addGenerationPrompt = true});
}
