#!/usr/bin/env bash
# Builds a package's shader bundle by calling impellerc directly.
#
# Why not the flutter_gpu_shaders package: it depends on the experimental Native
# Assets feature (`flutter config --enable-native-assets`), which is best left
# alone on the stable channel. Invoking impellerc does the same job and stays
# fully transparent.
#
# IMPORTANT: the bundle format is tied to the Flutter version. Rebuild after any
# SDK change.
#
# Nothing here is specific to flutter3d. Every `flutter3d_*` extension ships its
# own bundle, so this script is copied into each package's `tool/` verbatim and
# run with no arguments: the defaults are derived from where the script sits.
#
#   usage: build_shaders.sh [options]
#     -p, --package DIR    package root (default: the script's parent directory)
#     -m, --manifest PATH  bundle manifest JSON, relative to the package root
#                          (default: the single shaders/*.shaderbundle.json)
#     -o, --out PATH       output bundle, relative to the package root
#                          (default: assets/shaders/<manifest stem>)
#     -I, --include DIR    extra `#include <…>` root; repeatable. The package's
#                          own shaders/ and the SDK's shader_lib are always
#                          included, in that order. A package that always needs
#                          the same extra root lists it in shaders/includes.txt
#                          instead, so the script still runs with no arguments.
#     -P, --package-include NAME
#                          `#include <…>` root belonging to another PACKAGE,
#                          resolved through .dart_tool/package_config.json.
#                          Use this, not -I, for anything outside your own
#                          package: a relative path only works while the
#                          dependency comes from a path, and breaks the day it
#                          comes from the pub cache. `NAME:subdir` picks a
#                          subdirectory other than shaders/.
#         --platform NAME  host artifact directory under
#                          bin/cache/artifacts/engine (default: detected)
#
# Two different roots, and confusing them is the usual first failure:
#   * `file:` in the manifest resolves against the PACKAGE ROOT (impellerc is
#     run from there), so manifest paths read `shaders/lighting/pbr.frag`.
#   * `#include <lib/color.glsl>` resolves against an --include root, so the
#     same file is reached as `lib/color.glsl`.
set -euo pipefail

PACKAGE=""
MANIFEST=""
OUT=""
PLATFORM=""
EXTRA_INCLUDES=()
PACKAGE_INCLUDES=()

die() { echo "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--package)  PACKAGE="${2:?--package needs a directory}"; shift 2 ;;
    -m|--manifest) MANIFEST="${2:?--manifest needs a path}"; shift 2 ;;
    -o|--out)      OUT="${2:?--out needs a path}"; shift 2 ;;
    -I|--include)  EXTRA_INCLUDES+=("${2:?--include needs a directory}"); shift 2 ;;
    -P|--package-include)
                   PACKAGE_INCLUDES+=("${2:?--package-include needs a package name}"); shift 2 ;;
    --platform)    PLATFORM="${2:?--platform needs a name}"; shift 2 ;;
    -h|--help)     sed -n '2,38p' "$0"; exit 0 ;;
    *)             die "unknown argument: $1 (try --help)" ;;
  esac
done

# Where this copy of the script lives, resolved before the `cd` below because
# `$0` may be relative. package_root.dart sits beside it, and a copy of this
# script in another package finds its own neighbour rather than flutter3d's.
SCRIPT_HOME="$(cd "$(dirname "$0")" && pwd)"

# The package root defaults to the script's parent, which is what makes a
# verbatim copy of this file work in another package with no arguments.
if [[ -z "$PACKAGE" ]]; then
  PACKAGE="$(cd "$SCRIPT_HOME/.." && pwd)"
else
  PACKAGE="$(cd "$PACKAGE" && pwd)" || die "no such package directory"
fi
cd "$PACKAGE"

FLUTTER_BIN="$(dirname "$(command -v flutter)")"
SDK="$(cd "$FLUTTER_BIN/.." && pwd)"
ARTIFACTS="$SDK/bin/cache/artifacts/engine"

# The host artifact directory is not named after the host architecture: macOS
# ships one universal `darwin-x64` even on Apple silicon. So rather than mapping
# uname to a name and being wrong, list the plausible names for this OS and take
# the first that is actually on disk.
if [[ -z "$PLATFORM" ]]; then
  case "$(uname -s)" in
    Darwin)  CANDIDATES=(darwin-x64 darwin-arm64) ;;
    Linux)   case "$(uname -m)" in
               aarch64|arm64) CANDIDATES=(linux-arm64 linux-x64) ;;
               *)             CANDIDATES=(linux-x64 linux-arm64) ;;
             esac ;;
    MINGW*|MSYS*|CYGWIN*) CANDIDATES=(windows-x64 windows-arm64) ;;
    *)       CANDIDATES=(darwin-x64 linux-x64 windows-x64) ;;
  esac
  for candidate in "${CANDIDATES[@]}"; do
    if [[ -x "$ARTIFACTS/$candidate/impellerc" ]]; then
      PLATFORM="$candidate"
      break
    fi
  done
  [[ -n "$PLATFORM" ]] || {
    echo "impellerc not found under $ARTIFACTS" >&2
    echo "tried: ${CANDIDATES[*]}" >&2
    echo "Run 'flutter precache', or pass --platform." >&2
    exit 1
  }
