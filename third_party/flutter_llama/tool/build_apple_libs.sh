#!/usr/bin/env bash
# Builds the llama.cpp static libraries the iOS / macOS pods link (ios/ios_libs, macos/macos_libs) at the commit pinned in
# src/core/CMakeLists.txt, and packs them with the llama.cpp headers for the package registry / GitLab release
# (.gitlab-ci.yml). Binaries are never committed; the podspecs fetch the archive (tool/fetch_apple_libs.sh).
# Needs macOS with Xcode and cmake.
#   tool/build_apple_libs.sh [llama.cpp dir] [out dir]
#     → <out>/flutter_llama-apple-libs.tar.gz (+ .sha256), and the libraries installed into ios/ios_libs, macos/macos_libs
# The llama.cpp dir defaults to the checkout next to the package; it is cloned at the pinned commit when empty.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(sed -n 's/^set(FL_LLAMA_CPP_COMMIT \([0-9a-f]*\)).*/\1/p' "$root/src/core/CMakeLists.txt")"
src="${1:-$root/llama.cpp}"
out="${2:-$root/build/apple-libs}"
libs=(llama ggml ggml-base ggml-cpu ggml-metal ggml-blas)

if [ ! -f "$src/CMakeLists.txt" ]; then
  mkdir -p "$src"
  git -C "$src" init -q
  git -C "$src" fetch -q --depth 1 https://github.com/ggml-org/llama.cpp.git "$commit"
  git -C "$src" checkout -q FETCH_HEAD
fi
have="$(git -C "$src" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$have" != "$commit" ]; then
  echo "error: $src is at $have, src/core/CMakeLists.txt pins $commit" >&2
  exit 1
fi

common=(
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DGGML_NATIVE=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON -DGGML_BLAS=ON
  -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF
)

build() { # <platform> <cmake args...>: builds into $out/build-<platform>, collects the libraries into $out/stage/<platform>_libs
  local platform="$1"; shift
  local dir="$out/build-$platform" stage="$out/stage/${platform}_libs"
  cmake -S "$src" -B "$dir" "${common[@]}" "$@"
  cmake --build "$dir" --config Release --target llama -j "$(sysctl -n hw.ncpu)"
  mkdir -p "$stage"
  for lib in "${libs[@]}"; do
    local file
    file="$(find "$dir" -name "lib$lib.a" -print -quit)"
    [ -n "$file" ] || { echo "error: lib$lib.a was not built for $platform" >&2; exit 1; }
    cp "$file" "$stage/"
  done
}

rm -rf "$out/stage"
build ios -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
build macos "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15

mkdir -p "$out/stage/include"
cp "$src"/include/*.h "$src"/ggml/include/*.h "$out/stage/include/"
echo "$commit" > "$out/stage/LLAMA_CPP_COMMIT"

archive="$out/flutter_llama-apple-libs.tar.gz"
tar -czf "$archive" -C "$out/stage" .
(cd "$out" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")

# Install into this checkout too, so a local build is used as is.
for platform in ios macos; do
  dest="$root/$platform/${platform}_libs"
  rm -rf "$dest" && mkdir -p "$dest"
  cp "$out/stage/${platform}_libs/"*.a "$dest/"
  cp -R "$out/stage/include" "$dest/include"
done
echo "$archive"
