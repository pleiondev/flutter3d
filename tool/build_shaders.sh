#!/usr/bin/env bash
# Builds the shader bundle by calling impellerc directly.
#
# Why not the flutter_gpu_shaders package: it depends on the experimental Native
# Assets feature (`flutter config --enable-native-assets`), which is best left
# alone on the stable channel. Invoking impellerc does the same job and stays
# fully transparent.
#
# IMPORTANT: the bundle format is tied to the Flutter version. Rebuild after any
# SDK change.
set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER_BIN="$(dirname "$(command -v flutter)")"
SDK="$(cd "$FLUTTER_BIN/.." && pwd)"
IMPELLERC="$SDK/bin/cache/artifacts/engine/darwin-x64/impellerc"

if [[ ! -x "$IMPELLERC" ]]; then
  echo "impellerc not found at: $IMPELLERC" >&2
  echo "Run 'flutter precache' or adjust the path for your platform." >&2
  exit 1
fi

SPEC_FILE="shaders/flutter3d.shaderbundle.json"
OUT_DIR="build/shaders"
OUT="$OUT_DIR/flutter3d.shaderbundle"

mkdir -p "$OUT_DIR"

echo "impellerc: $IMPELLERC"
echo "spec:      $SPEC_FILE"

"$IMPELLERC" \
  --shader-bundle="$(cat "$SPEC_FILE")" \
  --sl="$OUT" \
  --include=shaders \
  --include="$SDK/bin/cache/artifacts/engine/darwin-x64/shader_lib"

echo "done: $OUT ($(wc -c <"$OUT" | tr -d ' ') bytes)"
