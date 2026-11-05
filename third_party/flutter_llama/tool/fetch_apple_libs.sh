#!/usr/bin/env bash
# Puts the prebuilt llama.cpp static libraries and headers for one Apple platform in place (ios/ios_libs or
# macos/macos_libs). Run by the podspecs at `pod install`; a no-op when they are already there (a local
# tool/build_apple_libs.sh build). The archive is built by .gitlab-ci.yml and kept in the project's package registry,
# keyed by the llama.cpp commit pinned in src/core/CMakeLists.txt.
#   tool/fetch_apple_libs.sh ios|macos
# FLUTTER_LLAMA_APPLE_LIBS_URL overrides the archive URL (a mirror, or file:///path/flutter_llama-apple-libs.tar.gz).
set -euo pipefail
platform="${1:?usage: fetch_apple_libs.sh ios|macos}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/$platform/${platform}_libs"
libs=(llama ggml ggml-base ggml-cpu ggml-metal ggml-blas)

present=1
for lib in "${libs[@]}"; do [ -f "$dest/lib$lib.a" ] || present=0; done
[ -f "$dest/include/llama.h" ] || present=0
[ "$present" = 0 ] || exit 0

commit="$(sed -n 's/^set(FL_LLAMA_CPP_COMMIT \([0-9a-f]*\)).*/\1/p' "$root/src/core/CMakeLists.txt")"
url="${FLUTTER_LLAMA_APPLE_LIBS_URL:-https://gitlab.com/api/v4/projects/libsFlutter%2Fflutter_llama/packages/generic/llama-apple-libs/${commit:0:12}/flutter_llama-apple-libs.tar.gz}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "flutter_llama: fetching llama.cpp ${commit:0:12} libraries for $platform from $url" >&2
curl -fsSL --retry 3 -o "$tmp/libs.tar.gz" "$url"
if [[ "$url" != file://* ]]; then
  curl -fsSL --retry 3 -o "$tmp/libs.sha256" "$url.sha256"
  echo "$(cut -d' ' -f1 "$tmp/libs.sha256")  $tmp/libs.tar.gz" | shasum -a 256 -c -s
fi
mkdir -p "$tmp/x"
tar -xzf "$tmp/libs.tar.gz" -C "$tmp/x"

rm -rf "$dest" && mkdir -p "$dest"
cp "$tmp/x/${platform}_libs/"*.a "$dest/"
cp -R "$tmp/x/include" "$dest/include"
