#!/usr/bin/env bash
# Plays a recorded run through the renderer on a real device, times every
# frame, writes the report kept in doc/pacing/, and fails on any frame longer
# than 50 ms — N3.
#
#   tool/pacing.sh                          macOS (Impeller), the sample run
#   tool/pacing.sh -d <device-id> --label a55
#   tool/pacing.sh --run path/to/run.f3drun --repeats 5 --budget 2000
#   tool/pacing.sh --label macos-ci
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
APP="$ROOT/apps/flutter3d_demo_dungeon"

RUN="$ROOT/site/assets/samples/shooter.f3drun"
DEVICE=macos
LABEL=""
REPEATS=3
BUDGET=0
WRITE_REPORT=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --run) RUN="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
    --repeats) REPEATS="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --no-report) WRITE_REPORT=false; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
LABEL="${LABEL:-$DEVICE}"

if [[ ! -f "$RUN" ]]; then
  echo "no run at $RUN" >&2
  exit 2
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
  "$LABEL" "$COMMIT" "${LOAD:-unknown}"
status=$?
if [[ "$WRITE_REPORT" == true ]]; then
  echo
  echo "wrote ${REPORT#"$ROOT"/}"
fi
exit $status
