#!/usr/bin/env bash
# Builds the llama.cpp shared libraries that llama_cpp_dart loads on Android.
#
# llama_cpp_dart's C bindings are generated against ONE llama.cpp revision and
# the struct layouts change between revisions, so the commit below must match
# the llama_cpp_dart version in pubspec.yaml (0.2.2 -> 4ffc47c). Bump both
# together; never drop in a newer libllama.so on its own.
#
# Usage:
#   ANDROID_NDK_HOME=/path/to/ndk scripts/build_android_libs.sh [abi...]
#   (default ABIs: arm64-v8a x86_64)
#
# Options (environment):
#   OUT_DIR       where jniLibs are written (default: example/android/app/src/main/jniLibs)
#   LLAMA_SRC     existing llama.cpp checkout to build (default: cloned into build/llama.cpp)
#   ANDROID_PLATFORM  default android-28
#   JOBS          parallel jobs (default: nproc)
set -euo pipefail

LLAMA_CPP_COMMIT="4ffc47cb2001e7d523f9ff525335bbe34b1a2858"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/example/android/app/src/main/jniLibs}"
LLAMA_SRC="${LLAMA_SRC:-$ROOT/build/llama.cpp}"
PLATFORM="${ANDROID_PLATFORM:-android-28}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"
ABIS=("$@")
[ ${#ABIS[@]} -eq 0 ] && ABIS=(arm64-v8a x86_64)

: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an Android NDK (r26+ recommended)}"
TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
[ -f "$TOOLCHAIN" ] || { echo "NDK toolchain not found at $TOOLCHAIN" >&2; exit 1; }

if [ ! -d "$LLAMA_SRC/.git" ]; then
  mkdir -p "$LLAMA_SRC"
  git -C "$LLAMA_SRC" init -q
  git -C "$LLAMA_SRC" remote add origin https://github.com/ggml-org/llama.cpp.git
fi
if [ "$(git -C "$LLAMA_SRC" rev-parse HEAD 2>/dev/null || true)" != "$LLAMA_CPP_COMMIT" ]; then
  git -C "$LLAMA_SRC" fetch -q --depth 1 origin "$LLAMA_CPP_COMMIT"
  git -C "$LLAMA_SRC" checkout -q FETCH_HEAD
fi

for abi in "${ABIS[@]}"; do
  build="$ROOT/build/android-$abi"
  extra=()
  # armv8.2 + dotprod covers phones from ~2018 on and enables the fast int8 kernels.
  [ "$abi" = "arm64-v8a" ] && extra+=(-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod)

  cmake -S "$LLAMA_SRC" -B "$build" -G "${CMAKE_GENERATOR:-Unix Makefiles}" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM="$PLATFORM" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_BUILD_TOOLS=ON \
    "${extra[@]}"
  cmake --build "$build" --config Release -j "$JOBS" --target llama mtmd

  dest="$OUT_DIR/$abi"
  mkdir -p "$dest"
  rm -f "$dest"/*.so
  find "$build/bin" -maxdepth 1 -name '*.so' -exec cp {} "$dest/" \;
  "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-strip --strip-unneeded "$dest"/*.so
  echo "== $abi =="; ls -la "$dest"
done

echo "Done. llama.cpp $LLAMA_CPP_COMMIT built into $OUT_DIR"
