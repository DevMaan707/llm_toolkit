import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../exceptions/llm_toolkit_exceptions.dart';
import 'sherpa_layout.dart';

/// Builds the synthesizer configuration for [layout].
///
/// [vocoder] supplies the Matcha vocoder when it is not in the model folder;
/// [lang] is the optional Kokoro language hint (e.g. `en-us`).
sherpa.OfflineTtsConfig buildTtsConfig(
  SherpaTtsLayout layout, {
  required int numThreads,
  String provider = 'cpu',
  String? vocoder,
  String lang = '',
}) {
  final model = switch (layout.architecture) {
    SherpaTtsArchitecture.vits => sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: layout.model,
        tokens: layout.tokens,
        lexicon: layout.lexicon,
        dataDir: layout.dataDir,
      ),
      numThreads: numThreads,
      provider: provider,
      debug: false,
    ),
    SherpaTtsArchitecture.kokoro => sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: layout.model,
        voices: layout.voices,
        tokens: layout.tokens,
        dataDir: layout.dataDir,
        lexicon: layout.lexicon,
        lang: lang,
      ),
      numThreads: numThreads,
      provider: provider,
      debug: false,
    ),
    SherpaTtsArchitecture.kitten => sherpa.OfflineTtsModelConfig(
      kitten: sherpa.OfflineTtsKittenModelConfig(
        model: layout.model,
        voices: layout.voices,
        tokens: layout.tokens,
        dataDir: layout.dataDir,
      ),
      numThreads: numThreads,
      provider: provider,
      debug: false,
    ),
    SherpaTtsArchitecture.matcha => () {
      final voc = vocoder ?? layout.vocoder;
      if (voc.isEmpty) {
        throw const InferenceException(
          'Matcha needs a vocoder: put it in the model folder or pass '
          'InferenceConfig.extra["vocoder"]',
        );
      }
      return sherpa.OfflineTtsModelConfig(
        matcha: sherpa.OfflineTtsMatchaModelConfig(
          acousticModel: layout.model,
          vocoder: voc,
          tokens: layout.tokens,
          lexicon: layout.lexicon,
          dataDir: layout.dataDir,
        ),
        numThreads: numThreads,
        provider: provider,
        debug: false,
      );
    }(),
  };
  return sherpa.OfflineTtsConfig(model: model, ruleFsts: layout.ruleFsts);
}
