#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/.tools/flutter/bin:$PATH"
cd "$ROOT/apps/meowo"
flutter build linux --release
"$ROOT/scripts/package_linux_bundle.sh"
