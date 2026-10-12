import 'dart:io';
import 'dart:math' as math;

/// Available RAM in MB from `/proc/meminfo`, or null where that file does not
/// exist (iOS, macOS, Windows) or cannot be parsed.
Future<int?> availableMemoryMb() async {
  if (!Platform.isLinux && !Platform.isAndroid) return null;
  try {
    final content = await File('/proc/meminfo').readAsString();
    return parseAvailableMemoryMb(content);
  } on FileSystemException {
    return null;
  }
}

/// Extracts `MemAvailable` from `/proc/meminfo` [content], in MB.
int? parseAvailableMemoryMb(String content) {
  final match = RegExp(r'MemAvailable:\s+(\d+)\s+kB').firstMatch(content);
  final kb = match == null ? null : int.tryParse(match.group(1)!);
  return kb == null ? null : kb ~/ 1024;
}

/// Largest context window considered safe for [availableMb], or null when
/// memory is plentiful or unknown.
int? contextLimitForMemory(int? availableMb) => switch (availableMb) {
  null => null,
  < 1024 => 512,
  < 2048 => 1024,
  < 4096 => 2048,
  _ => null,
};

/// [requested] context size clamped to what [availableMb] allows.
int clampContextSize(int requested, int? availableMb) {
  final limit = contextLimitForMemory(availableMb);
  return limit == null ? requested : math.min(requested, limit);
}
