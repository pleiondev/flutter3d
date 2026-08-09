#!/usr/bin/env bash
# Records or compares the golden render references.
#
# Golden rendering needs a real GPU, so it cannot run under `flutter test`,
# which is headless. Each scene runs as the example application instead, which
# renders one fully-specified frame and exits with a code this script reads.
#
#   tool/golden.sh              compare every scene against its reference
#   tool/golden.sh --update     record them instead
#   tool/golden.sh shadow-teapot        just that one
#
# IMPORTANT: the shader bundle format is tied to the Flutter version, so
# references recorded on one SDK will not match another. Re-record after an
# upgrade, and read the diff rather than accepting it blindly — that difference
# is the entire thing these tests exist to show.
set -uo pipefail

cd "$(dirname "$0")/.."
PACKAGE_DIR="$(pwd)"
GOLDEN_DIR="$PACKAGE_DIR/test/goldens"
EXAMPLE_DIR="$PACKAGE_DIR/example"

UPDATE=false
SCENES=()

for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=true ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) SCENES+=("$arg") ;;
  esac
done

if [[ ${#SCENES[@]} -eq 0 ]]; then
  # The list lives in golden_scenes.dart; this pulls the names out rather than
  # keeping a second copy that can fall out of step.
  # A while-read loop rather than `mapfile`, which macOS's system bash (3.2)
  # does not have.
  while IFS= read -r line; do
    SCENES+=("$line")
  done < <(
    grep -oE "name: '[a-z0-9-]+'" example/lib/src/spike/golden_scenes.dart |
      sed "s/name: '//; s/'//"
  )
  # The per-lighting-model scenes are generated in a loop, so their names are
  # not literals and the grep above cannot see them.
  for model in unlit lambert blinnphong pbr toon normals; do
    SCENES+=("lighting-$model")
  done
fi

mkdir -p "$GOLDEN_DIR"

if [[ ! -f "$PACKAGE_DIR/assets/shaders/flutter3d.shaderbundle" ]]; then
  echo "shader bundle missing; run tool/build_shaders.sh first" >&2
  exit 2
fi

pass=0
fail=0
failed_scenes=()

for scene in "${SCENES[@]}"; do
  printf '%-28s' "$scene"

  # `flutter run` stays attached and forwards the app's exit code, so the
  # script can simply read it. Output is captured and only shown on failure,
  # because a passing run prints a page of Flutter tooling noise.
  output=$(
    cd "$EXAMPLE_DIR" && flutter run -d macos --debug \
      --dart-define=FLUTTER3D_GOLDEN="$scene" \
      --dart-define=FLUTTER3D_GOLDEN_DIR="$GOLDEN_DIR" \
      --dart-define=FLUTTER3D_GOLDEN_UPDATE="$UPDATE" 2>&1
  )
  status=$?

  # `flutter run` reports 0 when the app exits cleanly and non-zero otherwise,
  # but it also prints the app's own message, which is where the verdict is.
  if echo "$output" | grep -q "GOLDEN $scene: \(PASS\|recorded\)"; then
    echo "ok"
    pass=$((pass + 1))
  else
    echo "FAILED"
    echo "$output" | grep -E "GOLDEN|Error|Exception|error:" | sed 's/^/    /'
    fail=$((fail + 1))
    failed_scenes+=("$scene")
  fi
done

echo
echo "$pass passed, $fail failed"
if [[ $fail -gt 0 ]]; then
  echo "failed: ${failed_scenes[*]}"
  echo "compare <name>.png against <name>.actual.png in $GOLDEN_DIR"
  exit 1
fi
