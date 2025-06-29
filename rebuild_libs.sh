#!/bin/bash
# rebuild_native_libs.sh

set -e

# Use NDK 25.2.9519653
NDK_BASE="/Users/mohammedaymaan/Library/Android/sdk/ndk"
NDK_VERSION="25.2.9519653"
export ANDROID_NDK_HOME="$NDK_BASE/$NDK_VERSION"

echo "✅ Using NDK: $ANDROID_NDK_HOME"

# Create jniLibs directories
mkdir -p example/android/app/src/main/jniLibs/arm64-v8a
mkdir -p example/android/app/src/main/jniLibs/armeabi-v7a
mkdir -p example/android/app/src/main/jniLibs/x86_64

# Clone llama.cpp at COMMIT b2277 (matches llama_cpp_dart 0.0.7)
cd /tmp
rm -rf llama.cpp
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
git checkout b2277  # Critical commit for compatibility

# Build for ARM64
echo "🔨 Building ARM64..."
mkdir build-android-arm64
cd build-android-arm64

cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM=android-23 \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_CURL=OFF \
      ..

make -j4

# Copy to project
cp libllama.so /Users/mohammedaymaan/code/genai/llm_toolkit/example/android/app/src/main/jniLibs/arm64-v8a/

# Repeat for other architectures...
