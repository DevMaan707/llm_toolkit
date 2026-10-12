/// Connection details for a known hosted or local OpenAI-compatible server.
/// API keys are never included; pass your own to the engine.
class RemotePreset {
  final String name;
  final String baseUrl;

  /// Whether the server normally requires an API key.
  final bool requiresApiKey;

  /// Whether the server accepts non-standard sampling fields (`top_k`,
  /// `repeat_penalty`) on `/chat/completions`.
  final bool acceptsExtendedSampling;

  const RemotePreset(
    this.name,
    this.baseUrl, {
    this.requiresApiKey = true,
    this.acceptsExtendedSampling = false,
  });
}

/// Well-known endpoints for [OpenAiCompatibleEngine] and [OllamaEngine].
abstract final class RemoteModelPresets {
  static const openAi = RemotePreset('OpenAI', 'https://api.openai.com/v1');
  static const openRouter = RemotePreset(
    'OpenRouter',
    'https://openrouter.ai/api/v1',
    acceptsExtendedSampling: true,
  );
  static const together = RemotePreset(
    'Together AI',
    'https://api.together.xyz/v1',
    acceptsExtendedSampling: true,
  );
  static const groq = RemotePreset('Groq', 'https://api.groq.com/openai/v1');
  static const deepSeek = RemotePreset(
    'DeepSeek',
    'https://api.deepseek.com/v1',
  );

  /// Moonshot AI (Kimi K2).
  static const moonshot = RemotePreset(
    'Moonshot',
    'https://api.moonshot.ai/v1',
  );

  static const lmStudio = RemotePreset(
    'LM Studio',
    'http://localhost:1234/v1',
    requiresApiKey: false,
    acceptsExtendedSampling: true,
  );
  static const llamaServer = RemotePreset(
    'llama-server',
    'http://localhost:8080/v1',
    requiresApiKey: false,
    acceptsExtendedSampling: true,
  );
  static const vllm = RemotePreset(
    'vLLM',
    'http://localhost:8000/v1',
    requiresApiKey: false,
    acceptsExtendedSampling: true,
  );

  /// Ollama's OpenAI-compatible endpoint. For the native API use
  /// [OllamaEngine] with [ollamaNative].
  static const ollama = RemotePreset(
    'Ollama',
    'http://localhost:11434/v1',
    requiresApiKey: false,
  );
  static const ollamaNativeUrl = 'http://localhost:11434';

  static const ollamaNative = RemotePreset(
    'Ollama',
    ollamaNativeUrl,
    requiresApiKey: false,
  );

  static const all = [
    openAi,
    openRouter,
    together,
    groq,
    deepSeek,
    moonshot,
    lmStudio,
    llamaServer,
    vllm,
    ollama,
  ];
}
