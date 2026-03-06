#!/bin/bash
# build_native_libs_fixed.sh

set -e

# Use NDK 25.2.9519653 specifically
NDK_BASE="/Users/mohammedaymaan/Library/Android/sdk/ndk"
NDK_VERSION="25.2.9519653"

export ANDROID_NDK_HOME="$NDK_BASE/$NDK_VERSION"
export ANDROID_NDK="$ANDROID_NDK_HOME"

echo "✅ Using NDK 25.2.9519653: $ANDROID_NDK_HOME"

# Create jniLibs directories
echo "📁 Creating jniLibs directories..."
mkdir -p example/android/app/src/main/jniLibs/arm64-v8a
mkdir -p example/android/app/src/main/jniLibs/armeabi-v7a
mkdir -p example/android/app/src/main/jniLibs/x86_64

cd /tmp/llama.cpp

# Build ARM64 (Most important for modern Android devices)
echo "🔨 Building ARM64..."
rm -rf build-android-arm64
mkdir build-android-arm64
cd build-android-arm64

cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM=android-23 \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_CURL=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      ..

make -j4

# Copy from the correct location (bin directory)
cp bin/libllama.so /Users/mohammedaymaan/code/genai/llm_toolkit/example/android/app/src/main/jniLibs/arm64-v8a/
echo "✅ ARM64 library built and copied"

# Build ARM32
echo "🔨 Building ARM32..."
cd ..
rm -rf build-android-arm32
mkdir build-android-arm32
cd build-android-arm32

cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=armeabi-v7a \
      -DANDROID_PLATFORM=android-23 \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_CURL=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      ..

make -j4

cp bin/libllama.so /Users/mohammedaymaan/code/genai/llm_toolkit/example/android/app/src/main/jniLibs/armeabi-v7a/
echo "✅ ARM32 library built and copied"

# Build x86_64
echo "🔨 Building x86_64..."
cd ..
rm -rf build-android-x86_64
mkdir build-android-x86_64
cd build-android-x86_64

cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=x86_64 \
      -DANDROID_PLATFORM=android-23 \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_CURL=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      ..

make -j4

cp bin/libllama.so /Users/mohammedaymaan/code/genai/llm_toolkit/example/android/app/src/main/jniLibs/x86_64/
echo "✅ x86_64 library built and copied"

# Verify files
echo "📋 Verifying libraries..."
ls -la /Users/mohammedaymaan/code/genai/llm_toolkit/example/android/app/src/main/jniLibs/*/libllama.so

echo "🎉 All native libraries built successfully!"
echo "NDK Version used: $NDK_VERSION"
echo "Now run: cd example && flutter clean && flutter pub get && flutter run"
