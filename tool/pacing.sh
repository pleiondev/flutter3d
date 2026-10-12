#!/usr/bin/env bash
# Plays a recorded run through the renderer on a real device, times every
# frame, writes the report kept in doc/pacing/, and fails on any frame longer
# than 50 ms — N3.
#
#   tool/pacing.sh                          macOS (Impeller), the sample run
#   tool/pacing.sh -d <device-id> --label a55
#   tool/pacing.sh --run path/to/run.f3drun --repeats 5 --budget 2000
#   tool/pacing.sh --label macos-ci
#   tool/pacing.sh --demo racing -d <device-id> --fail-on p99=33.3
#   tool/pacing.sh --demo platformer --dry-run
#
# `--demo` is one of the three the release proof is measured on: shooter
# (the dungeon, the default), platformer and racing. Each is played by its
# own application's `integration_test/pacing_test.dart` from its own tape in
# `site/assets/samples/`; an application without that harness is refused by
# name rather than played through another game's.
#
# `--fail-on` holds the run to thresholds in place of "no frame over 50 ms":
# `p50`, `p99` and `max` in milliseconds, `over50` as the per cent of frames
# over the limit, comma-separated (`p50=16.7,p99=33.3,over50=0.1,max=100`
# is P1 whole). The nightly holds the Galaxy A55 to `p99=33.3`. A value on
# the line passes.
#
# `--dry-run` checks the demo, the tape, the harness and the thresholds and
# prints what it would run, without building: the nightly's steps proved to
# resolve on a machine with no phone attached.
#
# **Frame-time spikes, not frame rate.** A run that averages sixty frames a
# second can still stop for a tenth of a second every few seconds, and that
# stop is what a player feels; three 60 Hz frames, 50 ms, is the line. The
# report keeps the median, the 99th percentile, the worst frame and where on
# the tape it fell, so a spike can be found again by replaying to it.
#
# The frames are drawn back to back, each timed from the simulation step to
# the GPU finishing its draw, at 1280x720 by default: what a frame costs,
# not how long it waited for a display. See `replayPacing` in
# flutter3d_testing for why that errs on the long side.
#
# Through `flutter drive --profile`, because `flutter test` on a device builds
# debug and a JIT frame time is not a frame time. The run reaches the device
# as a define rather than a path: neither a sandboxed macOS app nor a phone
# can read the repository.
#
# The same command runs on the release phone by hand before a release
# (`-d <id> --label a55`), and its report is committed beside the others.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

DEMO=shooter
RUN=""
DEVICE=macos
LABEL=""
REPEATS=3
BUDGET=0
FAIL_ON=""
WRITE_REPORT=true
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="$2"; shift 2 ;;
    --demo) DEMO="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --run) RUN="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
    --repeats) REPEATS="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --fail-on) FAIL_ON="$2"; shift 2 ;;
    --no-report) WRITE_REPORT=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
LABEL="${LABEL:-$DEVICE}"

# The demo's application, by the name the site serves it under.
case "$DEMO" in
  shooter) APP="$ROOT/apps/flutter3d_demo_dungeon" ;;
  platformer) APP="$ROOT/apps/flutter3d_demo_platformer" ;;
  racing) APP="$ROOT/apps/flutter3d_demo_racing" ;;
  *) echo "no demo called '$DEMO': shooter, platformer or racing" >&2; exit 2 ;;
esac
RUN="${RUN:-$ROOT/site/assets/samples/$DEMO.f3drun}"

if [[ ! -f "$RUN" ]]; then
  echo "no run at $RUN" >&2
  exit 2
fi

# The thresholds are read before anything is built, so a misspelt key costs
# a second and not a build.
if [[ -n "$FAIL_ON" ]]; then
  dart run tool/pacing_report.dart check-fail-on "$FAIL_ON" || exit 2
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "demo:      $DEMO"
  echo "app:       ${APP#"$ROOT"/}"
  echo "run:       ${RUN#"$ROOT"/}"
  echo "device:    $DEVICE"
  echo "label:     $LABEL"
  echo "repeats:   $REPEATS"
  echo "fail on:   ${FAIL_ON:-any frame over 50 ms}"
fi

HARNESS="$APP/integration_test/pacing_test.dart"
if [[ ! -f "$HARNESS" || ! -f "$APP/test_driver/pacing_driver.dart" ]]; then
  echo "${APP#"$ROOT"/} has no pacing harness: it needs" \
    "${HARNESS#"$ROOT"/} and test_driver/pacing_driver.dart, as" \
    "apps/flutter3d_demo_dungeon has" >&2
  exit 2
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "harness:   ${HARNESS#"$APP"/}"
  exit 0
fi

# Built rather than committed, like every application that draws.
BUNDLE="$ROOT/packages/flutter3d_impeller/assets/shaders/flutter3d.shaderbundle"
if [[ ! -f "$BUNDLE" ]]; then
  echo "shader bundle missing; run (cd packages/flutter3d_impeller &&" \
    "dart run bin/build_shader_bundle.dart)" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/flutter3d-pacing.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

dart run tool/pacing_report.dart defines "$RUN" "$WORK/defines.json" \
  "$REPEATS" "$BUDGET" || exit 2

# Read before the run, so the build's own load is over and the run's has not
# begun. macOS has no /proc. In the C locale, because sysctl otherwise
# writes a decimal comma and the three numbers run together in the report.
LOAD="$( (LC_ALL=C sysctl -n vm.loadavg 2>/dev/null || cut -d' ' -f1-3 /proc/loadavg) |
  tr -d '{}' | awk '{print $1", "$2", "$3}')"

echo "playing $(basename "$RUN") on $DEVICE, $REPEATS passes…"
(
  cd "$APP" &&
    FLUTTER3D_PACING_OUT="$WORK/pacing.json" flutter drive --profile \
      -d "$DEVICE" \
      --driver=test_driver/pacing_driver.dart \
      --target=integration_test/pacing_test.dart \
      --dart-define-from-file="$WORK/defines.json"
)
drove=$?
if [[ $drove -ne 0 || ! -f "$WORK/pacing.json" ]]; then
  echo "the run did not report (flutter drive exited $drove)" >&2
  exit 1
fi

REPORT="$ROOT/doc/pacing/$LABEL.md"
if [[ "$WRITE_REPORT" != true ]]; then
  REPORT="$WORK/report.md"
fi
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
dart run tool/pacing_report.dart report "$WORK/pacing.json" "$REPORT" \
  "$LABEL" "$COMMIT" "${LOAD:-unknown}" ${FAIL_ON:+"$FAIL_ON"}
status=$?
if [[ "$WRITE_REPORT" == true ]]; then
  echo
  echo "wrote ${REPORT#"$ROOT"/}"
fi
exit $status
