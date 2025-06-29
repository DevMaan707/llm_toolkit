class LLMToolkitException implements Exception {
  final String message;
  final dynamic originalError;

  LLMToolkitException(this.message, [this.originalError]);

  @override
  String toString() => 'LLMToolkitException: $message';
}

class ModelProviderException extends LLMToolkitException {
  ModelProviderException(String message, [dynamic originalError])
    : super(message, originalError);
}

class InferenceException extends LLMToolkitException {
  InferenceException(String message, [dynamic originalError])
    : super(message, originalError);
}

class DownloadException extends LLMToolkitException {
  DownloadException(String message, [dynamic originalError])
    : super(message, originalError);
}

class VectorStorageException extends LLMToolkitException {
  VectorStorageException(String message, [dynamic originalError])
    : super(message, originalError);
}
