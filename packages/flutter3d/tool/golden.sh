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
#   tool/golden.sh --cpu        draw them with the software backend instead
#   tool/golden.sh --no-build   reuse the application already built
#
# **One build for the whole suite, and the reason is disk rather than time.**
# This script used to call `flutter run -d macos` once a scene with the scene
# name in a `--dart-define`. A define is a compile-time input, so every scene
# was a fresh kernel compile filed under a fresh fingerprint directory in
# `example/.dart_tool/flutter_build` — roughly forty-six megabytes of `app.dill`
# apiece, and nothing has ever deleted one. Seven hundred and twenty-three of
# them, sixteen gigabytes, had collected in the main checkout by the time anyone
# measured; a full pass of forty-three scenes could not finish on a machine with
# room for a couple of gigabytes, which meant the Impeller set had stopped being
# runnable at all. The scene, the direction and the reference directory arrive
# in the process environment now, so `flutter build macos` runs once and the
# built binary is launched once a scene. That is the shape the browser stand has
# had all along, for the same arithmetic.
#
# Launching the binary rather than `flutter run` is part of the same change and
# not incidental: `flutter run` rebuilds, re-checks the toolchain and attaches a
# VM service on every scene, and none of the three has anything to do with the
# picture. The application prints its verdict with `print` and exits with a code,
# which is all this script ever read.
#
# --cpu draws the same scenes through flutter3d_cpu and compares against that
# backend's own references, in packages/flutter3d_cpu/test/goldens. Its own,
# not Impeller's: the software rasteriser has no multisampling, so it cannot
# reproduce these pictures byte for byte and a shared reference set would need
# a tolerance, which is a threshold that stops watching. Held to zero against
# itself, it answers "did this backend change"; the cross-backend question —
# "do the two draw the same picture" — is a plain test over the two committed
# reference sets, in flutter3d_cpu/test/cross_backend_test.dart, and needs no
# device at all.
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
CPU=false
BUILD=true
SCENES=()

for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=true ;;
    --cpu) CPU=true ;;
    --no-build) BUILD=false ;;
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

BACKEND_DEFINE=()
if [[ "$CPU" == true ]]; then
  GOLDEN_DIR="$PACKAGE_DIR/../flutter3d_cpu/test/goldens"
  BACKEND_DEFINE=(--dart-define=cpuBackend=true)
fi

mkdir -p "$GOLDEN_DIR"

# The bundle belongs to the backend package now: it is impellerc output, and
# only flutter3d_impeller can read it. Still required under --cpu: the
# application links both backends, and Flutter fails a declared asset that is
# missing whichever one draws.
BUNDLE="$PACKAGE_DIR/../flutter3d_impeller/assets/shaders/flutter3d.shaderbundle"
if [[ ! -f "$BUNDLE" ]]; then
  echo "shader bundle missing; run ../flutter3d_impeller/tool/build_shaders.sh" >&2
  exit 2
fi

# The example's own loadable bundle, for `loaded-shader`. Declared in the
# example's pubspec, so every scene needs it to build, not only the one that
# loads it — and under --cpu as much as on Impeller, since the file carries a
# section for each and the software backend reads its stage list.
LOADABLE="$EXAMPLE_DIR/assets/shaders/example.f3dshaders"
if [[ ! -f "$LOADABLE" ]]; then
  echo "the example's shader bundle is missing; run example/tool/build_shaders.sh" >&2
  exit 2
fi

APP='flutter3d.app/Contents/MacOS/flutter3d'
APP_BIN="$EXAMPLE_DIR/build/macos/Build/Products/Debug/$APP"

if [[ "$BUILD" == true ]]; then
  echo "building the example for macOS…"
  (cd "$EXAMPLE_DIR" && flutter build macos --debug \
    ${BACKEND_DEFINE[@]+"${BACKEND_DEFINE[@]}"})
fi

if [[ ! -x "$APP_BIN" ]]; then
  echo "no application at $APP_BIN; drop --no-build" >&2
  exit 2
fi

# How long one scene may take before it is treated as stalled rather than slow.
# A scene renders ninety frames and exits, which is about half a minute.
#
# Ninety seconds now, where it was five minutes: the five covered a cold build
# happening inside the first scene, and there is no build inside a scene any
# more. What is left is a launch and ninety frames, so a scene that has not
# spoken in a minute and a half is stuck rather than slow.
SCENE_TIMEOUT=${FLUTTER3D_SCENE_TIMEOUT:-90}

