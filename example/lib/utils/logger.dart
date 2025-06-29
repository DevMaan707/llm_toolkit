import 'package:flutter/foundation.dart';

enum LogLevel { info, success, warning, error }

class LogEntry {
  final LogLevel level;
  final String message;
  final dynamic error;
  final DateTime timestamp;

  LogEntry({
    required this.level,
    required this.message,
    this.error,
    required this.timestamp,
  });
}

class AppLogger extends ChangeNotifier {
  final List<LogEntry> _logs = [];

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void info(String message) => _log(LogLevel.info, message);
  void success(String message) => _log(LogLevel.success, message);
  void warning(String message) => _log(LogLevel.warning, message);
  void error(String message, [dynamic error]) =>
      _log(LogLevel.error, message, error);

  void _log(LogLevel level, String message, [dynamic error]) {
    final entry = LogEntry(
      level: level,
      message: message,
      error: error,
      timestamp: DateTime.now(),
    );

    _logs.add(entry);
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }

    notifyListeners(); // Notify listeners when new logs are added

    if (kDebugMode) {
      print(
        '[${level.name.toUpperCase()}] $message${error != null ? ': $error' : ''}',
      );
    }
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _logs.clear();
    super.dispose();
  }
}
