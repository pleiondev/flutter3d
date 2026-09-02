#!/usr/bin/env bash
# Measures flutter_gpu's GpuImageSurface against Texture.asImage() on a live
# GPU, and prints what it found.
#
#   tool/surface_probe.sh          run the probe, print the report, exit by it
#   tool/surface_probe.sh --stay   leave the application up with the report
#
# The report is a handful of lines — one per present path with its UI-thread
# cost, texture count and readback, one for the resize phase — ending with
# `=== surface probe done, N failed ===`. N counts present paths whose image
# did not hold what was drawn; the timings are for reading, not for judging.
# What the numbers meant when this was written, and what was decided on them,
# is ARCHITECTURE.md §15.
#
# A script driving an application, for the reason conformance.sh is one:
# Flutter GPU needs Impeller, which a headless `flutter test` does not enable.
set -uo pipefail

cd "$(dirname "$0")/.."
EXAMPLE_DIR="$(pwd)/../flutter3d/example"

STAY=false
for arg in "$@"; do
  case "$arg" in
    --stay) STAY=true ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$STAY" == true ]]; then
  ( cd "$EXAMPLE_DIR" && exec flutter run -d macos -t lib/surface_probe_main.dart \
      --dart-define=stay=true )
  exit $?
fi

# A cold build is minutes; the probe itself is four phases of a few seconds
# each, paced by the display.
TIMEOUT=${FLUTTER3D_PROBE_TIMEOUT:-600}

# A file rather than command substitution, as golden.sh explains: the
# application inherits the write end of a pipe and a surviving app holds the
# substitution open long after `flutter run` has exited.
LOG="$(mktemp -t flutter3d_surface_probe)"
trap 'rm -f "$LOG"' EXIT

( cd "$EXAMPLE_DIR" && exec flutter run -d macos --debug \
    -t lib/surface_probe_main.dart ) >"$LOG" 2>&1 &
PID=$!

WAITED=0
while kill -0 "$PID" 2>/dev/null; do
  if [[ $WAITED -ge $TIMEOUT ]]; then
    kill -TERM "$PID" 2>/dev/null || true
    sleep 2
    kill -9 "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    echo "timed out after ${TIMEOUT}s"
    sed -n '1,40p' "$LOG"
    exit 124
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done
wait "$PID" 2>/dev/null

if ! grep -q '=== surface probe done, .* failed ===' "$LOG"; then
  echo "the application never reported. Last of its output:"
  grep -vE '^(Launching|Syncing|Building|Flutter run|[a-z] [A-Z])' "$LOG" | tail -20
  exit 1
fi

grep -E '^(flutter: )?(surface-probe|ring |surface |trailing |churn |resize |=== )' "$LOG" \
  | sed 's/^flutter: //'

if grep -q '=== surface probe done, 0 failed ===' "$LOG"; then
  exit 0
fi
exit 1
