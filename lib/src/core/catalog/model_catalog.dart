import '../base_provider.dart';
import '../model_info.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

/// A curated, verified-on-the-Hub model that suits phones.
///
/// Sizes are the real byte counts of [files] (or of the whole repository when
/// [files] is empty); [minRamBytes] is an estimate of the memory needed to
/// run it comfortably.
class CatalogModel {
  /// Hugging Face repository id.
  final String repoId;
  final String name;
  final ModelTask task;

  /// Id of the built-in engine that runs it; `null` when none can.
  final String? runtime;

  /// Repository paths to download; empty means the whole repository.
  final List<String> files;
  final int sizeBytes;
  final int minRamBytes;
  final String license;

  /// Needs an accepted licence and a Hub token.
  final bool gated;
  final String notes;

  const CatalogModel({
    required this.repoId,
    required this.name,
    required this.task,
    required this.runtime,
    required this.files,
    required this.sizeBytes,
    required this.minRamBytes,
    required this.license,
    this.gated = false,
    this.notes = '',
  });

  bool get isRunnable => runtime != null;

  /// Several files that must live in one folder (sherpa-onnx models).
  bool get isBundle =>
      runtime == EngineIds.sherpaAsr || runtime == EngineIds.sherpaTts;

  /// Downloads the model with [provider] (normally the Hugging Face one) and
  /// returns the weights file, or the folder for bundles.
  Future<String> download(
    BaseModelProvider provider, {
    ProgressCallback? onProgress,
    DownloadProgressCallback? onDetailedProgress,
  }) {
    if (isBundle || files.length != 1) {
      return provider.downloadBundle(
        repoId,
        files: files.isEmpty ? null : files,
        onProgress: onProgress,
        onDetailedProgress: onDetailedProgress,
      );
    }
    return provider.downloadModel(
      repoId,
      files.single,
      onProgress: onProgress,
      onDetailedProgress: onDetailedProgress,
    );
  }

  @override
  String toString() => 'CatalogModel($repoId, ${task.name})';
}

/// Known-good mobile models per task, checked against the Hub API.
abstract final class ModelCatalog {
  static const custom =
      'Needs a custom host pipeline: not runnable by this toolkit.';

