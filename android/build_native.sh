#!/bin/bash
set -e

# Build native library for Android using NDK CMake.
# Gradle builds this library automatically through externalNativeBuild; this
# script is only for manually verifying the native build in isolation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPP_DIR="$SCRIPT_DIR/app/src/main/cpp"

# Find CMake - prefer NDK's CMake, fall back to system CMake
if [ -n "$ANDROID_SDK_ROOT" ]; then
    CMAKE_BIN="$ANDROID_SDK_ROOT/cmake/3.22.1/bin/cmake"
    if [ ! -f "$CMAKE_BIN" ]; then
        CMAKE_BIN=$(find "$ANDROID_SDK_ROOT/cmake" -name cmake -type f 2>/dev/null | head -n1)
    fi
fi

if [ -z "$CMAKE_BIN" ] || [ ! -f "$CMAKE_BIN" ]; then
    CMAKE_BIN=$(which cmake 2>/dev/null || echo "")
fi

if [ -z "$CMAKE_BIN" ] || [ ! -f "$CMAKE_BIN" ]; then
    echo "Error: CMake not found. Install CMake or set ANDROID_SDK_ROOT."
    exit 1
fi

echo "Using CMake: $CMAKE_BIN"

# Find NDK
if [ -n "$ANDROID_NDK_ROOT" ]; then
    NDK_ROOT="$ANDROID_NDK_ROOT"
elif [ -n "$ANDROID_SDK_ROOT" ]; then
    NDK_ROOT="$ANDROID_SDK_ROOT/ndk/28.0.12674087"
    if [ ! -d "$NDK_ROOT" ]; then
        NDK_ROOT=$(find "$ANDROID_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n1)
    fi
fi

if [ -z "$NDK_ROOT" ] || [ ! -d "$NDK_ROOT" ]; then
    echo "Error: Android NDK not found. Set ANDROID_NDK_ROOT or ANDROID_SDK_ROOT."
    exit 1
fi

echo "Using NDK: $NDK_ROOT"

TOOLCHAIN="$NDK_ROOT/build/cmake/android.toolchain.cmake"
if [ ! -f "$TOOLCHAIN" ]; then
    echo "Error: NDK toolchain not found at $TOOLCHAIN"
    exit 1
fi

# Determine make program
if [ "$(uname -s)" = "MINGW"* ] || [ "$(uname -s)" = "MSYS"* ]; then
    MAKE_PROGRAM="$NDK_ROOT/prebuilt/windows-x86_64/bin/make.exe"
else
    MAKE_PROGRAM="$NDK_ROOT/prebuilt/linux-x86_64/bin/make"
fi

if [ ! -f "$MAKE_PROGRAM" ]; then
    echo "Warning: NDK make not found, using system make"
    MAKE_PROGRAM="make"
fi

# Build for each ABI
for ABI in arm64-v8a armeabi-v7a x86_64 x86; do
    echo "Building for $ABI..."
    BUILD_DIR="$CPP_DIR/build-$ABI"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    
    "$CMAKE_BIN" \
        -G "Unix Makefiles" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DCMAKE_MAKE_PROGRAM="$MAKE_PROGRAM" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM=android-24 \
        -DANDROID_STL=c++_shared \
        -B "$BUILD_DIR" \
        -S "$CPP_DIR"
    
    "$CMAKE_BIN" --build "$BUILD_DIR"
    echo "✓ Built $ABI"
done

echo "Native library build complete for all architectures"
