/// Chat-template families and tool-call markers (sdd-flutter-llama-agent 2.3).
library;

import 'dart:convert';

import '../models/chat.dart';

/// The template family, from the GGUF `tokenizer.chat_template` (or the architecture when there is none).
String? templateFamily(String? template, String? architecture) {
  if (template == null || template.isEmpty) return architecture == 'gpt2' ? 'gpt2-plain' : null;
  if (template.contains('<|start_of_role|>')) return 'granite';
  if (template.contains('<|im_start|>')) return 'chatml';
  if (template.contains('<|start_header_id|>')) return 'llama3';
  if (template.contains('<start_of_turn>')) return 'gemma';
  if (template.contains('<|user|>') && template.contains('<|end|>')) return 'phi3';
  if (template.contains('[INST]')) return 'mistral';
  return 'custom';
}

/// Whether the template renders Hermes / Qwen style tools (`<tool_call>` … `</tool_call>`).
bool hermesTools(String? template) => template != null && template.contains('<tool_call>');

/// Whether the model understands Qwen3's `/think` and `/no_think` switches.
bool qwen3Thinking(String? template) => template != null && template.contains('<think>');

const toolCallOpen = '<tool_call>';
const toolCallClose = '</tool_call>';

/// The system-prompt block for Hermes / Qwen tools (as the Qwen chat template renders it).
String hermesToolsBlock(List<ToolSpec> tools) {
  final b = StringBuffer()
    ..writeln('# Tools')
    ..writeln()
    ..writeln('You may call one or more functions to assist with the user query.')
    ..writeln()
    ..writeln('You are provided with function signatures within <tools></tools> XML tags:')
    ..writeln('<tools>');
  for (final t in tools) {
    b.writeln(jsonEncode({
      'type': 'function',
      'function': {'name': t.name, 'description': t.description, 'parameters': t.parameters.isEmpty ? {'type': 'object', 'properties': {}} : t.parameters},
    }));
  }
  b
    ..writeln('</tools>')
    ..writeln()
    ..writeln('For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:')
    ..writeln('<tool_call>')
    ..writeln('{"name": <function-name>, "arguments": <args-json-object>}')
    ..write('</tool_call>');
  return b.toString();
}

/// The system-prompt block for the grammar fallback (any instruction model).
String grammarToolsBlock(List<ToolSpec> tools, {required bool allowAnswer}) {
  final b = StringBuffer('You can use these tools:\n');
  for (final t in tools) {
    final props = (t.parameters['properties'] as Map?)?.keys.join(', ') ?? '';
    b.writeln('- ${t.name}($props): ${t.description}');
  }
  b.write(allowAnswer
      ? 'Reply with exactly one JSON object: {"tool": <name>, "arguments": {...}} to call a tool, or {"answer": "<text>"} to answer the user.'
      : 'Reply with exactly one JSON object: {"tool": <name>, "arguments": {...}}.');
  return b.toString();
}

