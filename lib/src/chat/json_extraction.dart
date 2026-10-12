import 'dart:convert';

/// Returns every JSON value found in [text], in order of appearance.
///
/// Handles markdown code fences, surrounding prose, trailing commas,
/// single-quoted strings and raw newlines inside strings. Values inside
/// fences come first.
List<Object?> extractJsonValues(String text) {
  final found = <Object?>[];
  final fence = RegExp(r'```[a-zA-Z0-9_-]*\s*\n?([\s\S]*?)```');
  for (final m in fence.allMatches(text)) {
    found.addAll(_scan(m.group(1)!));
  }
  if (found.isEmpty) found.addAll(_scan(text));
  return found;
}

/// The first JSON value in [text], or null when there is none.
Object? extractJson(String text) {
  final values = extractJsonValues(text);
  return values.isEmpty ? null : values.first;
}

List<Object?> _scan(String text) {
  final out = <Object?>[];
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c != '{' && c != '[') {
      i++;
      continue;
    }
    final end = _matchingEnd(text, i);
    if (end < 0) {
      i++;
      continue;
    }
    final value = _tryDecode(text.substring(i, end + 1));
    if (value.ok) {
      out.add(value.value);
      i = end + 1;
    } else {
      i++;
    }
  }
  return out;
}

/// Index of the bracket closing the one at [start], or -1.
int _matchingEnd(String s, int start) {
  final stack = <String>[];
  String? quote;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    switch (c) {
      case '"' || "'":
        quote = c;
      case '{' || '[':
        stack.add(c == '{' ? '}' : ']');
      case '}' || ']':
        if (stack.isEmpty || stack.removeLast() != c) return -1;
        if (stack.isEmpty) return i;
    }
  }
  return -1;
}

({bool ok, Object? value}) _tryDecode(String s) {
  try {
    return (ok: true, value: jsonDecode(s));
  } on FormatException {
    try {
      return (ok: true, value: jsonDecode(repairJson(s)));
    } on FormatException {
      return (ok: false, value: null);
    }
  }
}

/// Best-effort fix of common LLM JSON mistakes: single-quoted strings, raw
/// newlines in strings and trailing commas.
String repairJson(String s) {
  final b = StringBuffer();
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      if (c == r'\' && i + 1 < s.length) {
        final next = s[i + 1];
        b.write(next == "'" ? "'" : '\\$next');
        i++;
      } else if (c == quote) {
        quote = null;
        b.write('"');
      } else if (c == '"') {
        b.write(r'\"');
      } else if (c == '\n') {
        b.write(r'\n');
      } else if (c == '\r') {
        b.write(r'\r');
      } else if (c == '\t') {
        b.write(r'\t');
      } else {
        b.write(c);
      }
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      b.write('"');
    } else if (c == '}' || c == ']') {
      final out = b.toString();
      final trimmed = out.trimRight();
      if (trimmed.endsWith(',')) {
        b.clear();
        b.write(trimmed.substring(0, trimmed.length - 1));
      }
      b.write(c);
    } else {
      b.write(c);
    }
  }
  return b.toString();
}
