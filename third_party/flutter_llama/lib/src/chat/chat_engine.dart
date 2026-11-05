/// chat / chatStream with tools over any [LlamaBackend] (sdd-flutter-llama-agent 2.3).
///
/// Tool calls run natively when the model's template renders Hermes / Qwen tools, and through a grammar-constrained
/// JSON reply on every other instruction model. A reply whose tool call does not parse gets one constrained repair
/// retry, then [ToolParseFailed].
library;

import 'dart:async';
import 'dart:convert';

import '../backend/backend.dart';
import '../grammar/gbnf.dart';
import '../models/chat.dart';
import 'families.dart';

/// What the engine needs to know about the loaded model.
class ModelTraits {
  const ModelTraits({required this.template, required this.architecture, required this.name});
  final String? template;
  final String? architecture;
  final String? name;
  String? get family => templateFamily(template, architecture);
  bool get hasTemplate => template != null && template!.isNotEmpty;
  bool get nativeTools => hermesTools(template);
  bool get thinkingSwitch => qwen3Thinking(template);
}

enum _Mode { plain, native, grammar }

class LlamaChatEngine {
  LlamaChatEngine(this.backend);
  final LlamaBackend backend;

  Future<ModelTraits>? _traits;
  Future<void> _tail = Future.value();

  /// Forget the cached model traits (a new model was loaded).
  void invalidate() => _traits = null;

  Future<ModelTraits> traits() => _traits ??= () async {
        if (!await backend.isLoaded) {
          _traits = null;
          throw const ModelNotLoaded();
        }
        return ModelTraits(
          template: await backend.meta('tokenizer.chat_template'),
          architecture: await backend.meta('general.architecture'),
          name: await backend.meta('general.name'),
        );
      }();

  Future<ChatResult> chat(List<LlamaMessage> messages, [ChatParams params = const ChatParams()]) async {
    final text = StringBuffer();
    final calls = <ToolCall>[];
    ChatDone? done;
    await for (final c in chatStream(messages, params)) {
      switch (c) {
        case ChatText(text: final t):
          text.write(t);
        case ChatToolCalls(calls: final cs):
          calls.addAll(cs);
        case ChatDone():
          done = c;
      }
    }
    return ChatResult(text: text.toString(), toolCalls: calls, reason: done!.reason, usage: done.usage);
  }

  /// The rendered prompt (exposed for countChatTokens and tests).
  Future<String> render(List<LlamaMessage> messages, ChatParams params) async {
    final t = await traits();
    return _render(messages, params, t, _modeFor(params, t));
  }

  Stream<ChatChunk> chatStream(List<LlamaMessage> messages, [ChatParams params = const ChatParams()]) async* {
    final prev = _tail;
    final mine = Completer<void>();
    _tail = mine.future;
    await prev;
    try {
      yield* _run(messages, params);
    } finally {
      mine.complete();
    }
  }

  _Mode _modeFor(ChatParams p, ModelTraits t) {
    if (p.tools.isEmpty || p.toolChoice.isNone) return _Mode.plain;
    return t.nativeTools ? _Mode.native : _Mode.grammar;
  }

  List<ToolSpec> _offered(ChatParams p) {
    final n = p.toolChoice.name;
    if (n == null) return p.tools;
    final only = p.tools.where((t) => t.name == n).toList();
    if (only.isEmpty) throw ArgumentError.value(n, 'toolChoice', 'not one of the tools');
    return only;
  }

