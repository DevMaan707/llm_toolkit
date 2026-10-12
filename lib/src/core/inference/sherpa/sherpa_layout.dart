import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../exceptions/llm_toolkit_exceptions.dart';

/// Which files in a sherpa model folder play which part.
enum SherpaFileRole {
  encoder,
  decoder,
  joiner,
  model,
  preprocessor,
  uncachedDecoder,
  cachedDecoder,
  mergedDecoder,
  vocoder,
}

/// Speech recognition model families this toolkit can configure.
enum SherpaAsrArchitecture {
  whisper,
  moonshine,

  /// Offline encoder/decoder/joiner (NeMo Parakeet TDT, Zipformer, ...).
  transducer,
  nemoCtc,
  zipformerCtc,
  senseVoice,
  paraformer,
  streamingTransducer,
  streamingParaformer,
  streamingZipformerCtc,
  streamingNemoCtc;

  /// Needs the online (streaming) recognizer instead of the offline one.
  bool get isStreaming => switch (this) {
    streamingTransducer ||
    streamingParaformer ||
    streamingZipformerCtc ||
    streamingNemoCtc => true,
    _ => false,
  };
}

/// Speech synthesis model families this toolkit can configure.
enum SherpaTtsArchitecture { vits, kokoro, kitten, matcha }

/// What [SherpaModelLayout.detect] found in a model folder.
sealed class SherpaModelLayout {
  /// The model folder.
  final String directory;

  /// Path of the `tokens.txt` file.
  final String tokens;

  const SherpaModelLayout(this.directory, this.tokens);

  /// Inspects [dir] and returns a speech recognition or synthesis layout.
  ///
  /// With [preferInt8], quantised files win over full precision ones when a
  /// folder ships both. [streaming] overrides the detection of online models (a
  /// `streaming` or `chunk-` name hint, or chunk metadata in the encoder).
  ///
  /// Throws [InferenceException] when the folder is missing, has no
  /// `tokens.txt`, or matches no known architecture.
  static SherpaModelLayout detect(
    Directory dir, {
    bool preferInt8 = true,
    bool? streaming,
  }) {
    if (!dir.existsSync()) {
      throw InferenceException('Sherpa model folder not found: ${dir.path}');
    }
    final entries = dir.listSync(followLinks: false);
    final dirName = p.basename(dir.path).toLowerCase();
    final models = <String>[];
    var tokens = '';
    var hasEspeakData = false;
    var hasVoices = false;
    for (final e in entries) {
      final name = p.basename(e.path).toLowerCase();
      if (e is Directory) {
        hasEspeakData |= name == 'espeak-ng-data';
      } else if (name.endsWith('.onnx') || name.endsWith('.ort')) {
        if (!name.contains('silero')) models.add(e.path);
      } else if (name == 'tokens.txt' ||
          (tokens.isEmpty && name.endsWith('-tokens.txt'))) {
        tokens = e.path;
      } else if (name == 'voices.bin') {
        hasVoices = true;
      }
    }
    if (tokens.isEmpty) {
      throw InferenceException('No tokens.txt in sherpa folder ${dir.path}');
    }
    if (models.isEmpty) {
      throw InferenceException('No .onnx files in sherpa folder ${dir.path}');
    }
    final tts =
        hasVoices ||
        hasEspeakData ||
        _ttsName.hasMatch(dirName) ||
        models.any((m) => _ttsFile.hasMatch(p.basename(m).toLowerCase()));
    return tts
        ? SherpaTtsLayout._detect(dir, entries, models, tokens, preferInt8)
        : SherpaAsrLayout._detect(dir, models, tokens, preferInt8, streaming);
  }

  static final _ttsName = RegExp(
    r'kokoro|piper|vits|matcha|kitten|(^|[-_])tts([-_]|$)',
  );
  static final _ttsFile = RegExp(r'vocoder|vocos|hifigan|model-steps');
}

/// Files and architecture of a speech recognition model folder.
final class SherpaAsrLayout extends SherpaModelLayout {
  final SherpaAsrArchitecture architecture;
  final Map<SherpaFileRole, String> files;

  const SherpaAsrLayout(
    super.directory,
    super.tokens,
    this.architecture,
    this.files,
  );

