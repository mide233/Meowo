#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/.tools/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-/home/mide/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export JAVA_HOME="${JAVA_HOME:-/usr/local/android-studio/jbr}"
"$ROOT/scripts/build_android_core.sh"
cd "$ROOT/apps/meowo"
flutter build apk --release --target-platform android-arm64