  Stream<ChatChunk> _run(List<LlamaMessage> messages, ChatParams p) async* {
    final t = await traits();
    final mode = _modeFor(p, t);
    final tools = mode == _Mode.plain ? const <ToolSpec>[] : _offered(p);
    final names = {for (final x in tools) x.name};
    final specs = [for (final x in tools) (name: x.name, parameters: x.parameters)];
    final required = p.toolChoice.isRequired;
    final prompt = await _render(messages, p, t, mode, offered: tools);

    final grammar = switch (mode) {
      _Mode.plain => p.grammar ?? (p.jsonSchema == null ? null : JsonSchemaGrammar.fromSchema(p.jsonSchema!)),
      _Mode.native => required ? nativeToolCallGrammar(specs) : null,
      _Mode.grammar => toolCallGrammar(specs, allowAnswer: !required),
    };
    final stop = [...p.stop, if (!t.hasTemplate && p.template == null) '\nUser:'];
    var promptTokens = 0, completionTokens = 0;

    // One attempt: streams text chunks and returns the raw reply and the stop reason.
    Stream<Object> attempt(String? g, int maxTokens, {required bool streamText}) async* {
      final think = _ThinkFilter(enabled: t.thinkingSwitch);
      final marker = _MarkerHold();
      final answer = AnswerStreamer();
      final raw = StringBuffer();
      var reason = ChatStopReason.eos;
      final sampling = RawSampling(temperature: p.temperature, topP: p.topP, topK: p.topK, repeatPenalty: p.repeatPenalty, maxTokens: maxTokens, seed: p.seed, stop: stop);
      await for (final e in backend.generate(prompt, sampling, grammar: g)) {
        if (e is RawDone) {
          reason = e.reason;
          promptTokens += e.promptTokens;
          completionTokens += e.completionTokens;
          continue;
        }
        final piece = e as String;
        raw.write(piece);
        if (!streamText) continue;
        final visible = think.feed(piece);
        if (visible.isEmpty) continue;
        final out = switch (mode) {
          _Mode.plain => visible,
          _Mode.native => marker.feed(visible),
          _Mode.grammar => answer.feed(visible),
        };
        if (out.isNotEmpty) yield ChatText(out);
      }
      if (streamText && mode != _Mode.grammar) {
        final rest = mode == _Mode.native ? marker.flushIfNoMarker(think.flush()) : think.flush();
        if (rest.isNotEmpty) yield ChatText(rest);
      }
      yield (raw: raw.toString(), reason: reason, answerStarted: answer.started);
    }

    ({String raw, ChatStopReason reason, bool answerStarted})? last;
    await for (final x in attempt(grammar, p.maxTokens, streamText: true)) {
      if (x is ChatChunk) {
        yield x;
      } else {
        last = x as ({String raw, ChatStopReason reason, bool answerStarted});
      }
    }
    var (:raw, :reason, :answerStarted) = last!;

    if (mode == _Mode.plain) {
      yield ChatDone(reason, ChatUsage(promptTokens: promptTokens, completionTokens: completionTokens));
      return;
    }

    var parsed = mode == _Mode.native ? parseNativeToolCalls(stripThink(raw), names) : parseGrammarReply(raw, names);
    if (parsed == null && mode == _Mode.grammar && answerStarted) {
      // A long answer cut by maxTokens: the text was already streamed; nothing to repair.
      yield ChatDone(reason, ChatUsage(promptTokens: promptTokens, completionTokens: completionTokens));
      return;
    }
    if (parsed == null || (required && parsed.calls.isEmpty)) {
      // One repair retry, constrained to a tool call (or the grammar reply), with room for the arguments.
      final g = mode == _Mode.native ? nativeToolCallGrammar(specs) : toolCallGrammar(specs, allowAnswer: !required);
      await for (final x in attempt(g, p.maxTokens * 2, streamText: false)) {
        if (x is! ChatChunk) {
          final r = x as ({String raw, ChatStopReason reason, bool answerStarted});
          raw = r.raw;
          reason = r.reason;
        }
      }
      parsed = mode == _Mode.native ? parseNativeToolCalls(raw, names) : parseGrammarReply(raw, names);
      if (parsed == null || (required && parsed.calls.isEmpty)) throw ToolParseFailed('tool_parse_failed', raw);
      if (parsed.calls.isEmpty && parsed.text.isNotEmpty) yield ChatText(parsed.text);
    } else if (mode == _Mode.grammar && parsed.calls.isEmpty && !answerStarted && parsed.text.isNotEmpty) {
      yield ChatText(parsed.text);
    }
    if (parsed.calls.isNotEmpty) yield ChatToolCalls(parsed.calls);
    yield ChatDone(parsed.calls.isNotEmpty ? ChatStopReason.toolCall : reason, ChatUsage(promptTokens: promptTokens, completionTokens: completionTokens));
  }