  factory SherpaAsrLayout._detect(
    Directory dir,
    List<String> models,
    String tokens,
    bool preferInt8,
    bool? streaming,
  ) {
    final files = _pickRoles(models, preferInt8, _asrRole);
    final names = models.map((m) => p.basename(m).toLowerCase());
    final hint = '${p.basename(dir.path).toLowerCase()} ${names.join(' ')}';
    bool has(SherpaFileRole r) => files.containsKey(r);
    final isStreaming =
        streaming ??
        (hint.contains('streaming') ||
            hint.contains('chunk-') ||
            _hasStreamingMetadata(files[SherpaFileRole.encoder]));

    final SherpaAsrArchitecture arch;
    if (hint.contains('moonshine') &&
        has(SherpaFileRole.encoder) &&
        (has(SherpaFileRole.mergedDecoder) || has(SherpaFileRole.decoder))) {
      arch = SherpaAsrArchitecture.moonshine;
    } else if (has(SherpaFileRole.preprocessor) &&
        has(SherpaFileRole.encoder) &&
        (has(SherpaFileRole.mergedDecoder) ||
            (has(SherpaFileRole.uncachedDecoder) &&
                has(SherpaFileRole.cachedDecoder)))) {
      arch = SherpaAsrArchitecture.moonshine;
    } else if (has(SherpaFileRole.joiner)) {
      if (!has(SherpaFileRole.encoder) || !has(SherpaFileRole.decoder)) {
        throw InferenceException(
          'Transducer folder ${dir.path} needs encoder, decoder and joiner',
        );
      }
      arch =
          isStreaming
              ? SherpaAsrArchitecture.streamingTransducer
              : SherpaAsrArchitecture.transducer;
    } else if (has(SherpaFileRole.encoder) && has(SherpaFileRole.decoder)) {
      if (_whisperHint.hasMatch(hint)) {
        arch = SherpaAsrArchitecture.whisper;
      } else if (hint.contains('paraformer') && isStreaming) {
        arch = SherpaAsrArchitecture.streamingParaformer;
      } else {
        throw InferenceException(
          'Unsupported encoder/decoder model in ${dir.path}',
        );
      }
    } else if (has(SherpaFileRole.model)) {
      arch = switch (hint) {
        _ when hint.contains('sense') => SherpaAsrArchitecture.senseVoice,
        _ when hint.contains('paraformer') => SherpaAsrArchitecture.paraformer,
        _ when hint.contains('zipformer') =>
          isStreaming
              ? SherpaAsrArchitecture.streamingZipformerCtc
              : SherpaAsrArchitecture.zipformerCtc,
        _ =>
          isStreaming
              ? SherpaAsrArchitecture.streamingNemoCtc
              : SherpaAsrArchitecture.nemoCtc,
      };
    } else {
      throw InferenceException(
        'Unrecognised sherpa model files in ${dir.path}',
      );
    }
    return SherpaAsrLayout(dir.path, tokens, arch, files);
  }

  /// Streaming icefall encoders record their chunking in the ONNX metadata,
  /// which is serialised at the end of the file.
  static bool _hasStreamingMetadata(String? encoder) {
    if (encoder == null) return false;
    try {
      final file = File(encoder).openSync();
      try {
        const window = 64 * 1024;
        final length = file.lengthSync();
        file.setPositionSync(length > window ? length - window : 0);
        final tail = file.readSync(window);
        return String.fromCharCodes(tail).contains('decode_chunk_len');
      } finally {
        file.closeSync();
      }
    } on FileSystemException {
      return false;
    }
  }

  static final _whisperHint = RegExp(
    r'whisper|(^|\s)(tiny|base|small|medium|large|turbo)[.\-]',
  );

  static SherpaFileRole _asrRole(String name) => switch (name) {
    _ when name.contains('preprocess') => SherpaFileRole.preprocessor,
    _ when name.contains('uncached_decode') => SherpaFileRole.uncachedDecoder,
    _ when name.contains('cached_decode') => SherpaFileRole.cachedDecoder,
    _ when name.contains('merged') => SherpaFileRole.mergedDecoder,
    _ when name.contains('joiner') => SherpaFileRole.joiner,
    _ when name.contains('encode') => SherpaFileRole.encoder,
    _ when name.contains('decode') => SherpaFileRole.decoder,
    _ => SherpaFileRole.model,
  };

  /// Path for [role]; empty when the layout has none.
  String path(SherpaFileRole role) => files[role] ?? '';
}

/// Files and architecture of a speech synthesis model folder.
final class SherpaTtsLayout extends SherpaModelLayout {
  final SherpaTtsArchitecture architecture;

  /// Main (or Matcha acoustic) model.
  final String model;

  /// `voices.bin` for Kokoro and Kitten.
  final String voices;

  /// Matcha vocoder, when it sits in the folder.
  final String vocoder;

