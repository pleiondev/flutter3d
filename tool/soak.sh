#!/usr/bin/env bash
# Plays the platformer's tape in a loop for two hours on a device, reads its
# resident memory once a second, times every frame, listens for its garbage
# collections and for a crash or an ANR, and writes the soak report and its
# memory graph into doc/pacing/ — P2.
#
#   tool/soak.sh -d <device-id> --label a55               P2 whole: both
#                                                        placements, 2 h each
#   tool/soak.sh -d macos --minutes 3 --out <dir>          the rehearsal
#   tool/soak.sh -d <id> --placement inline --fail-on rssGrowth=1.15,max=250
#   tool/soak.sh -d <id> --dry-run
#
# **Two placements, one after the other.** `inline` steps the simulation on
# the thread that draws; `isolate` asks the harness for
# `SimulationPlacement.isolate` through the `FLUTTER3D_SOAK_PLACEMENT`
# define. A harness that does not read that define is refused for the
# isolate by name rather than soaked inline twice. `--placement` is
# `inline`, `isolate` or `both` (the default).
#
# **The run is `tool/pacing.sh`'s.** The same harness
# (`apps/flutter3d_demo_platformer/integration_test/pacing_test.dart`) plays
# the same tape (`site/assets/samples/platformer.f3drun`) through
# `flutter drive --profile`, looped in as many whole passes as cover
# `--minutes` of play, and the same sampler reads the memory
# (`tool/pacing_rss.sh`: `dumpsys meminfo` on Android, `ps` on macOS). The
# frames are drawn back to back, so a fast device plays two hours of tape in
# less than two hours; the memory graph is in wall-clock minutes.
#
# **The thresholds are P2's** unless `--fail-on` says otherwise:
# `rssGrowth=1.15,max=250,gc50=1` — the memory at the end at most 1.15 times
# the memory ten minutes in, no frame over 250 ms, at most one garbage
# collection over 50 ms in any one minute — and no crash or ANR whatever the
# line. See `tool/soak_report.dart` for how each is read, the pauses among
# them (off the VM service `flutter drive` prints, its `GC` stream).
#
# **A crash or an ANR** is read on Android from `adb logcat` (cleared before
# the run: `ANR in <package>`, `FATAL EXCEPTION`, `Fatal signal` in the
# application's process) and on macOS from the crash reports the system
# writes for the application's binary during the run.
#
# The report is `<out>/soak-<label>-<placement>.md` with
# `soak-<label>-<placement>-rss.svg` beside it, `<out>` being doc/pacing/
# unless `--out` says; the label is the device unless `--label` says. A
# rehearsal on a machine doing other work is not a proof: give it `--out`
# somewhere outside the repository.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DEVICE=""
LABEL=""
MINUTES=120
PLACEMENT=both
FAIL_ON="rssGrowth=1.15,max=250,gc50=1"
OUT="$ROOT/doc/pacing"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --minutes) MINUTES="$2"; shift 2 ;;
    --placement) PLACEMENT="$2"; shift 2 ;;
    --fail-on) FAIL_ON="$2"; shift 2 ;;
    --out) OUT="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  echo "which device? -d <device-id> (or -d macos)" >&2
  exit 2
fi
if ! [[ "$MINUTES" =~ ^[0-9]+$ ]] || [[ "$MINUTES" -lt 1 ]]; then
  echo "--minutes is a whole number of minutes, at least 1" >&2
  exit 2
fi
case "$PLACEMENT" in
  inline|isolate) PLACEMENTS=("$PLACEMENT") ;;
  both) PLACEMENTS=(inline isolate) ;;
  *) echo "--placement is inline, isolate or both" >&2; exit 2 ;;
esac
LABEL="${LABEL:-$DEVICE}"

APP="$ROOT/apps/flutter3d_demo_platformer"
RUN="$ROOT/site/assets/samples/platformer.f3drun"
HARNESS="$APP/integration_test/pacing_test.dart"
if [[ ! -f "$HARNESS" || ! -f "$APP/test_driver/pacing_driver.dart" ]]; then
  echo "${APP#"$ROOT"/} has no pacing harness to soak through" >&2
  exit 2
fi

dart run tool/soak_report.dart check-fail-on "$FAIL_ON" || exit 2

# The harness must say it can place the simulation in an isolate, or the
# isolate's soak would be the inline one again under another name.
for placement in "${PLACEMENTS[@]}"; do
  if [[ "$placement" == isolate ]] &&
    ! grep -q FLUTTER3D_SOAK_PLACEMENT "$HARNESS"; then
    echo "${HARNESS#"$ROOT"/} does not read FLUTTER3D_SOAK_PLACEMENT, so it" \
      "cannot run the simulation under SimulationPlacement.isolate; soak" \
      "--placement inline, or teach the harness the define" >&2
    exit 2
  fi
done

# Where the memory and the crashes are read from.
MEMORY=none
PACKAGE=""
if [[ "$DEVICE" == macos ]]; then
  MEMORY=macos
elif command -v adb >/dev/null 2>&1 &&
  [[ "$(adb -s "$DEVICE" get-state 2>/dev/null)" == device ]]; then
  MEMORY=android
  PACKAGE="$(sed -n 's/.*applicationId *= *"\(.*\)".*/\1/p' \
    "$APP/android/app/build.gradle.kts" 2>/dev/null | head -1)"
  [[ -n "$PACKAGE" ]] || MEMORY=none