/// Tool calls in a native reply: Hermes / Qwen `<tool_call>{…}</tool_call>` blocks, Granite `<|tool_call|>[…]`, or a
/// Llama-style bare `{"name": …, "parameters": …}`. Returns null when the text has a marker but no valid call.
({String text, List<ToolCall> calls})? parseNativeToolCalls(String raw, Set<String> toolNames, {int idBase = 0}) {
  final calls = <ToolCall>[];
  var text = raw;
  ToolCall? one(Object? j) {
    if (j is! Map) return null;
    final name = j['name'] ?? (j['function'] is Map ? (j['function'] as Map)['name'] : null);
    var args = j['arguments'] ?? j['parameters'] ?? (j['function'] is Map ? (j['function'] as Map)['arguments'] : null) ?? const {};
    if (args is String) {
      try {
        args = jsonDecode(args);
      } on FormatException {
        return null;
      }
    }
    if (name is! String || !toolNames.contains(name) || args is! Map) return null;
    return ToolCall(id: 'call_${idBase + calls.length}', name: name, arguments: args.cast<String, Object?>());
  }

  if (raw.contains(toolCallOpen)) {
    final re = RegExp(r'<tool_call>\s*([\s\S]*?)\s*(?:</tool_call>|$)');
    for (final m in re.allMatches(raw)) {
      try {
        final c = one(jsonDecode(m.group(1)!));
        if (c == null) return null;
        calls.add(c);
      } on FormatException {
        return null;
      }
    }
    text = raw.substring(0, raw.indexOf(toolCallOpen)).trim();
    return (text: text, calls: calls);
  }
  if (raw.contains('<|tool_call|>')) {
    final body = raw.substring(raw.indexOf('<|tool_call|>') + '<|tool_call|>'.length).trim();
    try {
      final j = jsonDecode(body);
      for (final x in j is List ? j : [j]) {
        final c = one(x);
        if (c == null) return null;
        calls.add(c);
      }
    } on FormatException {
      return null;
    }
    return (text: raw.substring(0, raw.indexOf('<|tool_call|>')).trim(), calls: calls);
  }
  final t = raw.trim();
  if (t.startsWith('{') && t.endsWith('}') && (t.contains('"parameters"') || t.contains('"arguments"'))) {
    try {
      final c = one(jsonDecode(t));
      if (c != null) return (text: '', calls: [c]);
    } on FormatException {
      // not a call: plain text
    }
  }
  return (text: raw, calls: const []);
}

/// The grammar-fallback reply: `{"tool": …, "arguments": …}` or `{"answer": …}`. null when it does not parse.
({String text, List<ToolCall> calls})? parseGrammarReply(String raw, Set<String> toolNames, {int idBase = 0}) {
  try {
    final j = jsonDecode(raw.trim());
    if (j is! Map) return null;
    if (j['answer'] case final String a) return (text: a, calls: const []);
    final name = j['tool'], args = j['arguments'];
    if (name is String && toolNames.contains(name) && args is Map) {
      return (text: '', calls: [ToolCall(id: 'call_$idBase', name: name, arguments: args.cast<String, Object?>())]);
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Removes a Qwen3 `<think>…</think>` block (also an unterminated one at the end).
String stripThink(String s) => s.replaceAll(RegExp(r'<think>[\s\S]*?(</think>|$)\s*'), '');

/// Streams the text of `{"answer": "…"}` as it is generated (the grammar fallback), decoding JSON string escapes.
class AnswerStreamer {
  final _buf = StringBuffer();
  int _pos = 0;
  bool? _isAnswer;
  bool _closed = false;

  /// Feeds a piece; returns the newly decoded answer text ('' when there is none yet).
  String feed(String piece) {
    _buf.write(piece);
    final s = _buf.toString();
    if (_isAnswer == null) {
      final m = RegExp(r'^\s*\{\s*"(answer|tool)"\s*:\s*"?').firstMatch(s);
      if (m == null) {
        if (s.trim().length > 12) _isAnswer = false;
        return '';
      }
      _isAnswer = m.group(1) == 'answer' && m.group(0)!.endsWith('"');
      if (_isAnswer != true) return '';
      _pos = m.end;
    }
    if (_isAnswer != true || _closed) return '';
    final out = StringBuffer();
    while (_pos < s.length) {
      final ch = s[_pos];
      if (ch == '"') {
        _closed = true;
        break;
      }
      if (ch == r'\') {
        if (_pos + 1 >= s.length) break;
        final e = s[_pos + 1];
        if (e == 'u') {
          if (_pos + 6 > s.length) break;
          out.writeCharCode(int.parse(s.substring(_pos + 2, _pos + 6), radix: 16));
          _pos += 6;
          continue;
        }
        out.write(switch (e) { 'n' => '\n', 't' => '\t', 'r' => '\r', 'b' => '\b', 'f' => '\f', _ => e });
        _pos += 2;
        continue;
      }
      out.write(ch);
      _pos++;
    }
    return out.toString();
  }

  String get raw => _buf.toString();

  /// Whether the reply is an answer whose text has started streaming.
  bool get started => _isAnswer == true;
}