  Future<String> _render(List<LlamaMessage> messages, ChatParams p, ModelTraits t, _Mode mode, {List<ToolSpec>? offered}) async {
    final tools = offered ?? (mode == _Mode.plain ? const <ToolSpec>[] : _offered(p));
    final out = <({String role, String content})>[];
    final toolBlock = switch (mode) {
      _Mode.plain => null,
      _Mode.native => hermesToolsBlock(tools),
      _Mode.grammar => grammarToolsBlock(tools, allowAnswer: !p.toolChoice.isRequired),
    };
    var systemDone = toolBlock == null;
    for (final m in messages) {
      switch (m.role) {
        case LlamaRole.system:
          out.add((role: 'system', content: systemDone ? m.content : '${m.content}\n\n$toolBlock'));
          systemDone = true;
        case LlamaRole.user:
          out.add((role: 'user', content: m.content));
        case LlamaRole.assistant:
          final calls = switch (mode) {
            _Mode.native => [for (final c in m.toolCalls) '$toolCallOpen\n${jsonEncode({'name': c.name, 'arguments': c.arguments})}\n$toolCallClose'],
            _ => [for (final c in m.toolCalls) jsonEncode({'tool': c.name, 'arguments': c.arguments})],
          };
          out.add((role: 'assistant', content: [if (m.content.isNotEmpty) m.content, ...calls].join('\n')));
        case LlamaRole.tool:
          final body = mode == _Mode.native
              ? '<tool_response>\n${m.content}\n</tool_response>'
              : 'Result of ${m.name ?? 'the tool'}: ${m.content}';
          // Consecutive tool results share one user turn (as the Qwen template renders them).
          if (out.isNotEmpty && out.last.role == 'user' && out.last.content.startsWith(mode == _Mode.native ? '<tool_response>' : 'Result of ')) {
            final prev = out.removeLast();
            out.add((role: 'user', content: '${prev.content}\n$body'));
          } else {
            out.add((role: 'user', content: body));
          }
      }
    }
    if (!systemDone) out.insert(0, (role: 'system', content: toolBlock!));
    if (t.thinkingSwitch) {
      final i = out.lastIndexWhere((m) => m.role == 'user');
      if (i >= 0) out[i] = (role: 'user', content: '${out[i].content} ${p.thinking ? '/think' : '/no_think'}');
    }
    if (p.template == null && !t.hasTemplate) return _plain(out);
    return backend.applyTemplate(out, template: p.template?.value);
  }

  /// No template in the GGUF (GPT-2 style models such as braindler): `User:` / `Assistant:` turns.
  static String _plain(List<({String role, String content})> m) {
    final b = StringBuffer();
    for (final x in m) {
      b.writeln(switch (x.role) { 'system' => x.content, 'user' => 'User: ${x.content}', _ => 'Assistant: ${x.content}' });
    }
    b.write('Assistant:');
    return b.toString();
  }
}

/// Drops a leading Qwen3 `<think>…</think>` block from a stream.
class _ThinkFilter {
  _ThinkFilter({required this.enabled});
  final bool enabled;
  final _buf = StringBuffer();
  bool _decided = false;
  bool _trimLead = false;

  String feed(String piece) {
    if (!enabled) return piece;
    if (_decided) {
      if (!_trimLead) return piece;
      final t = piece.trimLeft();
      if (t.isNotEmpty) _trimLead = false;
      return t;
    }
    _buf.write(piece);
    final s = _buf.toString();
    final lead = s.trimLeft();
    if (lead.isEmpty || '<think>'.startsWith(lead)) return '';
    if (!lead.startsWith('<think>')) {
      _decided = true;
      return s;
    }
    final end = s.indexOf('</think>');
    if (end < 0) return '';
    _decided = true;
    final rest = s.substring(end + '</think>'.length).trimLeft();
    _trimLead = rest.isEmpty;
    return rest;
  }

  /// What is left when the stream ends (an unfinished think block yields nothing).
  String flush() {
    if (!enabled || _decided) return '';
    final lead = _buf.toString().trimLeft();
    return lead.startsWith('<think>') || '<think>'.startsWith(lead) ? '' : lead;
  }
}

/// Streams text until a tool-call marker; holds back a suffix that may start one.
class _MarkerHold {
  static const _markers = [toolCallOpen, '<|tool_call|>'];
  final _held = StringBuffer();
  bool _inCall = false;

  String feed(String piece) {
    if (_inCall) return '';
    _held.write(piece);
    final s = _held.toString();
    for (final m in _markers) {
      final i = s.indexOf(m);
      if (i >= 0) {
        _inCall = true;
        _held.clear();
        return s.substring(0, i).trimRight();
      }
    }
    var keep = 0;
    for (final m in _markers) {
      for (var k = m.length - 1; k > keep; k--) {
        if (s.length >= k && s.endsWith(m.substring(0, k))) {
          keep = k;
          break;
        }
      }
    }
    // Whitespace right before a possible marker is held too (it is trimmed if the marker follows).
    while (keep < s.length && s[s.length - keep - 1].trim().isEmpty) {
      keep++;
    }
    _held.clear();
    _held.write(s.substring(s.length - keep));
    return s.substring(0, s.length - keep);
  }

  String flushIfNoMarker(String tail) {
    if (_inCall) return '';
    final s = feed(tail);
    if (_inCall) return s;
    final rest = _held.toString();
    _held.clear();
    return s + rest;
  }
}
