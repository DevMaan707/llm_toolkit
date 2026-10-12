import 'dart:convert';

import '../chat_message.dart';

/// Message text including any tool calls in `<tool_call>` tag form.
String templateText(ChatMessage m, [String? content]) {
  final text = content ?? m.content;
  if (m.toolCalls.isEmpty) return text;
  final calls = [
    for (final c in m.toolCalls)
      '<tool_call>\n${jsonEncode(c.toJson())}\n</tool_call>',
  ].join('\n');
  return text.isEmpty ? calls : '$text\n$calls';
}

/// Merges system messages into the next user turn and maps tool results to
/// user turns, for templates without system/tool roles.
List<ChatMessage> foldSystem(List<ChatMessage> messages) {
  final out = <ChatMessage>[];
  var pending = '';
  for (final m in messages) {
    if (m.role == ChatRole.system) {
      pending = pending.isEmpty ? m.content : '$pending\n\n${m.content}';
      continue;
    }
    final text = templateText(m);
    if (m.role == ChatRole.assistant) {
      if (pending.isNotEmpty) {
        out.add(ChatMessage.user(pending));
        pending = '';
      }
      out.add(ChatMessage.assistant(text));
    } else {
      out.add(ChatMessage.user(pending.isEmpty ? text : '$pending\n\n$text'));
      pending = '';
    }
  }
  if (pending.isNotEmpty) out.add(ChatMessage.user(pending));
  return out;
}

/// Text after the last `</think>`, or [text] unchanged when there is none.
/// With [trimLeadingNewlines] the newlines following the tag are dropped too.
String stripThink(String text, {bool trimLeadingNewlines = false}) {
  const close = '</think>';
  final i = text.lastIndexOf(close);
  if (i < 0) return text;
  final rest = text.substring(i + close.length);
  return trimLeadingNewlines ? rest.replaceFirst(RegExp(r'^\n+'), '') : rest;
}

/// Index of the last user message, or -1.
int lastUserIndex(List<ChatMessage> messages) =>
    messages.lastIndexWhere((m) => m.role == ChatRole.user);

String twoDigits(int n) => n.toString().padLeft(2, '0');

/// `2025-06-28`.
String isoDate(DateTime d) =>
    '${d.year}-${twoDigits(d.month)}-${twoDigits(d.day)}';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `28 June 2025`.
String longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Python-style literal for [value], as used by pythonic tool-call formats.
String pythonLiteral(Object? value) => switch (value) {
  null => 'None',
  true => 'True',
  false => 'False',
  final String s =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n')}'",
  final num n => n.toString(),
  _ => jsonEncode(value),
};
