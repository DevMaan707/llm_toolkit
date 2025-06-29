class SearchQuery {
  final String searchTerm;
  final List<ModelFormat> formats;
  final List<TaskType> tasks;
  final int limit;
  final bool onlyCompatible;
  final int? maxSizeBytes;
  final SortBy sortBy;
  final SortDirection sortDirection;

  SearchQuery({
    required this.searchTerm,
    this.formats = const [],
    this.tasks = const [],
    this.limit = 20,
    this.onlyCompatible = true,
    this.maxSizeBytes,
    this.sortBy = SortBy.downloads,
    this.sortDirection = SortDirection.desc,
  });
}

enum ModelFormat { gguf, ggml, safetensors, pytorch }

enum TaskType { textGeneration, chatbot, codeGeneration, translation }

enum SortBy { downloads, created, updated, name }

enum SortDirection { asc, desc }
