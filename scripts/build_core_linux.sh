#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cmake -S "$ROOT/packages/meowo_core/native" -B "$ROOT/packages/meowo_core/native/build" -G Ninja -DCMAKE_BUILD_TYPE="${1:-Debug}"
cmake --build "$ROOT/packages/meowo_core/native/build" -j 2
