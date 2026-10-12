import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../../config.dart';
import '../base_inference_engine.dart';

/// Smallest context window LiteRT-LM accepts for `.litertlm` models.
const litertMinContextTokens = 1024;

/// Context window used when the config does not specify one.
const litertDefaultContextTokens = 2048;

/// Picks the flutter_edge_ai runtime from the file extension. The file type
/// decides which native engine runs the model.
ModelFileType litertFileTypeFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.litertlm')) return ModelFileType.litertlm;
  if (lower.endsWith('.task')) return ModelFileType.task;
  return ModelFileType.binary;
}

/// Maps the toolkit's [ModelFamily] to flutter_edge_ai's [ModelType], which
/// selects chat template and default sampling. [path] distinguishes Gemma 4
/// (native tool tokens) from earlier Gemma generations.
ModelType litertModelTypeFor(ModelFamily family, {String path = ''}) {
  final name = path.toLowerCase();
  return switch (family) {
    ModelFamily.gemma =>
      name.contains('gemma-4') || name.contains('gemma4')
          ? ModelType.gemma4
          : name.contains('functiongemma')
          ? ModelType.functionGemma
          : ModelType.gemmaIt,
    ModelFamily.deepSeek => ModelType.deepSeek,
    ModelFamily.qwen =>
      name.contains('qwen3.5') || name.contains('qwen35')
          ? ModelType.qwen35
          : name.contains('qwen3')
          ? ModelType.qwen3
          : ModelType.qwen,
    ModelFamily.llama => ModelType.llama,
    ModelFamily.phi => ModelType.phi,
    _ => ModelType.general,
  };
}

/// Maps [ComputeBackend] to [PreferredBackend]; null leaves the choice to the
/// runtime.
PreferredBackend? litertBackendFor(ComputeBackend? backend) =>
    switch (backend) {
      null => null,
      ComputeBackend.cpu => PreferredBackend.cpu,
      ComputeBackend.gpu => PreferredBackend.gpu,
      ComputeBackend.npu => PreferredBackend.npu,
    };

/// Full context window (prompt + history + reply) for the model. LiteRT-LM
/// rejects windows below [litertMinContextTokens].
int litertContextWindow(InferenceConfig config, ModelFileType fileType) {
  final requested =
      config.contextSize ?? config.maxTokens ?? litertDefaultContextTokens;
  return fileType == ModelFileType.litertlm &&
          requested < litertMinContextTokens
      ? litertMinContextTokens
      : requested;
}

/// Converts [GenerationParams] into the sampling flutter_edge_ai accepts,
/// clamping values to the ranges it validates.
SamplingParams litertSamplingFor(GenerationParams params) => SamplingParams(
  temperature: params.temperature < 0 ? 0 : params.temperature,
  topK: params.topK < 1 ? 1 : params.topK,
  topP: params.topP <= 0 ? null : (params.topP > 1 ? 1 : params.topP),
  randomSeed: params.seed,
);

/// Output cap for one reply, never larger than the [contextWindow].
int litertMaxOutputTokens(GenerationParams params, int contextWindow) =>
    params.maxTokens.clamp(1, contextWindow);

/// A chat transcript split for LiteRT: the system prompt goes into the
/// session, the rest is replayed as messages.
typedef LitertTranscript = ({String? system, List<Message> messages});

/// Converts [turns] into a [LitertTranscript]. Tool turns are sent from the
/// user side. Throws [ArgumentError] unless the final turn is from the user.
LitertTranscript litertTranscriptFrom(List<ChatTurn> turns) {
  final system = turns
      .where((t) => t.role == 'system')
      .map((t) => t.content)
      .join('\n\n');
  final messages = [
    for (final t in turns)
      if (t.role != 'system') litertMessageFrom(t),
  ];
  if (messages.isEmpty || !messages.last.isUser) {
    throw ArgumentError.value(
      turns,
      'turns',
      'must end with a user (or tool) turn',
    );
  }
  return (system: system.isEmpty ? null : system, messages: messages);
}

/// Converts one [ChatTurn]. `Message.isUser` defaults to false, so it is set
/// explicitly.
Message litertMessageFrom(ChatTurn turn) {
  final isUser = turn.role != 'assistant';
  return switch (turn.images) {
    [] => Message.text(text: turn.content, isUser: isUser),
    final images => Message.withImages(
      text: turn.content,
      imageBytes: images,
      isUser: isUser,
    ),
  };
}

/// Ends [source] at the first occurrence of any of [stops], holding back only
/// as many trailing characters as could still start a stop sequence.
Stream<String> litertApplyStopSequences(
  Stream<String> source,
  List<String> stops,
) async* {
  final active = stops.where((s) => s.isNotEmpty).toList();
  if (active.isEmpty) {
    yield* source;
    return;
  }
  final holdBack =
      active.map((s) => s.length).reduce((a, b) => a > b ? a : b) - 1;
  var pending = '';
  await for (final chunk in source) {
    pending += chunk;
    var cut = -1;
    for (final s in active) {
      final i = pending.indexOf(s);
      if (i != -1 && (cut == -1 || i < cut)) cut = i;
    }
    if (cut != -1) {
      if (cut > 0) yield pending.substring(0, cut);
      return;
    }
    if (pending.length > holdBack) {
      yield pending.substring(0, pending.length - holdBack);
      pending = pending.substring(pending.length - holdBack);
    }
  }
  if (pending.isNotEmpty) yield pending;
}
