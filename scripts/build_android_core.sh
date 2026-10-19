#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-/home/mide/Android/Sdk}/ndk/28.2.13676358}"
if [ ! -d "$NDK" ]; then
  echo "Android NDK not found at $NDK; set ANDROID_NDK_HOME" >&2
  exit 1
fi
cmake -S "$ROOT/packages/meowo_core/native" -B "$ROOT/packages/meowo_core/native/build-android" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31 -DCMAKE_BUILD_TYPE=Release
cmake --build "$ROOT/packages/meowo_core/native/build-android" -j 2
STRIP="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
"$STRIP" --strip-unneeded "$ROOT/packages/meowo_core/native/build-android/libmeowo_core.so"
mkdir -p "$ROOT/apps/meowo/android/app/src/main/jniLibs/arm64-v8a"
cp "$ROOT/packages/meowo_core/native/build-android/libmeowo_core.so" \
   "$ROOT/apps/meowo/android/app/src/main/jniLibs/arm64-v8a/"
