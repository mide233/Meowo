#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/.tools/flutter/bin:$PATH"
"$ROOT/scripts/build_core_linux.sh" Debug
ctest --test-dir "$ROOT/packages/meowo_core/native/build" --output-on-failure
cd "$ROOT/apps/meowo"
flutter analyze
MEOWO_CORE_LIB="$ROOT/packages/meowo_core/native/build/libmeowo_core.so" flutter test
