# Status: sdd-flutter-llama-agent

## Current Phase

IMPLEMENTATION

## Phase Status

IN PROGRESS (0.1, 1.1, 2.1–2.4, 3.1, 4.1 done on Linux; 3.2 Windows code ready (needs a machine); 4.2 example + docs done (Linux build, 2026-10-11); GPU auto policy on Android; 1.2 Android, 1.3 iOS / macOS wait for the SDK / MacBook)

## Last Updated

2026-10-08 by Claude Code

## Blockers

- Owner review of `01-requirements.md` (questions F1–F5).

## Progress

- [x] Requirements drafted (v0.1, 2026-10-08)
- [x] Requirements approved (2026-10-08, v0.3)
- [x] Specifications drafted (v0.1, 2026-10-08; questions S1–S3)
- [x] Specifications approved (2026-10-08)
- [x] Plan drafted (v0.1, 2026-10-08)
- [x] Plan approved (2026-10-08)
- [x] Implementation started (2026-10-08)
- [ ] Implementation complete

## Context Notes

- **Owner 2026-10-11: «публиковать flutter_llama 1.2.1 - да. По flutter_llama - еще и коммить и пушь самостоятельно (все остальные git - на мне)».** For this repository only, Claude commits and pushes itself. Every other repository's git stays with the owner.

- **Published 2026-10-11 (owner command):** flutter_llama 1.2.0, nativemind_core 0.1.1, nativemind_copilot 0.2.0 on pub.dev (`flutter pub publish`, from this server with the owner's credentials). The other widgets packages are unchanged at their published versions.

- **Owner 2026-10-11: «Опубликуй текущие widgets и fluter_llama в pub.dev».** On pub.dev today:
  - unchanged, nothing to publish: nativemind_widgets 0.5.0, fugue, nativemind_icons_fugue and nativemind_translations
    0.1.0 (the local code equals the published archives);
  - changed: flutter_llama → **1.2.0**, nativemind_core → **0.1.1** (3 icons added; the copies in
    nativemind_icons_fugue were restored, so that package stays as published), nativemind_copilot → **0.2.0**.

  Order (dependencies): flutter_llama 1.2.0 → nativemind_core 0.1.1 → nativemind_copilot 0.2.0. Dry runs pass, with
  only the "modified in git" warnings. This server has no pub.dev credentials: the owner logs in.

- Created 2026-10-08 by owner command. While extending `nativemind_copilot` with on-device models
  (`widgets.nativemind.net/flows/sdd-nativemind-copilot` item 15), the owner said: «flutter_llama — универсальный
  инструмент, нужно использовать именно его, а при необходимости доработать именно его, создав у него дополнительный
  sdd flow». Every model-side capability an agent needs is added here, not worked around in consumers.
- Consumers:
  - `nativemind_copilot` (agent loop with tools, decisions, streaming);
  - through it, the LienDeed apps (Pro, Academy, Scout on device, Circle).
- Code facts (2026-10-08):
  - `flutter_llama` 1.1.2 (same on pub.dev); Android (Kotlin + JNI, `android/src/main/cpp/flutter_llama_bridge.cpp`),
    iOS / macOS (Swift + `ios/Classes/llama_cpp_bridge.mm`, `llama.xcframework`); vendored llama.cpp `945501f5e`
    (2025-10-27).
  - Dart API: `loadModel`, `generate`, `generateStream`, `stopGeneration`, `getModelInfo`, auto-download / presets
    (Hugging Face, Ollama).
  - `GenerationParams` = prompt, temperature, top-p / top-k, maxTokens, repeatPenalty, stopSequences.
  - The bridges tokenize the raw prompt. The bundled `llama.h` has `llama_chat_apply_template` and the grammar
    sampler, but neither is used. There is no chat API, no structured output, no token count, no capability metadata.
  - No web, Linux or Windows implementation.
- Provenance: commits by the owner. The repo's status documents (`IMPLEMENTATION_STATUS.md` etc.) read as generated; the
  code is the source of truth.
- Rules: git belongs to the owner (no git writes). The working tree has the owner's uncommitted changes; do not touch
  them. Licence: NativeMindNONC.

## Next Actions

1. Owner review of requirements v0.1 (F1–F5).

- Owner 2026-10-08:
  - F3: open models only; the package under NativeMindNONC;
  - F4: desktop Windows / Linux / macOS in this flow.
  Requirements v0.2. Model recommendations per OS and for liendeed.us: given in chat, to go into specs.
