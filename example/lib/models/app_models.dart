import 'package:llm_toolkit/llm_toolkit.dart';

class LocalModel {
  final String name;
  final String path;
  final String size;
  final DateTime lastModified;
  final InferenceEngineType engine;

  LocalModel({
    required this.name,
    required this.path,
    required this.size,
    required this.lastModified,
    required this.engine,
  });
}

class RecommendedModel {
  final String name;
  final String description;
  final String searchTerm;
  final String quantization;
  final String size;
  final InferenceEngineType engine;
  final String category;
  final bool isStable;
  final List<String> features;
  final String difficulty;

  RecommendedModel({
    required this.name,
    required this.description,
    required this.searchTerm,
    required this.quantization,
    required this.size,
    required this.engine,
    required this.category,
    this.isStable = true,
    this.features = const [],
    this.difficulty = 'Easy',
  });
}

class ChatMessage {
  String text;
  final bool isUser;
  final DateTime timestamp;
  String? error;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.error,
  }) : timestamp = timestamp ?? DateTime.now();
}

class DeviceInfo {
  final String brand;
  final String model;
  final String version;
  final int sdkInt;
  final int totalMemoryMB;
  final int availableMemoryMB;
  final String memoryStatus;
  final String recommendedQuantization;
  final int recommendedNCtx;

  DeviceInfo({
    required this.brand,
    required this.model,
    required this.version,
    required this.sdkInt,
    required this.totalMemoryMB,
    required this.availableMemoryMB,
    required this.memoryStatus,
    required this.recommendedQuantization,
    required this.recommendedNCtx,
  });
}