fi

IMPELLERC="$ARTIFACTS/$PLATFORM/impellerc"
SHADER_LIB="$ARTIFACTS/$PLATFORM/shader_lib"

if [[ ! -x "$IMPELLERC" ]]; then
  echo "impellerc not found at: $IMPELLERC" >&2
  echo "Run 'flutter precache' or pass --platform for your host." >&2
  exit 1
fi

# One manifest per package is the convention; discovering it rather than naming
# it is what lets the script be copied without editing. Two would be ambiguous,
# so say so instead of picking one.
if [[ -z "$MANIFEST" ]]; then
  shopt -s nullglob
  found=(shaders/*.shaderbundle.json)
  shopt -u nullglob
  case ${#found[@]} in
    0) die "no shaders/*.shaderbundle.json in $PACKAGE — pass --manifest" ;;
    1) MANIFEST="${found[0]}" ;;
    *) die "several manifests in $PACKAGE (${found[*]}) — pass --manifest" ;;
  esac
fi
[[ -f "$MANIFEST" ]] || die "manifest not found: $PACKAGE/$MANIFEST"

# Inside the package rather than under build/, because this is an asset the
# package declares and a consuming application loads as
# `packages/<package>/assets/shaders/…`. Generated, so it is gitignored — but it
# cannot live in build/, which Flutter owns and clears.
if [[ -z "$OUT" ]]; then
  STEM="$(basename "$MANIFEST" .shaderbundle.json)"
  OUT="assets/shaders/$STEM.shaderbundle"
fi
mkdir -p "$(dirname "$OUT")"

# A package that needs a foreign include root records it in
# shaders/includes.txt, one entry per line. That keeps the invocation
# argument-free, which is what lets CI build every package's bundle with one
# loop over `packages/*/tool/build_shaders.sh` instead of a hand-maintained
# table of flags.
#
# An entry is a PACKAGE NAME unless it starts with `.` or `/`, in which case it
# is a literal path. Package names are the right default: a relative path to a
# dependency only works while that dependency comes from a path, and an
# extension installed from pub sits in the cache, where no relative path from
# the consumer reaches it.
if [[ -f shaders/includes.txt ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    # Trim with parameter expansion rather than `xargs`, which would also strip
    # quotes and backslashes out of a path that legitimately contains them.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    case "$line" in
      .*|/*) EXTRA_INCLUDES+=("$line") ;;
      *)     PACKAGE_INCLUDES+=("$line") ;;
    esac
  done < shaders/includes.txt
fi

# Resolved through package_config.json, which is the only mapping pub
# guarantees across path, git and hosted dependencies alike. The SDK's own Dart
# runs it: `rootUri` is a URI — relative for a path dependency, absolute and
# percent-encoded for the cache — and Uri.resolve implements those rules where
# shell string-mangling would only approximate them.
DART="$SDK/bin/cache/dart-sdk/bin/dart"
RESOLVED_INCLUDES=()
for entry in ${PACKAGE_INCLUDES+"${PACKAGE_INCLUDES[@]}"}; do
  name="${entry%%:*}"
  subdir="shaders"
  [[ "$entry" == *:* ]] && subdir="${entry#*:}"
  root="$("$DART" "$SCRIPT_HOME/package_root.dart" "$name" --from "$PACKAGE")" ||
    die "cannot resolve package '$name'. Is it a dependency, and has 'flutter pub get' run?"
  RESOLVED_INCLUDES+=("$root/$subdir")
done

INCLUDES=(--include=shaders)
for dir in "${EXTRA_INCLUDES[@]}"; do
  [[ -d "$dir" ]] || die "include directory not found: $dir"
  INCLUDES+=("--include=$(cd "$dir" && pwd)")
done
for dir in ${RESOLVED_INCLUDES+"${RESOLVED_INCLUDES[@]}"}; do
  [[ -d "$dir" ]] || die "resolved include directory not found: $dir"
  INCLUDES+=("--include=$dir")
done
INCLUDES+=("--include=$SHADER_LIB")

echo "impellerc: $IMPELLERC"
echo "package:   $PACKAGE"
echo "spec:      $MANIFEST"

# The manifest is passed as inline JSON text, not as a path — impellerc's
# --shader-bundle takes the document itself.
"$IMPELLERC" \
  --shader-bundle="$(cat "$MANIFEST")" \
  --sl="$OUT" \
  "${INCLUDES[@]}"

echo "done: $OUT ($(wc -c <"$OUT" | tr -d ' ') bytes)"
echo

# What the compiler actually kept, per entry point.
#
# Not decoration. A uniform block or a sampler the shader declares but never
# reads is dropped from the compiled function, while the Dart side still has
# metadata claiming it is there — and binding a slot Metal does not have is a
# native crash with no Dart stack trace. LightingModel declares these sets by
# hand, so printing the truth next to them is what keeps the two together.
#
# It also prints the entry-point names, which is the thing to check when a
# second package joins the build: these names live in ONE process-wide
# namespace, they are derived from the shader's FILE NAME (not the manifest
# key), and a collision between two bundles is resolved silently in favour of
# whichever registered first. See tool/README or the Track B report.
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
