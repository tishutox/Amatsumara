/// GBNF grammars for constrained generation (sdd-flutter-llama-agent 2.2): JSON schema → GBNF, the tool-call
/// grammar and the label-choice grammar. Pure Dart, so every platform gets the same grammar.
library;

import 'dart:convert';

/// Thrown when a schema uses something the converter does not support.
class GrammarSchemaException implements Exception {
  GrammarSchemaException(this.message);
  final String message;
  @override
  String toString() => 'GrammarSchemaException: $message';
}

const _primitives = r'''
ws ::= [ \t\n]{0,8}
string ::= "\"" char* "\""
char ::= [^"\\\x00-\x1f] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
integer ::= "-"? ("0" | [1-9] [0-9]{0,15})
number ::= integer ("." [0-9]{1,16})? ([eE] [-+]? [0-9]{1,4})?
boolean ::= "true" | "false"
null ::= "null"
value ::= object-any | array-any | string | number | boolean | null
object-any ::= "{" ws (string ws ":" ws value (ws "," ws string ws ":" ws value)*)? ws "}"
array-any ::= "[" ws (value (ws "," ws value)*)? ws "]"
''';

/// Converts JSON schemas to GBNF rules. Supported: `type` (string, number, integer, boolean, null, object, array, or a
/// list of types), `enum`, `const`, `properties` + `required` (other properties are not allowed; required ones come first in
/// the declared order, then optional ones may follow), `items`, `minItems` / `maxItems` (≤ 32), `anyOf` / `oneOf`, an empty schema (any
/// JSON value), `description` (ignored).
class JsonSchemaGrammar {
  final _rules = <String, String>{};
  var _n = 0;

  /// A grammar whose root is [schema].
  static String fromSchema(Map<String, Object?> schema) {
    final g = JsonSchemaGrammar();
    final root = g.rule(schema, 'root-value');
    return g.render('root ::= ws $root ws');
  }

  /// Adds the rules for [schema] and returns the rule name to reference.
  String rule(Map<String, Object?> schema, String hint) {
    if (schema.containsKey('const')) return _add(hint, _literal(schema['const']));
    final en = schema['enum'];
    if (en is List) {
      if (en.isEmpty) throw GrammarSchemaException('enum is empty');
      return _add(hint, en.map(_literal).join(' | '));
    }
    for (final key in ['anyOf', 'oneOf']) {
      final alts = schema[key];
      if (alts is List) {
        final names = [for (final (i, a) in alts.indexed) rule(_map(a), '$hint-$i')];
        return _add(hint, names.join(' | '));
      }
    }
    final type = schema['type'];
    if (type is List) {
      final names = [for (final t in type) rule({...schema, 'type': t}, '$hint-$t')];
      return _add(hint, names.join(' | '));
    }
    switch (type) {
      case null:
        return schema.containsKey('properties') ? _object(schema, hint) : 'value';
      case 'string':
        return 'string';
      case 'integer':
        return 'integer';
      case 'number':
        return 'number';
      case 'boolean':
        return 'boolean';
      case 'null':
        return 'null';
      case 'object':
        return _object(schema, hint);
      case 'array':
        return _array(schema, hint);
      default:
        throw GrammarSchemaException('unsupported type "$type"');
    }
  }

  String _object(Map<String, Object?> schema, String hint) {
    final props = _map(schema['properties']);
    if (props.isEmpty) return 'object-any';
    final required = {for (final r in schema['required'] as List? ?? const []) '$r'};
    final req = <String>[], opt = <String>[];
    for (final MapEntry(:key, :value) in props.entries) {
      final p = '${_literal(key)} ws ":" ws ${rule(_map(value), '$hint-${_slug(key)}')}';
      (required.contains(key) ? req : opt).add(p);
    }
    if (req.isEmpty) return _add(hint, _allOptional(opt));
    // Required properties first (declared order), then each optional one may follow.
    final body = ['"{" ws', req.join(' ws "," ws '), for (final o in opt) '(ws "," ws $o)?', 'ws "}"'].join(' ');
    return _add(hint, body);
  }

