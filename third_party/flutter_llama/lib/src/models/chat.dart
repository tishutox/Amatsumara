/// Chat, tools and capability models (sdd-flutter-llama-agent 2.1).
library;

/// Who wrote a message.
enum LlamaRole { system, user, assistant, tool }

/// One chat message. Assistant messages can carry [toolCalls]; tool results carry [toolCallId] and [name].
class LlamaMessage {
  const LlamaMessage(this.role, this.content, {this.toolCalls = const [], this.toolCallId, this.name});
  const LlamaMessage.system(String content) : this(LlamaRole.system, content);
  const LlamaMessage.user(String content) : this(LlamaRole.user, content);
  const LlamaMessage.assistant(String content, {List<ToolCall> toolCalls = const []}) : this(LlamaRole.assistant, content, toolCalls: toolCalls);
  const LlamaMessage.tool(String content, {required String toolCallId, String? name}) : this(LlamaRole.tool, content, toolCallId: toolCallId, name: name);

  final LlamaRole role;
  final String content;
  final List<ToolCall> toolCalls;
  final String? toolCallId;
  final String? name;
}

/// A tool the model may call: [parameters] is a JSON schema.
class ToolSpec {
  const ToolSpec({required this.name, required this.description, this.parameters = const {}});
  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

/// A call the model made.
class ToolCall {
  const ToolCall({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;
  final Map<String, Object?> arguments;
  @override
  String toString() => 'ToolCall($name, $arguments)';
}

/// When the model may call tools.
sealed class ToolChoice {
  const ToolChoice();
  static const auto = _Auto();
  static const none = _None();
  static const required = _Required();
  const factory ToolChoice.named(String name) = _Named;
}
class _Auto extends ToolChoice { const _Auto(); }
class _None extends ToolChoice { const _None(); }
class _Required extends ToolChoice { const _Required(); }
class _Named extends ToolChoice { const _Named(this.name); final String name; }
extension ToolChoiceX on ToolChoice {
  bool get isNone => this is _None;
  bool get isRequired => this is _Required || this is _Named;
  String? get name => switch (this) { _Named(:final name) => name, _ => null };
}

/// A chat template override: a llama.cpp built-in name (`chatml`, `llama3`, `gemma`, `phi3`, `mistral-v7`, …) or a
/// template string. null in [ChatParams] = the model's own.
class ChatTemplate {
  const ChatTemplate(this.value);
  final String value;
  static const chatml = ChatTemplate('chatml');
  static const llama3 = ChatTemplate('llama3');
  static const gemma = ChatTemplate('gemma');
  static const phi3 = ChatTemplate('phi3');
}

/// Sampling and chat options.
class ChatParams {
  const ChatParams({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.maxTokens = 512,
    this.repeatPenalty = 1.1,
    this.seed = 0,
    this.stop = const [],
    this.tools = const [],
    this.toolChoice = ToolChoice.auto,
    this.grammar,
    this.jsonSchema,
    this.template,
    this.thinking = false,
  });
  final double temperature;
  final double topP;
  final int topK;
  final int maxTokens;
  final double repeatPenalty;
  final int seed;
  final List<String> stop;
  final List<ToolSpec> tools;
  final ToolChoice toolChoice;

  /// GBNF; wins over [jsonSchema].
  final String? grammar;
  final Map<String, Object?>? jsonSchema;
  final ChatTemplate? template;

  /// Reasoning on / off for models that support it (Qwen3: `/think` / `/no_think`).
  final bool thinking;
}

enum ChatStopReason { eos, maxTokens, stopString, cancelled, toolCall }

class ChatUsage {
  const ChatUsage({required this.promptTokens, required this.completionTokens});
  final int promptTokens;
  final int completionTokens;
}

/// A piece of a streamed reply.
sealed class ChatChunk { const ChatChunk(); }
class ChatText extends ChatChunk { const ChatText(this.text); final String text; }
class ChatToolCalls extends ChatChunk { const ChatToolCalls(this.calls); final List<ToolCall> calls; }
class ChatDone extends ChatChunk { const ChatDone(this.reason, this.usage); final ChatStopReason reason; final ChatUsage usage; }

/// A whole reply.
class ChatResult {
  const ChatResult({required this.text, this.toolCalls = const [], required this.reason, required this.usage});
  final String text;
  final List<ToolCall> toolCalls;
  final ChatStopReason reason;
  final ChatUsage usage;
}

/// What the loaded model is (from GGUF meta and the core's facts).
class ModelInfo {
  const ModelInfo({
    required this.architecture,
    required this.parameters,
    required this.quantization,
    required this.contextLength,
    required this.trainedContext,
    required this.hasChatTemplate,
    required this.templateFamily,
    required this.nativeToolCalls,
    required this.fileSize,
    this.description = '',
    this.gguf = const {},
  });
  final String architecture;
  final int parameters;

  /// e.g. Q4_K_M (from the core's model description).
  final String quantization;

  /// The loaded context.
  final int contextLength;
  final int trainedContext;
  final bool hasChatTemplate;

  /// chatml | llama3 | gemma | phi3 | mistral | granite | gpt2-plain | custom; null when unknown.
  final String? templateFamily;

  /// Whether the model's template renders tools natively (Qwen3 / Granite / Llama style).
  final bool nativeToolCalls;
  final int fileSize;
  final String description;

  /// GGUF `general.*` values (name, license, languages, base model) when present.
  final Map<String, String> gguf;
}

/// Whether a model fits this device.
class DeviceFit {
  const DeviceFit({required this.ok, required this.needBytes, required this.availableBytes, this.reason});
  final bool ok;
  final int needBytes;
  final int availableBytes;

  /// too_large_ram | too_large_disk | unsupported_platform | unknown_memory
  final String? reason;
}

class ClassifyParams {
  const ClassifyParams({this.instructions, this.examples = const {}, this.method = ClassifyMethod.logprob});
  final String? instructions;

  /// label → example texts (few-shot for logprob, centroids for embedding).
  final Map<String, List<String>> examples;
  final ClassifyMethod method;
}
enum ClassifyMethod { logprob, embedding }

class ClassifyResult {
  const ClassifyResult({required this.label, required this.scores, required this.took});
  final String label;

  /// Probabilities over the labels (sum to 1).
  final Map<String, double> scores;
  final Duration took;
}

/// Typed errors of the 1.2 API.
sealed class LlamaError implements Exception {
  const LlamaError(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}
class UnsupportedPlatform extends LlamaError { const UnsupportedPlatform([super.message = 'On-device models are not available on this platform.']); }
class ModelNotLoaded extends LlamaError { const ModelNotLoaded([super.message = 'Load a model first.']); }
class ModelTooLarge extends LlamaError { const ModelTooLarge(super.message, this.fit); final DeviceFit fit; }
class GrammarInvalid extends LlamaError { const GrammarInvalid(super.message); }
class ContextOverflow extends LlamaError { const ContextOverflow(super.message); }
class Cancelled extends LlamaError { const Cancelled([super.message = 'Generation was stopped.']); }
class TemplateUnavailable extends LlamaError { const TemplateUnavailable([super.message = 'The model has no chat template; pass ChatParams.template.']); }
/// A reply that should hold a tool call did not parse, even after the repair retry (`tool_parse_failed`).
class ToolParseFailed extends LlamaError { const ToolParseFailed(super.message, this.raw); final String raw; }
class NativeFailure extends LlamaError { const NativeFailure(super.message, [this.code]); final int? code; }