  static const all = <CatalogModel>[
    // Speech to text: TFLite Whisper.
    CatalogModel(
      repoId: 'litert-community/whisper-tiny',
      name: 'Whisper tiny (int8)',
      task: ModelTask.speechToText,
      runtime: EngineIds.asr,
      files: ['whisper_tiny_30s_i8.tflite'],
      sizeBytes: 41116288,
      minRamBytes: 512 * _mb,
      license: 'apache-2.0',
      notes: 'Multilingual, 30 s windows. Smallest and fastest.',
    ),
    CatalogModel(
      repoId: 'litert-community/whisper-tiny',
      name: 'Whisper tiny (float32)',
      task: ModelTask.speechToText,
      runtime: EngineIds.asr,
      files: ['whisper_tiny_30s_f32.tflite'],
      sizeBytes: 150979184,
      minRamBytes: 768 * _mb,
      license: 'apache-2.0',
      notes: 'Full-precision graph; better accuracy than int8.',
    ),
    CatalogModel(
      repoId: 'litert-community/whisper-base',
      name: 'Whisper base (int8)',
      task: ModelTask.speechToText,
      runtime: EngineIds.asr,
      files: ['whisper_base_30s_i8.tflite'],
      sizeBytes: 77012960,
      minRamBytes: 768 * _mb,
      license: 'apache-2.0',
      notes: 'Multilingual, 30 s windows.',
    ),
    CatalogModel(
      repoId: 'litert-community/whisper-base',
      name: 'Whisper base (float32)',
      task: ModelTask.speechToText,
      runtime: EngineIds.asr,
      files: ['whisper_base_30s_f32.tflite'],
      sizeBytes: 290082636,
      minRamBytes: 1 * _gb,
      license: 'apache-2.0',
    ),
    // Speech to text: sherpa-onnx bundles.
    CatalogModel(
      repoId: 'csukuangfj/sherpa-onnx-whisper-tiny.en',
      name: 'Whisper tiny.en (sherpa, int8)',
      task: ModelTask.speechToText,
      runtime: EngineIds.sherpaAsr,
      files: [
        'tiny.en-encoder.int8.onnx',
        'tiny.en-decoder.int8.onnx',
        'tiny.en-tokens.txt',
      ],
      sizeBytes: 103627191,
      minRamBytes: 512 * _mb,
      license: 'mit',
      notes: 'English only. License follows OpenAI Whisper.',
    ),
    CatalogModel(
      repoId: 'csukuangfj/sherpa-onnx-whisper-base.en',
      name: 'Whisper base.en (sherpa, int8)',
      task: ModelTask.speechToText,
      runtime: EngineIds.sherpaAsr,
      files: [
        'base.en-encoder.int8.onnx',
        'base.en-decoder.int8.onnx',
        'base.en-tokens.txt',
      ],
      sizeBytes: 160626066,
      minRamBytes: 768 * _mb,
      license: 'mit',
      notes: 'English only. License follows OpenAI Whisper.',
    ),
    CatalogModel(
      repoId: 'csukuangfj/sherpa-onnx-moonshine-tiny-en-int8',
      name: 'Moonshine tiny (sherpa, int8)',
      task: ModelTask.speechToText,
      runtime: EngineIds.sherpaAsr,
      files: [
        'preprocess.onnx',
        'encode.int8.onnx',
        'uncached_decode.int8.onnx',
        'cached_decode.int8.onnx',
        'tokens.txt',
      ],
      sizeBytes: 123967539,
      minRamBytes: 512 * _mb,
      license: 'mit',
      notes: 'English only; variable-length audio, fast on CPU.',
    ),
    // Speech to text: graphs the toolkit cannot drive.
    CatalogModel(
      repoId: 'litert-community/moonshine-tiny',
      name: 'Moonshine tiny (LiteRT, int8)',
      task: ModelTask.speechToText,
      runtime: null,
      files: ['moonshine_tiny_5s_i8.tflite'],
      sizeBytes: 51936896,
      minRamBytes: 512 * _mb,
      license: 'mit',
      notes: 'Fixed 5 s windows. $custom Use the sherpa build instead.',
    ),
    CatalogModel(
      repoId: 'litert-community/parakeet-ctc-0.6b',
      name: 'Parakeet CTC 0.6B (LiteRT, int8)',
      task: ModelTask.speechToText,
      runtime: null,
      files: ['parakeet_ctc_0.6b_5s_i8.tflite'],
      sizeBytes: 596365072,
      minRamBytes: 2 * _gb,
      license: 'cc-by-4.0',
      notes: 'English, high accuracy. $custom',
    ),
    CatalogModel(
      repoId: 'litert-community/Qwen3-ASR-0.6B',
      name: 'Qwen3-ASR 0.6B (LiteRT, int8)',
      task: ModelTask.speechToText,
      runtime: null,
      files: ['qwen3_asr_0.6b_5s_i8.tflite'],
      sizeBytes: 793931296,
      minRamBytes: 3 * _gb,
      license: 'apache-2.0',
      notes: 'Multilingual. $custom',
    ),
    // Text to speech.
    CatalogModel(
      repoId: 'csukuangfj/vits-piper-en_US-lessac-medium',
      name: 'Piper en_US lessac (medium)',
      task: ModelTask.textToSpeech,
      runtime: EngineIds.sherpaTts,
      files: [],
      sizeBytes: 81203669,
      minRamBytes: 512 * _mb,
      license: 'see model card',
      notes: 'Whole folder incl. espeak-ng data. Check the voice licence.',
    ),
    CatalogModel(
      repoId: 'csukuangfj/vits-piper-en_US-amy-low',
      name: 'Piper en_US amy (low)',
      task: ModelTask.textToSpeech,
      runtime: EngineIds.sherpaTts,
      files: [],
      sizeBytes: 81105784,
      minRamBytes: 512 * _mb,
      license: 'see model card',
      notes: 'Whole folder incl. espeak-ng data. Lowest latency.',
    ),
    CatalogModel(
      repoId: 'csukuangfj/kokoro-multi-lang-v1_0',
      name: 'Kokoro 82M multilingual (sherpa)',
      task: ModelTask.textToSpeech,
      runtime: EngineIds.sherpaTts,
      files: [],
      sizeBytes: 401240996,
      minRamBytes: 1 * _gb,
      license: 'apache-2.0',
      notes: 'Whole folder: model, voices, lexicons and espeak data.',
    ),
    CatalogModel(
      repoId: 'onnx-community/Kokoro-82M-ONNX',
      name: 'Kokoro 82M (ONNX, quantised)',
      task: ModelTask.textToSpeech,
      runtime: null,
      files: ['onnx/model_quantized.onnx', 'voices/af_bella.bin'],
      sizeBytes: 92884831,
      minRamBytes: 1 * _gb,
      license: 'apache-2.0',
      notes: 'transformers.js layout, not sherpa. $custom',
    ),
    // Text generation.
    CatalogModel(
      repoId: 'unsloth/Qwen3-0.6B-GGUF',
      name: 'Qwen3 0.6B (Q4_K_M)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.llama,
      files: ['Qwen3-0.6B-Q4_K_M.gguf'],
      sizeBytes: 396705472,
      minRamBytes: 1 * _gb,
      license: 'apache-2.0',
      notes: 'Runs on nearly any phone; supports thinking mode.',
    ),
    CatalogModel(
      repoId: 'litert-community/Qwen3-0.6B',
      name: 'Qwen3 0.6B (LiteRT-LM, int4)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.litert,
      files: ['Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm'],
      sizeBytes: 344671744,
      minRamBytes: 1 * _gb,
      license: 'apache-2.0',
    ),
    CatalogModel(
      repoId: 'unsloth/Qwen3-1.7B-GGUF',
      name: 'Qwen3 1.7B (Q4_K_M)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.llama,
      files: ['Qwen3-1.7B-Q4_K_M.gguf'],
      sizeBytes: 1107409472,
      minRamBytes: 3 * _gb,
      license: 'apache-2.0',
    ),
    CatalogModel(
      repoId: 'litert-community/Qwen3-1.7B',
      name: 'Qwen3 1.7B (LiteRT-LM, int4)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.litert,
      files: ['Qwen3-1.7B_dynamic_wi4b32_afp32.litertlm'],
      sizeBytes: 977184032,
      minRamBytes: 3 * _gb,
      license: 'apache-2.0',
    ),
    CatalogModel(
      repoId: 'litert-community/Gemma3-1B-IT',
      name: 'Gemma 3 1B (LiteRT-LM, int4)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.litert,
      files: ['gemma3-1b-it-int4.litertlm'],
      sizeBytes: 584417280,
      minRamBytes: 2 * _gb,
      license: 'gemma',
      gated: true,
      notes: 'Accept the Gemma licence on the Hub and pass a token.',
    ),
    CatalogModel(
      repoId: 'unsloth/gemma-3n-E2B-it-GGUF',
      name: 'Gemma 3n E2B (Q4_K_M)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.llama,
      files: ['gemma-3n-E2B-it-Q4_K_M.gguf'],
      sizeBytes: 3026881888,
      minRamBytes: 6 * _gb,
      license: 'gemma',
      notes: 'Text only here: the repository ships no mmproj file.',
    ),
    CatalogModel(
      repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
      name: 'Llama 3.2 1B Instruct (Q4_K_M)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.llama,
      files: ['Llama-3.2-1B-Instruct-Q4_K_M.gguf'],
      sizeBytes: 807694464,
      minRamBytes: 2 * _gb,
      license: 'llama3.2',
    ),
    CatalogModel(
      repoId: 'litert-community/Llama-3.2-1B',
      name: 'Llama 3.2 1B (LiteRT-LM, int4)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.litert,
      files: ['llama3_2_1b_mixed_int4_gpu.litertlm'],
      sizeBytes: 963903488,
      minRamBytes: 2 * _gb,
      license: 'llama3.2',
      gated: true,
      notes: 'Accept the Llama licence on the Hub and pass a token.',
    ),
    CatalogModel(
      repoId: 'bartowski/Llama-3.2-3B-Instruct-GGUF',
      name: 'Llama 3.2 3B Instruct (Q4_K_M)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.llama,
      files: ['Llama-3.2-3B-Instruct-Q4_K_M.gguf'],
      sizeBytes: 2019377696,
      minRamBytes: 4 * _gb,
      license: 'llama3.2',
    ),
    CatalogModel(
      repoId: 'unsloth/SmolLM3-3B-GGUF',
      name: 'SmolLM3 3B (Q4_K_M)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.llama,
      files: ['SmolLM3-3B-Q4_K_M.gguf'],
      sizeBytes: 1915306528,
      minRamBytes: 4 * _gb,
      license: 'apache-2.0',
    ),
    CatalogModel(
      repoId: 'LiquidAI/LFM2-1.2B-GGUF',
      name: 'LFM2 1.2B (Q4_K_M)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.llama,
      files: ['LFM2-1.2B-Q4_K_M.gguf'],
      sizeBytes: 730893248,
      minRamBytes: 2 * _gb,
      license: 'other',
      notes: 'LFM Open License: free below a revenue threshold.',
    ),
    CatalogModel(
      repoId: 'litert-community/LFM2.5-1.2B-Instruct',
      name: 'LFM2.5 1.2B Instruct (LiteRT-LM, int4)',
      task: ModelTask.textGeneration,
      runtime: EngineIds.litert,
      files: ['LFM2.5-1.2B-Instruct_int4.litertlm'],
      sizeBytes: 736015744,
      minRamBytes: 2 * _gb,
      license: 'other',
      notes: 'LFM Open License: free below a revenue threshold.',
    ),
    // Vision.
    CatalogModel(
      repoId: 'google/gemma-3n-E2B-it-litert-lm',
      name: 'Gemma 3n E2B (LiteRT-LM, int4)',
      task: ModelTask.vision,
      runtime: EngineIds.litert,
      files: ['gemma-3n-E2B-it-int4.litertlm'],
      sizeBytes: 3655827456,
      minRamBytes: 6 * _gb,
      license: 'gemma',
      gated: true,
      notes: 'Image and audio input. Accept the Gemma licence on the Hub.',
    ),
    CatalogModel(
      repoId: 'litert-community/LFM2.5-VL-450M',
      name: 'LFM2.5-VL 450M (LiteRT-LM, int4)',
      task: ModelTask.vision,
      runtime: EngineIds.litert,
      files: ['LFM2.5-VL-450M_int4.litertlm'],
      sizeBytes: 406820224,
      minRamBytes: 1 * _gb,
      license: 'other',
      notes: 'Smallest vision-language model here.',
    ),
    CatalogModel(
      repoId: 'ggml-org/SmolVLM2-500M-Video-Instruct-GGUF',
      name: 'SmolVLM2 500M (Q8_0 + mmproj)',
      task: ModelTask.vision,
      runtime: EngineIds.llama,
      files: [
        'SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
        'mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
      ],
      sizeBytes: 545593888,
      minRamBytes: 2 * _gb,
      license: 'apache-2.0',
      notes: 'Download both files into the same folder.',
    ),
    // Embeddings.
    CatalogModel(
      repoId: 'CompendiumLabs/bge-small-en-v1.5-gguf',
      name: 'BGE small en v1.5 (Q8_0)',
      task: ModelTask.embedding,
      runtime: EngineIds.llama,
      files: ['bge-small-en-v1.5-q8_0.gguf'],
      sizeBytes: 36806944,
      minRamBytes: 256 * _mb,
      license: 'mit',
      notes: '384 dimensions, English.',
    ),
    CatalogModel(
      repoId: 'nomic-ai/nomic-embed-text-v1.5-GGUF',
      name: 'Nomic Embed Text v1.5 (Q4_K_M)',
      task: ModelTask.embedding,
      runtime: EngineIds.llama,
      files: ['nomic-embed-text-v1.5.Q4_K_M.gguf'],
      sizeBytes: 84106624,
      minRamBytes: 512 * _mb,
      license: 'apache-2.0',
      notes:
          '768 dimensions (Matryoshka), long context. Prefix inputs with '
          '"search_document: " / "search_query: ".',
    ),
    CatalogModel(
      repoId: 'ggml-org/embeddinggemma-300M-GGUF',
      name: 'EmbeddingGemma 300M (Q8_0)',
      task: ModelTask.embedding,
      runtime: EngineIds.llama,
      files: ['embeddinggemma-300M-Q8_0.gguf'],
      sizeBytes: 333590944,
      minRamBytes: 1 * _gb,
      license: 'gemma',
      notes: '768 dimensions, multilingual.',
    ),
    // Image generation.
    CatalogModel(
      repoId: 'litert-community/Z-Image-Turbo-LiteRT',
      name: 'Z-Image Turbo (LiteRT)',
      task: ModelTask.imageGeneration,
      runtime: null,
      files: [],
      sizeBytes: 9778689787,
      minRamBytes: 8 * _gb,
      license: 'apache-2.0',
      notes: 'Chunked int8 graphs; needs an 8 GB phone. $custom',
    ),
    CatalogModel(
      repoId: 'litert-community/FLUX.2-klein-4B-LiteRT',
      name: 'FLUX.2 klein 4B (LiteRT)',
      task: ModelTask.imageGeneration,
      runtime: null,
      files: [],
      sizeBytes: 11359398277,
      minRamBytes: 12 * _gb,
      license: 'apache-2.0',
      notes: 'Chunked graphs plus tokenizer assets. $custom',
    ),
  ];

  /// Entries for [task], optionally only those the toolkit can run.
  static List<CatalogModel> forTask(
    ModelTask task, {
    bool runnableOnly = false,
  }) => [
    for (final m in all)
      if (m.task == task && (!runnableOnly || m.isRunnable)) m,
  ];

  /// Runnable entries for [task] that fit [availableMemoryBytes], largest
  /// (usually most capable) first.
  ///
  /// Pass `runnableOnly: false` to also list models that need a custom
  /// pipeline.
  static List<CatalogModel> forDevice(
    ModelTask task,
    int availableMemoryBytes, {
    bool runnableOnly = true,
  }) =>
      forTask(
          task,
          runnableOnly: runnableOnly,
        ).where((m) => m.minRamBytes <= availableMemoryBytes).toList()
        ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

  /// Entry for [repoId] (and [file] when a repository has several).
  static CatalogModel? find(String repoId, {String? file}) {
    for (final m in all) {
      if (m.repoId == repoId && (file == null || m.files.contains(file))) {
        return m;
      }
    }
    return null;
  }
}
