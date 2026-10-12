import 'dart:developer' as developer;

/// Severity of a log record, ordered from least to most severe.
enum LogLevel { debug, info, warning, error, none }

/// A single log record handed to the active [LogSink].
class LogRecord {
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime time;

  LogRecord(this.level, this.tag, this.message, [this.error, this.stackTrace])
    : time = DateTime.now();

  @override
  String toString() =>
      '[${level.name.toUpperCase()}] $tag: $message${error != null ? ' ($error)' : ''}';
}

typedef LogSink = void Function(LogRecord record);

/// Library-wide logging. Silent below [level]; routes to `dart:developer` by
/// default and can be redirected with [sink] (for example into your own logger).
class ToolkitLog {
  ToolkitLog._();

  static LogLevel level = LogLevel.warning;

  static LogSink sink = _defaultSink;

  static void _defaultSink(LogRecord r) {
    developer.log(
      r.message,
      name: 'llm_toolkit.${r.tag}',
      level: switch (r.level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        _ => 1000,
      },
      error: r.error,
      stackTrace: r.stackTrace,
      time: r.time,
    );
  }

  static bool isEnabled(LogLevel l) => l.index >= level.index;

  static void _emit(
    LogLevel l,
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!isEnabled(l)) return;
    sink(LogRecord(l, tag, message, error, stackTrace));
  }

  static void debug(String tag, String message) =>
      _emit(LogLevel.debug, tag, message);
  static void info(String tag, String message) =>
      _emit(LogLevel.info, tag, message);
  static void warning(String tag, String message, [Object? error]) =>
      _emit(LogLevel.warning, tag, message, error);
  static void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _emit(LogLevel.error, tag, message, error, stackTrace);
}