fi
case "$MEMORY" in
  android) RSS_SOURCE="adb shell dumpsys meminfo $PACKAGE" ;;
  macos) RSS_SOURCE="ps -o rss on the application" ;;
  *) RSS_SOURCE="" ;;
esac
PRODUCT="$(sed -n 's/^PRODUCT_NAME *= *//p' \
  "$APP/macos/Runner/Configs/AppInfo.xcconfig" 2>/dev/null | head -1)"

if [[ "$DRY_RUN" == true ]]; then
  echo "app:        ${APP#"$ROOT"/}"
  echo "run:        ${RUN#"$ROOT"/}, looped for $MINUTES min"
  echo "harness:    ${HARNESS#"$APP"/}"
  echo "device:     $DEVICE"
  echo "placements: ${PLACEMENTS[*]}"
  echo "fail on:    $FAIL_ON, and any crash or ANR"
  echo "memory:     ${RSS_SOURCE:-not measured on this device}"
  echo "reports:    ${OUT#"$ROOT"/}/soak-$LABEL-<placement>.md"
  exit 0
fi

if [[ "$MEMORY" == none ]]; then
  echo "no memory to read on $DEVICE: an Android device adb sees, or macos" >&2
  exit 2
fi
BUNDLE="$ROOT/packages/flutter3d_impeller/assets/shaders/flutter3d.shaderbundle"
if [[ ! -f "$BUNDLE" ]]; then
  echo "shader bundle missing; run (cd packages/flutter3d_impeller &&" \
    "dart run bin/build_shader_bundle.dart)" >&2
  exit 2
fi

# shellcheck source=pacing_rss.sh
source "$ROOT/tool/pacing_rss.sh"

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
status=0

# One placement's soak, its report written; returns non-zero when it broke
# a threshold, crashed or did not report.
soak() {
  local placement="$1" work load drove sampler watcher logcat=""
  work="$(mktemp -d "${TMPDIR:-/tmp}/flutter3d-soak.XXXXXX")"
  : > "$work/rss.txt"
  : > "$work/crash.txt"

  dart run tool/pacing_report.dart defines "$RUN" "$work/defines.json" \
    1 0 "$((MINUTES * 60))" 0 || return 2
  dart run tool/soak_report.dart define "$work/defines.json" \
    FLUTTER3D_SOAK_PLACEMENT "$placement" || return 2

  load="$( (LC_ALL=C sysctl -n vm.loadavg 2>/dev/null || cut -d' ' -f1-3 /proc/loadavg) |
    tr -d '{}' | awk '{print $1", "$2", "$3}')"

  if [[ "$MEMORY" == android ]]; then
    adb -s "$DEVICE" logcat -c 2>/dev/null
    adb -s "$DEVICE" logcat -v threadtime -b main,system,crash \
      > "$work/logcat.txt" 2>/dev/null &
    logcat=$!
  fi
  touch "$work/started"

  sample_rss "$work/rss.txt" &
  sampler=$!

  # The VM service's address, as soon as flutter drive prints it, for the
  # garbage collections.
  (
    for _ in $(seq 1 1800); do
      uri="$(grep -Eo 'http://127\.0\.0\.1:[0-9]+/[^ ]*=/' \
        "$work/drive.log" 2>/dev/null | head -1)"
      if [[ -n "$uri" ]]; then
        exec dart run tool/soak_report.dart gc "$uri" "$work/gc.txt"
      fi
      sleep 1
    done
  ) &
  watcher=$!

  echo "soaking $(basename "$RUN") on $DEVICE, $placement, $MINUTES min…"
  (
    cd "$APP" &&
      FLUTTER3D_PACING_OUT="$work/pacing.json" flutter drive --profile \
        -d "$DEVICE" \
        --driver=test_driver/pacing_driver.dart \
        --target=integration_test/pacing_test.dart \
        --dart-define-from-file="$work/defines.json"
  ) 2>&1 | tee "$work/drive.log"
  drove=${PIPESTATUS[0]}

  kill "$sampler" 2>/dev/null
  wait "$sampler" 2>/dev/null
  # The listener ends with the application; give it a moment to write.
  sleep 2
  pkill -P "$watcher" 2>/dev/null
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  if [[ -n "$logcat" ]]; then
    kill "$logcat" 2>/dev/null
    wait "$logcat" 2>/dev/null
    grep -E "ANR in $PACKAGE|FATAL EXCEPTION|Fatal signal [0-9]+.*\($PACKAGE|>>> $PACKAGE <<<" \
      "$work/logcat.txt" >> "$work/crash.txt"
  elif [[ "$MEMORY" == macos && -n "$PRODUCT" ]]; then
    find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 \
      -name "$PRODUCT*" -newer "$work/started" 2>/dev/null |
      sed 's/^/crash report: /' >> "$work/crash.txt"
  fi
  if [[ $drove -ne 0 ]]; then
    echo "flutter drive exited $drove" >> "$work/crash.txt"
  fi
  # Without the listener's file the report says the pauses were not
  # measured, not that there were none.
  [[ -s "$work/gc.txt" ]] || rm -f "$work/gc.txt"

  dart run tool/soak_report.dart report "$work/pacing.json" \
    "$work/rss.txt" "$work/gc.txt" "$work/crash.txt" "$OUT" "$LABEL" \
    "$placement" "$COMMIT" "${load:-unknown}" "$FAIL_ON"
  local reported=$?
  echo
  echo "wrote ${OUT#"$ROOT"/}/soak-$LABEL-$placement.md (scratch: $work)"
  return $reported
}

for placement in "${PLACEMENTS[@]}"; do
  soak "$placement" || status=1
done
exit $status
