import 'dart:convert';
import 'dart:typed_data';

/// Author of a [ChatMessage].
enum ChatRole { system, user, assistant, tool }

/// A function call requested by the model.
class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall(this.name, [this.arguments = const {}]);

  /// The canonical `{"name": ..., "arguments": ...}` form used in prompts.
  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
    json['name'] as String,
    Map<String, dynamic>.from(json['arguments'] as Map? ?? const {}),
  );

  @override
  String toString() => 'ToolCall($name, $arguments)';
}

/// One message of a conversation.
class ChatMessage {
  final ChatRole role;
  final String content;
  final List<Uint8List> images;

  /// Calls requested by an assistant message (rendered by templates).
  final List<ToolCall> toolCalls;

  /// For [ChatRole.tool] messages: the tool that produced [content].
  final String? toolName;

  const ChatMessage(
    this.role,
    this.content, {
    this.images = const [],
    this.toolCalls = const [],
    this.toolName,
  });

  const ChatMessage.system(String content) : this(ChatRole.system, content);

  const ChatMessage.user(String content, {List<Uint8List> images = const []})
    : this(ChatRole.user, content, images: images);

  const ChatMessage.assistant(
    String content, {
    List<ToolCall> toolCalls = const [],
  }) : this(ChatRole.assistant, content, toolCalls: toolCalls);

  const ChatMessage.tool(String content, {String? name})
    : this(ChatRole.tool, content, toolName: name);

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': content,
    if (images.isNotEmpty) 'images': [for (final i in images) base64Encode(i)],
    if (toolCalls.isNotEmpty)
      'toolCalls': [for (final c in toolCalls) c.toJson()],
    if (toolName != null) 'toolName': toolName,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    ChatRole.values.byName(json['role'] as String),
    json['content'] as String? ?? '',
    images: [
      for (final i in json['images'] as List? ?? const [])
        base64Decode(i as String),
    ],
    toolCalls: [
      for (final c in json['toolCalls'] as List? ?? const [])
        ToolCall.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    toolName: json['toolName'] as String?,
  );

  @override
  String toString() => 'ChatMessage(${role.name}: $content)';
}