# The software backend needs longer, and the two heaviest scenes need much
# longer. cube-shadow-many and cube-shadow-crowded draw six faces per light
# into 1024-pixel tiles, and a rasteriser written in Dart takes seconds a frame
# at that size where Impeller takes milliseconds. Both were reported FAILED
# four runs in a row under the limit the hardware backend needs; run alone with
# more patience each renders and passes.
#
# Raising the limit rather than shrinking the atlas for this backend, which was
# the other candidate and is the wrong one: the tile size is a *scene* setting,
# so a smaller atlas here would draw a different picture and cross-backend
# comparison of every shadow scene would stop meaning anything. It would also
# not have helped much — clearing the whole 6144x4096 atlas measures 66ms; the
# cost is rasterising casters into the tiles, not the atlas itself.
if [[ "$CPU" == true ]]; then
  SCENE_TIMEOUT=${FLUTTER3D_SCENE_TIMEOUT:-900}
fi

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
# therefore held the substitution open long after the launch had returned, which
# looked like the launch hanging and was not. Redirecting to a file makes the
# script wait for the process it actually started.
#
# The scene, the direction and the directory are exported rather than compiled
# in, which is what lets every scene share one build; the application reads all
# three from its environment and falls back to the defines of the same name, so
# a `flutter run` driven by hand still works the way it always did.
run_scene() {
  local scene="$1" log="$2"

  (
    cd "$EXAMPLE_DIR" &&
      FLUTTER3D_GOLDEN="$scene" \
        FLUTTER3D_GOLDEN_DIR="$GOLDEN_DIR" \
        FLUTTER3D_GOLDEN_UPDATE="$UPDATE" \
        exec "$APP_BIN"
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

# Free space on the volume the build and the references live on, in mebibytes.
FLOOR_MIB=${FLUTTER3D_DISK_FLOOR_MIB:-10240}

free_mib() {
  df -m "$PACKAGE_DIR" | awk 'NR == 2 { print $4 }'
}

pass=0
fail=0
stopped=""
failed_scenes=()
log="$(mktemp -t flutter3d-golden)"
trap 'rm -f "$log"' EXIT

for scene in "${SCENES[@]}"; do
  # **Checked before each scene, and the run stops rather than fills the
  # volume.** A golden run writes a picture per disagreement and the build it
  # launches is already on disk, so no single scene is expensive now; what makes
  # this worth a check anyway is that a machine out of space does not fail as a
  # golden mismatch, it fails as a truncated PNG or a launch that cannot write
  # its log, and that reads as a rendering problem to whoever comes next. Ten
  # gibibytes is a floor with room for a whole second run under it, so stopping
  # here never costs more than the run in progress.
  remaining="$(free_mib)"
  if [[ -n "$remaining" && "$remaining" -lt "$FLOOR_MIB" ]]; then
    stopped="$scene"
    echo "STOPPED before $scene: $((remaining / 1024)) GiB free, floor is" \
      "$((FLOOR_MIB / 1024)) GiB"
    break
  fi

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

  # The application exits 0 on a match and non-zero otherwise, but it also
  # prints its own message, which is where the numbers are.
  if grep -q "GOLDEN $scene: \(PASS\|recorded\)" "$log"; then
    # The verdict is printed even when it passes, and that is not noise. It
    # used to be the only defence: the threshold allowed 0.2% of pixels to
    # differ, so "ok" covered everything from a byte-identical frame to one
    # that was 0.199% wrong and about to break — two scenes sat at 0.178% and
    # 0.100% for a whole session behind that word. The pixel threshold is zero
    # now, so "ok" means zero differing pixels; the count is printed anyway,
    # because the worst channel delta beside it is the one number that still
    # moves and the only warning that the hardware is drifting.
    # Not anchored to the start of the line. The application prints its verdict
    # with `print` — it has to, because dart:io does not exist in a browser and
    # the same runner serves both — and whatever launched it may prefix the
    # line: run under `flutter run` it arrives behind "flutter: ", run as the
    # binary it arrives bare. An anchored extraction found nothing under the
    # first of those, so every scene passed and printed a blank line: the count
    # survived and the numbers vanished, which is the exact state printing them
    # was meant to end.
    verdict="$(sed -n "s/^.*GOLDEN $scene: //p" "$log" | head -1)"
    if [[ -z "$verdict" ]]; then
      # A pass whose numbers cannot be read is not a pass worth reporting.
      echo "FAILED (verdict matched but could not be extracted — see $log)"
      fail=$((fail + 1))
      failed_scenes+=("$scene")
      continue
    fi
    echo "ok  $verdict"
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
echo "$pass passed, $fail failed, $(($(free_mib) / 1024)) GiB free"
if [[ -n "$stopped" ]]; then
  echo "stopped at $stopped with ${#SCENES[@]} scenes asked for; the rest were" \
    "not compared"
fi
if [[ $fail -gt 0 ]]; then
  echo "failed: ${failed_scenes[*]}"
  echo "compare <name>.png against <name>.actual.png in $GOLDEN_DIR"
  exit 1
fi
# A run that stopped early answered nothing about the scenes it never reached,
# and a zero here would say it did.
if [[ -n "$stopped" ]]; then exit 1; fi
