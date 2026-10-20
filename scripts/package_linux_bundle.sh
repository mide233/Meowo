#!/usr/bin/env bash
set -euo pipefail

# Flutter's Linux runner is linked against libmeowo_core.so. When the local
# MuPDF build is shared (instead of the vendored static libraries), the bundle
# must also contain MuPDF's runtime libraries and a launcher that points the
# dynamic loader at the bundle's lib directory.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${1:-$ROOT/apps/meowo/build/linux/x64/release/bundle}"
CORE="$BUNDLE/lib/libmeowo_core.so"
[ -f "$CORE" ] || exit 0

mapfile -t RUNPATHS < <(readelf -d "$CORE" 2>/dev/null |
  sed -n 's/.*RUNPATH.*\[\(.*\)\].*/\1/p' | tr ':' '\n')
SEARCH_DIRS=("$BUNDLE/lib")
for dir in "${RUNPATHS[@]}"; do
  [ -n "$dir" ] && [ -d "$dir" ] && SEARCH_DIRS+=("$dir")
done
if [ -n "${LD_LIBRARY_PATH:-}" ]; then
  IFS=':' read -r -a LD_DIRS <<<"$LD_LIBRARY_PATH"
  for dir in "${LD_DIRS[@]}"; do
    [ -n "$dir" ] && [ -d "$dir" ] && SEARCH_DIRS+=("$dir")
  done
fi

copy_dep() {
  local name="$1"
  for dir in "${SEARCH_DIRS[@]}"; do
    if [ -e "$dir/$name" ]; then
      if [ "$(readlink -f "$dir/$name")" = "$(readlink -f "$BUNDLE/lib/$name" 2>/dev/null || true)" ]; then
        return 0
      fi
      cp -Lf "$dir/$name" "$BUNDLE/lib/$name"
      return 0
    fi
  done
  return 1
}

# Only needed when the core was linked against Ubuntu's shared MuPDF. Static
# vendored builds do not have these dependencies and this becomes a no-op.
for name in libmupdf.so.27.0 libgumbo.so.3 libmujs.so.3; do
  copy_dep "$name" || true
done

if [ ! -e "$BUNDLE/meowo.bin" ] && [ -x "$BUNDLE/meowo" ] &&
  file "$BUNDLE/meowo" | grep -q 'ELF'; then
  mv "$BUNDLE/meowo" "$BUNDLE/meowo.bin"
fi
cat >"$BUNDLE/meowo" <<'EOF'
#!/bin/sh
# MEOWO_BUNDLE_WRAPPER
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$DIR/meowo.bin" "$@"
EOF
chmod +x "$BUNDLE/meowo"