  String _allOptional(List<String> items) {
    // "{" ws ( a (ws "," ws b)? … | b … )? ws "}" — every non-empty in-order subset.
    String chain(int from) {
      final alts = <String>[];
      for (var i = from; i < items.length; i++) {
        final rest = i + 1 < items.length ? ' (ws "," ws (${chain(i + 1)}))?' : '';
        alts.add('${items[i]}$rest');
      }
      return alts.join(' | ');
    }
    return '"{" ws (${chain(0)})? ws "}"';
  }

  String _array(Map<String, Object?> schema, String hint) {
    final item = schema.containsKey('items') ? rule(_map(schema['items']), '$hint-item') : 'value';
    final min = (schema['minItems'] as num?)?.toInt() ?? 0;
    final max = (schema['maxItems'] as num?)?.toInt();
    if (min > 32 || (max != null && max > 32)) throw GrammarSchemaException('minItems / maxItems above 32');
    String body;
    if (max == 0) {
      body = '"[" ws "]"';
    } else if (min == 0 && max == null) {
      body = '"[" ws ($item (ws "," ws $item)*)? ws "]"';
    } else {
      final rest = max == null ? '(ws "," ws $item)*' : '(ws "," ws $item){${min == 0 ? 0 : min - 1},${max - 1}}';
      body = min == 0 ? '"[" ws ($item $rest)? ws "]"' : '"[" ws $item $rest ws "]"';
    }
    return _add(hint, body);
  }

  String _add(String hint, String body) {
    final name = '${_slug(hint)}-${_n++}';
    _rules[name] = body;
    return name;
  }

  String render(String rootRule) => [rootRule, for (final MapEntry(:key, :value) in _rules.entries) '$key ::= $value', _primitives.trim()].join('\n');

  static Map<String, Object?> _map(Object? v) => v is Map ? v.cast<String, Object?>() : <String, Object?>{};
  static String _slug(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

  /// A GBNF literal for a JSON value (strings quoted and escaped).
  static String _literal(Object? v) => '"${jsonEncode(v).replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// The tool-call grammar: exactly one of `{"tool": "<name>", "arguments": <that tool's schema>}` or
/// `{"answer": "<text>"}` (when [allowAnswer]).
String toolCallGrammar(List<({String name, Map<String, Object?> parameters})> tools, {bool allowAnswer = true}) {
  if (tools.isEmpty && !allowAnswer) throw GrammarSchemaException('no tools and no answer allowed');
  final g = JsonSchemaGrammar();
  final alts = <String>[];
  for (final t in tools) {
    final args = g.rule(t.parameters.isEmpty ? {'type': 'object'} : t.parameters, 'args-${t.name}');
    alts.add('"{" ws "\\"tool\\"" ws ":" ws ${JsonSchemaGrammar._literal(t.name)} ws "," ws "\\"arguments\\"" ws ":" ws $args ws "}"');
  }
  if (allowAnswer) alts.add('"{" ws "\\"answer\\"" ws ":" ws string ws "}"');
  return g.render('root ::= ws (${alts.join(' | ')}) ws');
}

/// The native (Qwen / Hermes) tool-call form: `<tool_call>\n{"name": "<name>", "arguments": {…}}\n</tool_call>`, used
/// when a tool call is required on a model whose template renders tools natively.
String nativeToolCallGrammar(List<({String name, Map<String, Object?> parameters})> tools) {
  if (tools.isEmpty) throw GrammarSchemaException('no tools');
  final g = JsonSchemaGrammar();
  final alts = <String>[];
  for (final t in tools) {
    final args = g.rule(t.parameters.isEmpty ? {'type': 'object'} : t.parameters, 'args-${t.name}');
    alts.add('"{" ws "\\"name\\"" ws ":" ws ${JsonSchemaGrammar._literal(t.name)} ws "," ws "\\"arguments\\"" ws ":" ws $args ws "}"');
  }
  return g.render('root ::= "<tool_call>\\n" (${alts.join(' | ')}) "\\n</tool_call>"');
}

/// One label out of [labels], verbatim.
String labelChoiceGrammar(List<String> labels) {
  if (labels.isEmpty) throw GrammarSchemaException('no labels');
  final alts = labels.map((l) => '"${l.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"').join(' | ');
  return 'root ::= $alts';
}
