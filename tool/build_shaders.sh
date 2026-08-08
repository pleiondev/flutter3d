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
echo

# What the compiler actually kept, per entry point.
#
# Not decoration. A uniform block or a sampler the shader declares but never
# reads is dropped from the compiled function, while the Dart side still has
# metadata claiming it is there — and binding a slot Metal does not have is a
# native crash with no Dart stack trace. LightingModel declares these sets by
# hand, so printing the truth next to them is what keeps the two together.
echo "compiled bindings (must match LightingModel metadata):"
# One awk pass rather than a shell loop: the signatures embed `[[buffer(0)]]`,
# so they cannot be matched with an "up to the closing paren" pattern, and
# per-line subshells here proved fragile.
strings -n 3 "$OUT" |
  grep -E '^(fragment|vertex) .*_main\(' |
  awk '
    {
      match($0, /[a-z_]+_(fragment|vertex)_main\(/)
      if (RSTART == 0) next
      name = substr($0, RSTART, RLENGTH - 1)
      if (seen[name]++) next

      slots = ""
      rest = $0
      while (match(rest, /constant [A-Za-z]+&|texture2d<float> [a-z_]+/)) {
        slot = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        sub(/^constant /, "", slot)
        sub(/&$/, "", slot)
        sub(/^texture2d<float> /, "", slot)
        if (!(name "/" slot in used)) {
          used[name "/" slot] = 1
          slots = slots (slots == "" ? "" : " ") slot
        }
      }
      printf "  %-24s %s\n", name, (slots == "" ? "(none)" : slots)
    }
  '