  /// `espeak-ng-data` folder, empty when absent.
  final String dataDir;

  /// Comma-separated lexicon files, empty when absent.
  final String lexicon;

  /// Comma-separated text-normalisation `.fst` files, empty when absent.
  final String ruleFsts;

  const SherpaTtsLayout({
    required String directory,
    required String tokens,
    required this.architecture,
    required this.model,
    this.voices = '',
    this.vocoder = '',
    this.dataDir = '',
    this.lexicon = '',
    this.ruleFsts = '',
  }) : super(directory, tokens);

  factory SherpaTtsLayout._detect(
    Directory dir,
    List<FileSystemEntity> entries,
    List<String> models,
    String tokens,
    bool preferInt8,
  ) {
    final files = _pickRoles(models, preferInt8, _ttsRole);
    final model = files[SherpaFileRole.model];
    if (model == null) {
      throw InferenceException('No TTS model .onnx in ${dir.path}');
    }
    String join(bool Function(String name) test) => (entries
            .whereType<File>()
            .map((f) => f.path)
            .where((f) => test(p.basename(f).toLowerCase()))
            .toList()
          ..sort())
        .join(',');
    final voices = entries
        .whereType<File>()
        .map((f) => f.path)
        .where((f) => p.basename(f).toLowerCase() == 'voices.bin');
    final espeak = p.join(dir.path, 'espeak-ng-data');
    final name = p.basename(dir.path).toLowerCase();
    final arch =
        files.containsKey(SherpaFileRole.vocoder) || name.contains('matcha')
            ? SherpaTtsArchitecture.matcha
            : voices.isEmpty
            ? SherpaTtsArchitecture.vits
            : name.contains('kitten')
            ? SherpaTtsArchitecture.kitten
            : SherpaTtsArchitecture.kokoro;
    return SherpaTtsLayout(
      directory: dir.path,
      tokens: tokens,
      architecture: arch,
      model: model,
      voices: voices.firstOrNull ?? '',
      vocoder: files[SherpaFileRole.vocoder] ?? '',
      dataDir: Directory(espeak).existsSync() ? espeak : '',
      lexicon: join((n) => n.startsWith('lexicon') && n.endsWith('.txt')),
      ruleFsts: join((n) => n.endsWith('.fst')),
    );
  }

  static SherpaFileRole _ttsRole(String name) => switch (name) {
    _ when RegExp(r'vocoder|vocos|hifigan').hasMatch(name) =>
      SherpaFileRole.vocoder,
    _ => SherpaFileRole.model,
  };
}

/// Chooses one file per role. Encoders pick the file first; decoders and
/// joiners then prefer the file whose name differs only by the role word, so
/// folders holding several chunk-size variants stay consistent.
Map<SherpaFileRole, String> _pickRoles(
  List<String> models,
  bool preferInt8,
  SherpaFileRole Function(String lowerName) roleOf,
) {
  final byRole = <SherpaFileRole, List<String>>{};
  for (final m in models) {
    byRole.putIfAbsent(roleOf(p.basename(m).toLowerCase()), () => []).add(m);
  }
  String choose(List<String> paths, {String? key, String? word}) {
    final sorted = [...paths]..sort();
    if (key != null && word != null) {
      final same = sorted.where(
        (s) => p.basename(s).toLowerCase().replaceFirst(word, '') == key,
      );
      if (same.isNotEmpty) return same.first;
    }
    final quant = sorted.where(
      (s) => p.basename(s).toLowerCase().contains('int8'),
    );
    final plain = sorted.where(
      (s) => !p.basename(s).toLowerCase().contains('int8'),
    );
    final pool = switch (preferInt8) {
      true when quant.isNotEmpty => quant,
      false when plain.isNotEmpty => plain,
      _ => sorted,
    };
    return pool.first;
  }

  final picked = <SherpaFileRole, String>{};
  final encoder = byRole[SherpaFileRole.encoder];
  String? key;
  if (encoder != null) {
    picked[SherpaFileRole.encoder] = choose(encoder);
    key = p
        .basename(picked[SherpaFileRole.encoder]!)
        .toLowerCase()
        .replaceFirst('encoder', '')
        .replaceFirst('encode', '');
  }
  for (final MapEntry(key: role, value: paths) in byRole.entries) {
    if (role == SherpaFileRole.encoder) continue;
    final word = switch (role) {
      SherpaFileRole.decoder => 'decoder',
      SherpaFileRole.joiner => 'joiner',
      _ => null,
    };
    picked[role] = choose(paths, key: key, word: word);
  }
  return picked;
}
