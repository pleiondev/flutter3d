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

APP='flutter3d.app/Contents/MacOS/flutter3d'

# How long one scene may take before it is treated as stalled rather than slow.
# A scene renders ninety frames and exits, which is about half a minute; the
# first one of a run also builds, and a cold build is minutes rather than
# seconds.
#
# Five, not three, because the two failure modes cost different amounts. Too
# short turns a cold first build into a FAILED line about a picture, which is a
# wrong answer and sends the reader hunting a rendering bug. Too long costs a
# few extra minutes once, on a run that was going to be thrown away anyway. When
# the errors are that lopsided, pick the side that only wastes time.
SCENE_TIMEOUT=${FLUTTER3D_SCENE_TIMEOUT:-300}

# Kills the example app and *waits for it to be gone*.
#
# `pkill` only asks. The next launch used to start while the previous process
# was still exiting, macOS answered "Failed to foreground app; open returned 1",
# the new app came up without a window, its ninetieth frame never arrived and
# `flutter run` waited for an app that would never report. That is the stall
# this whole function exists to remove, and the waiting is the part that does
# it — the `pkill` was already here and was not enough.
reap_app() {
  pkill -f "$APP" 2>/dev/null || true
  for _ in $(seq 1 60); do
    pgrep -f "$APP" >/dev/null 2>&1 || return 0
    sleep 0.25
  done
  # Still there after fifteen seconds: it is not exiting on its own.
  pkill -9 -f "$APP" 2>/dev/null || true
  sleep 1
}

# Runs one scene into a log file, giving up after SCENE_TIMEOUT.
#
# A file rather than `output=$(...)`: command substitution waits for end of file
# on a pipe, and the app inherits the write end of that pipe. A surviving app
# therefore held the substitution open long after `flutter run` had exited,
# which looked like `flutter run` hanging and was not. Redirecting to a file
# makes the script wait for the process it actually started.
run_scene() {
  local scene="$1" log="$2"

  (
    cd "$EXAMPLE_DIR" && exec flutter run -d macos --debug \
      --dart-define=FLUTTER3D_GOLDEN="$scene" \
      --dart-define=FLUTTER3D_GOLDEN_DIR="$GOLDEN_DIR" \
      --dart-define=FLUTTER3D_GOLDEN_UPDATE="$UPDATE"
  ) >"$log" 2>&1 &
  local pid=$!

  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ $waited -ge $SCENE_TIMEOUT ]]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
}

pass=0
fail=0
failed_scenes=()
log="$(mktemp -t flutter3d-golden)"
trap 'rm -f "$log"' EXIT

for scene in "${SCENES[@]}"; do
  printf '%-28s' "$scene"

  # Reaped *before* each scene rather than after, because the straggler may
  # also predate this run entirely. The cost is real and worth stating: an
  # example app opened by hand for debugging is indistinguishable from a
  # leftover and gets killed too. The suite launches and drives that app
  # anyway, so it already needed it to itself.
  reap_app
  run_scene "$scene" "$log"

  # One retry, and only when the run produced no verdict at all — a launch
  # macOS refused to foreground, or a timeout. Neither says anything about the
  # picture. A scene that rendered and *disagreed* is never retried: that is a
  # finding, and retrying until a golden agrees is how a suite comes to pin
  # nothing.
  if ! grep -q "GOLDEN $scene:" "$log"; then
    reap_app
    run_scene "$scene" "$log"
  fi

  # `flutter run` reports 0 when the app exits cleanly and non-zero otherwise,
  # but it also prints the app's own message, which is where the verdict is.
  if grep -q "GOLDEN $scene: \(PASS\|recorded\)" "$log"; then
    # The verdict is printed even when it passes, and that is not noise. The
    # threshold allows 0.2% of pixels to differ, so "ok" covers everything from
    # a byte-identical frame to one that is 0.199% wrong and about to break —
    # two scenes sat at 0.178% and 0.100% for a whole session behind that word.
    # A count is a measurement; "ok" is a comparison against a number nobody
    # sees.
    sed -n "s/^GOLDEN $scene: //p" "$log" | head -1 | sed 's/^/ok  /'
    pass=$((pass + 1))
  else
    echo "FAILED"
    grep -E "GOLDEN|Failed to foreground|Error|Exception|error:" "$log" |
      sed 's/^/    /'
    fail=$((fail + 1))
    failed_scenes+=("$scene")
  fi
done

reap_app

echo
echo "$pass passed, $fail failed"
if [[ $fail -gt 0 ]]; then
  echo "failed: ${failed_scenes[*]}"
  echo "compare <name>.png against <name>.actual.png in $GOLDEN_DIR"
  exit 1
fi
