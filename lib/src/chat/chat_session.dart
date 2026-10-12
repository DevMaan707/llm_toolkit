import 'dart:async';
import 'dart:typed_data';

import '../core/config.dart';
import '../core/inference/base_inference_engine.dart';
import 'chat_backend.dart';
import 'chat_message.dart';
import 'chat_usage.dart';
import 'prompt_template.dart';

/// A stateful conversation on top of a [ChatGenerator] or [TextGenerator]
/// engine: keeps history, trims it to the context window and tracks usage.
class ChatSession {
  /// The engine; must implement `ChatGenerator` and/or `TextGenerator`.
  final Object engine;

  /// Used when the engine has no native chat API.
  final PromptTemplate template;

  GenerationParams params;

  /// Prepended to every request; never trimmed.
  String? systemPrompt;

  /// Context window in tokens; null disables trimming.
  final int? contextSize;
  final TokenCounter tokenCounter;

  /// Tokens assumed per attached image when budgeting.
  final int imageTokens;

  final DateTime Function() _clock;
  final List<ChatMessage> _history = [];
  bool _generating = false;
  bool _cancelled = false;
  ChatUsage? _lastUsage;
  int _totalPrompt = 0;
  int _totalCompletion = 0;

  ChatSession(
    this.engine, {
    this.systemPrompt,
    this.template = const ChatMlTemplate(),
    this.params = const GenerationParams(),
    this.contextSize,
    this.tokenCounter = approximateTokenCount,
    this.imageTokens = 256,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock {
    if (engine is! ChatGenerator && engine is! TextGenerator) {
      throw ArgumentError.value(
        engine,
        'engine',
        'must implement ChatGenerator or TextGenerator',
      );
    }
  }

  /// Rebuilds a session saved with [toJson].
  factory ChatSession.fromJson(
    Map<String, dynamic> json,
    Object engine, {
    PromptTemplate template = const ChatMlTemplate(),
    GenerationParams params = const GenerationParams(),
    int? contextSize,
    TokenCounter tokenCounter = approximateTokenCount,
  }) {
    final session = ChatSession(
      engine,
      systemPrompt: json['systemPrompt'] as String?,
      template: template,
      params: params,
      contextSize: contextSize,
      tokenCounter: tokenCounter,
    );
    for (final m in json['messages'] as List? ?? const []) {
      session._history.add(ChatMessage.fromJson(Map<String, dynamic>.from(m)));
    }
    return session;
  }

  /// Serialisable snapshot of the conversation (not the engine or settings).
  Map<String, dynamic> toJson() => {
    'version': 1,
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
    'messages': [for (final m in _history) m.toJson()],
  };

  List<ChatMessage> get history => List.unmodifiable(_history);
  bool get isGenerating => _generating;

  /// Usage of the most recent generation.
  ChatUsage? get lastUsage => _lastUsage;

  /// Cumulative usage since creation or [reset].
  ChatUsage get totalUsage =>
      ChatUsage(promptTokens: _totalPrompt, completionTokens: _totalCompletion);

  /// Adds [message] to the history without generating.
  void addMessage(ChatMessage message) {
    _ensureIdle();
    _history.add(message);
  }

  /// Sends a user message and streams the assistant reply. The completed reply
  /// is appended to the history once the stream finishes (or is cancelled).
  Stream<String> send(String text, {List<Uint8List> images = const []}) {
    _ensureIdle();
    _history.add(ChatMessage.user(text, images: images));
    return generate();
  }

  /// Streams a reply to the current history, which must not end with an
  /// assistant message. Used after [addMessage] (e.g. tool results).
  Stream<String> generate() async* {
    _ensureIdle();
    if (_history.isEmpty || _history.last.role == ChatRole.assistant) {
      throw StateError('Nothing to respond to');
    }
    _generating = true;
    _cancelled = false;
    final prompt = promptMessages();
    final promptTokens = _count(prompt);
    final start = _clock();
    DateTime? first;
    final reply = StringBuffer();
    var failed = false;
    try {
      await for (final chunk in streamReply(
        engine,
        prompt,
        template: template,
        params: params,
      )) {
        if (_cancelled) break;
        if (chunk.isEmpty) continue;
        first ??= _clock();
        reply.write(chunk);
        yield chunk;
      }
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      final text = reply.toString().trim();
      if (failed && text.isEmpty) {
        if (_history.last.role == ChatRole.user) _history.removeLast();
      } else if (text.isNotEmpty) {
        _history.add(ChatMessage.assistant(text));
      }
      final usage = ChatUsage(
        promptTokens: promptTokens,
        completionTokens: tokenCounter(text),
        timeToFirstToken: first?.difference(start),
        totalTime: _clock().difference(start),
      );
      _lastUsage = usage;
      _totalPrompt += usage.promptTokens;
      _totalCompletion += usage.completionTokens;
      _generating = false;
    }
  }

  /// Drops the last assistant reply and generates a new one.
  Stream<String> regenerate() {
    _ensureIdle();
    if (_history.isNotEmpty && _history.last.role == ChatRole.assistant) {
      _history.removeLast();
    }
    return generate();
  }

  /// Removes the last user turn and everything after it. Returns false when
  /// there is no user message.
  bool undo() {
    _ensureIdle();
    final i = _history.lastIndexWhere((m) => m.role == ChatRole.user);
    if (i < 0) return false;
    _history.removeRange(i, _history.length);
    return true;
  }

  /// Clears the history and usage counters (the system prompt is kept).
  void reset() {
    _ensureIdle();
    _history.clear();
    _lastUsage = null;
    _totalPrompt = 0;
    _totalCompletion = 0;
  }

  /// Stops the running generation; the partial reply is kept in the history.
  void cancel() => _cancelled = true;

  /// The messages that would be sent now: system prompt plus as much recent
  /// history as fits the context window (oldest turns are dropped first, the
  /// latest turn is always kept).
  List<ChatMessage> promptMessages() {
    final system = [
      if (systemPrompt != null && systemPrompt!.isNotEmpty)
        ChatMessage.system(systemPrompt!),
    ];
    final window = contextSize;
    if (window == null) return [...system, ..._history];
    final budget = window - params.maxTokens - _count(system);
    var start = _history.lastIndexWhere((m) => m.role == ChatRole.user);
    if (start < 0) return [...system, ..._history];
    var used = _count(_history.sublist(start));
    var end = start;
    // Add earlier turns (a user message and what follows it) while they fit.
    for (var i = end - 1; i >= 0; i--) {
      if (_history[i].role != ChatRole.user) continue;
      final cost = _count(_history.sublist(i, end));
      if (used + cost > budget) break;
      used += cost;
      start = i;
      end = i;
    }
    return [...system, ..._history.sublist(start)];
  }

  int _count(List<ChatMessage> messages) {
    var n = 0;
    for (final m in messages) {
      n += tokenCounter(m.content) + 4 + m.images.length * imageTokens;
    }
    return n;
  }

  void _ensureIdle() {
    if (_generating) throw StateError('A generation is already running');
  }
}
