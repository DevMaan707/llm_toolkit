/// Base type for every error thrown by the toolkit.
class LLMToolkitException implements Exception {
  final String message;
  final Object? cause;

  const LLMToolkitException(this.message, [this.cause]);

  @override
  String toString() =>
      '$runtimeType: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

/// A model provider (Hugging Face, Ollama, ...) failed.
class ModelProviderException extends LLMToolkitException {
  const ModelProviderException(super.message, [super.cause]);
}

/// Loading a model or running inference failed.
class InferenceException extends LLMToolkitException {
  const InferenceException(super.message, [super.cause]);
}

/// A model download failed, was cancelled, or failed verification.
class DownloadException extends LLMToolkitException {
  const DownloadException(super.message, [super.cause]);
}

/// The vector store or RAG pipeline failed.
class VectorStorageException extends LLMToolkitException {
  const VectorStorageException(super.message, [super.cause]);
}

/// No registered engine can serve the requested capability or model.
class UnsupportedCapabilityException extends LLMToolkitException {
  const UnsupportedCapabilityException(super.message, [super.cause]);
}

/// Structured output could not be parsed or validated.
class StructuredOutputException extends LLMToolkitException {
  final String rawOutput;
  const StructuredOutputException(super.message, this.rawOutput, [super.cause]);
}
