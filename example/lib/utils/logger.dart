import 'package:flutter/foundation.dart';
import 'package:llm_toolkit/llm_toolkit.dart' show ToolkitLog;

enum AppLogLevel { info, success, warning, error }

class LogEntry {
  final AppLogLevel level;
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

  void info(String message) => _log(AppLogLevel.info, message);
  void success(String message) => _log(AppLogLevel.success, message);
  void warning(String message) => _log(AppLogLevel.warning, message);
  void error(String message, [dynamic error]) =>
      _log(AppLogLevel.error, message, error);

  void _log(AppLogLevel level, String message, [dynamic error]) {
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

    notifyListeners();

    final text = error == null ? message : '$message: $error';
    switch (level) {
      case AppLogLevel.info:
      case AppLogLevel.success:
        ToolkitLog.info('App', text);
      case AppLogLevel.warning:
        ToolkitLog.warning('App', text);
      case AppLogLevel.error:
        ToolkitLog.error('App', text);
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
