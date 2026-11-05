/// classify (sdd-flutter-llama-agent 2.4): log-probabilities of each label as the assistant's reply (default), or
/// embedding centroids of the examples.
library;

import 'dart:math' as math;

import '../models/chat.dart';
import 'chat_engine.dart';

extension LlamaClassify on LlamaChatEngine {
  Future<ClassifyResult> classify(String text, List<String> labels, [ClassifyParams params = const ClassifyParams()]) async {
    if (labels.length < 2) throw ArgumentError.value(labels, 'labels', 'needs at least two labels');
    final sw = Stopwatch()..start();
    final List<double> scores;
    switch (params.method) {
      case ClassifyMethod.logprob:
        final prompt = await classifyPrompt(text, labels, params);
        scores = softmax(await backend.labelLogprobs(prompt, labels));
      case ClassifyMethod.embedding:
        final missing = [for (final l in labels) if ((params.examples[l] ?? const []).isEmpty) l];
        if (missing.isNotEmpty) throw ArgumentError.value(missing, 'examples', 'the embedding method needs examples for every label');
        final v = await backend.embed(text);
        final sims = <double>[];
        for (final l in labels) {
          final c = centroid([for (final e in params.examples[l]!) await backend.embed(e)]);
          sims.add(cosine(v, c));
        }
        // Cosine similarities are close together; a temperature of 0.05 turns them into usable probabilities.
        scores = softmax([for (final s in sims) s / 0.05]);
    }
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    return ClassifyResult(label: labels[best], scores: {for (var i = 0; i < labels.length; i++) labels[i]: scores[i]}, took: sw.elapsed);
  }

  /// The shared prefix: instructions, few-shot turns, the text, then the assistant turn the label continues.
  Future<String> classifyPrompt(String text, List<String> labels, ClassifyParams params) async {
    final t = await traits();
    final system = [
      if (params.instructions != null) params.instructions!,
      'Classify the text. Reply with exactly one of: ${labels.join(', ')}.',
    ].join('\n');
    final msgs = <LlamaMessage>[LlamaMessage.system(system)];
    for (final l in labels) {
      for (final e in params.examples[l] ?? const <String>[]) {
        msgs
          ..add(LlamaMessage.user(e))
          ..add(LlamaMessage.assistant(l));
      }
    }
    msgs.add(LlamaMessage.user(text));
    var prompt = await render(msgs, const ChatParams());
    // Qwen3 would open a think block; the label must follow the turn directly.
    if (t.thinkingSwitch) prompt += '<think>\n\n</think>\n\n';
    if (!t.hasTemplate) prompt += ' ';
    return prompt;
  }
}

List<double> softmax(List<double> xs) {
  final m = xs.reduce(math.max);
  final e = [for (final x in xs) math.exp(x - m)];
  final s = e.fold<double>(0, (a, b) => a + b);
  return [for (final x in e) x / s];
}

List<double> centroid(List<List<double>> vs) {
  final c = List<double>.filled(vs.first.length, 0);
  for (final v in vs) {
    for (var i = 0; i < c.length; i++) {
      c[i] += v[i] / vs.length;
    }
  }
  return c;
}

double cosine(List<double> a, List<double> b) {
  var d = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    d += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na == 0 || nb == 0 ? 0 : d / math.sqrt(na * nb);
}
