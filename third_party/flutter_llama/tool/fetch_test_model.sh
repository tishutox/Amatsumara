#!/usr/bin/env bash
# The tiny open model for core / smoke tests (sdd-flutter-llama-agent 0.1): SmolLM2-135M-Instruct Q4_K_M (Apache-2.0,
# base HuggingFaceTB/SmolLM2-135M-Instruct). Downloaded to a cache outside the package (never committed / published).
#   tool/fetch_test_model.sh            → prints the path
# FLUTTER_LLAMA_TEST_MODELS overrides the cache directory (default ~/.cache/flutter_llama/test_models).
set -euo pipefail
dir="${FLUTTER_LLAMA_TEST_MODELS:-$HOME/.cache/flutter_llama/test_models}"
file="$dir/SmolLM2-135M-Instruct-Q4_K_M.gguf"
url="https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf"
mkdir -p "$dir"
if [ ! -s "$file" ]; then
  curl -fL --retry 3 -C - -o "$file.part" "$url" >&2
  mv "$file.part" "$file"
fi
echo "$file"
