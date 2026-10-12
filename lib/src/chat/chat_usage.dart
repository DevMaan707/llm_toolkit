/// Token and timing statistics for one generation. Token counts are estimates
/// unless a precise counter was injected into the session.
class ChatUsage {
  final int promptTokens;
  final int completionTokens;

  /// Time from request to the first streamed chunk (null if none arrived).
  final Duration? timeToFirstToken;

  /// Wall-clock time of the whole generation.
  final Duration totalTime;

  const ChatUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.timeToFirstToken,
    this.totalTime = Duration.zero,
  });

  int get totalTokens => promptTokens + completionTokens;

  /// Decode speed after the first token; null when it can't be measured.
  double? get tokensPerSecond {
    final decode = totalTime - (timeToFirstToken ?? Duration.zero);
    if (completionTokens < 2 || decode <= Duration.zero) return null;
    return (completionTokens - 1) / (decode.inMicroseconds / 1e6);
  }

  @override
  String toString() =>
      'ChatUsage(prompt: $promptTokens, completion: $completionTokens, '
      'ttft: $timeToFirstToken, tok/s: $tokensPerSecond)';
}
