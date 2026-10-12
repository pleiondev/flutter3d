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
#   tool/pacing.sh --demo racing -d <a55> --warm-up 60 --seconds 120 \
#     --fail-on p50=16.7,p99=33.3,over50=0.1,max=100,rssGrowth=1.10,rssEnd=400
#
# `--demo` is one of the three the release proof is measured on: shooter
# (the dungeon, the default; `dungeon` names it too), platformer and racing.
# Each is played by its own application's `integration_test/pacing_test.dart`
# from its own tape in `site/assets/samples/`; an application without that
# harness is refused by name rather than played through another game's. The
# report is `doc/pacing/<label>.md`, the label being the device for the
# shooter and `<device>-<demo>` for the other two unless `--label` says.
#
# `--seconds` and `--warm-up` size the run in seconds of play, a step being a
# sixtieth: the tape is looped in as many whole passes as cover them, and the
# warm-up's passes are played and not counted. Without `--seconds` the run is
# `--repeats` passes.
#
# `--fail-on` holds the run to thresholds in place of "no frame over 50 ms":
# `p50`, `p99` and `max` in milliseconds, `over50` as the per cent of frames
# over the limit, `rssGrowth` as the resident memory at the end over the
# value 30 s in, and `rssEnd` as the resident memory at the end in MB,
# comma-separated (`p50=16.7,p99=33.3,over50=0.1,max=100,rssGrowth=1.10,
# rssEnd=400` is P1 whole on the A55, `rssEnd=300` on the iPhone). The
# nightly holds the Galaxy A55 to `p99=33.3`. A value on the line passes; a
# memory line on a device whose memory was not read fails.
#
# **Resident memory, once a second, while the run plays.** On an Android
# device through `adb shell dumpsys meminfo <package>` (its TOTAL RSS), on
# macOS through `ps` on the application's own binary; nowhere else yet, and
# the report says so. Counted from the first sample, when the application is
# up, so "30 s" is thirty seconds after it started.
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
SECONDS_TIMED=0
WARM_UP=0
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
    --seconds) SECONDS_TIMED="$2"; shift 2 ;;
    --warm-up) WARM_UP="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --fail-on) FAIL_ON="$2"; shift 2 ;;
    --no-report) WRITE_REPORT=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# The demo's application, by the name the site serves it under.
case "$DEMO" in
  shooter|dungeon) DEMO=shooter; APP="$ROOT/apps/flutter3d_demo_dungeon" ;;
  platformer) APP="$ROOT/apps/flutter3d_demo_platformer" ;;
  racing) APP="$ROOT/apps/flutter3d_demo_racing" ;;
  *) echo "no demo called '$DEMO': shooter, platformer or racing" >&2; exit 2 ;;
esac
RUN="${RUN:-$ROOT/site/assets/samples/$DEMO.f3drun}"
if [[ "$DEMO" == shooter ]]; then
  LABEL="${LABEL:-$DEVICE}"
else
  LABEL="${LABEL:-$DEVICE-$DEMO}"
fi

if [[ ! -f "$RUN" ]]; then
  echo "no run at $RUN" >&2
  exit 2
fi

# The thresholds are read before anything is built, so a misspelt key costs
# a second and not a build.
if [[ -n "$FAIL_ON" ]]; then
  dart run tool/pacing_report.dart check-fail-on "$FAIL_ON" || exit 2
fi

# Where the memory is read from: an Android device through adb, this Mac
# through ps, anything else not at all.
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

if [[ "$DRY_RUN" == true ]]; then
  echo "demo:      $DEMO"
  echo "app:       ${APP#"$ROOT"/}"
  echo "run:       ${RUN#"$ROOT"/}"
  echo "device:    $DEVICE"
  echo "label:     $LABEL"
  echo "fail on:   ${FAIL_ON:-any frame over 50 ms}"
  echo "memory:    ${RSS_SOURCE:-not measured on this device}"
fi

HARNESS="$APP/integration_test/pacing_test.dart"
if [[ ! -f "$HARNESS" || ! -f "$APP/test_driver/pacing_driver.dart" ]]; then
  echo "${APP#"$ROOT"/} has no pacing harness: it needs" \
    "${HARNESS#"$ROOT"/} and test_driver/pacing_driver.dart, as" \
    "apps/flutter3d_demo_dungeon has" >&2
  exit 2
fi
# A warm-up the harness does not read would be timed as play.
if [[ "$WARM_UP" != 0 ]] && ! grep -q FLUTTER3D_PACING_WARMUP "$HARNESS"; then
  echo "${HARNESS#"$ROOT"/} plays no warm-up; run without --warm-up" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/flutter3d-pacing.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

dart run tool/pacing_report.dart defines "$RUN" "$WORK/defines.json" \
  "$REPEATS" "$BUDGET" "$SECONDS_TIMED" "$WARM_UP" || exit 2

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

# One resident-memory sample a second into $1, `<seconds> <kB>` a line,
# counted from the first sample the application answers.
sample_rss() {
  local out="$1" start="" kb pid now
  while :; do
    kb=""
    case "$MEMORY" in
      android)
        kb="$(adb -s "$DEVICE" shell dumpsys meminfo "$PACKAGE" 2>/dev/null |
          awk '/TOTAL RSS:/ { for (i = 1; i < NF; i++) if ($i == "RSS:") { print $(i + 1); exit } }')"
        ;;
      macos)
        # The profile build's own binary, not another checkout's game.
        pid="$(pgrep -f "$APP/build/macos/Build/Products/Profile/" | head -1)"
        [[ -n "$pid" ]] && kb="$(ps -o rss= -p "$pid" | tr -d ' ')"
        ;;
    esac
    if [[ "$kb" =~ ^[0-9]+$ ]]; then
      now="$(date +%s)"
      start="${start:-$now}"
      echo "$((now - start)) $kb" >> "$out"
    fi
    sleep 1
  done
}

# Read before the run, so the build's own load is over and the run's has not
# begun. macOS has no /proc. In the C locale, because sysctl otherwise
# writes a decimal comma and the three numbers run together in the report.
LOAD="$( (LC_ALL=C sysctl -n vm.loadavg 2>/dev/null || cut -d' ' -f1-3 /proc/loadavg) |
  tr -d '{}' | awk '{print $1", "$2", "$3}')"

SAMPLER=""
if [[ "$MEMORY" != none ]]; then
  sample_rss "$WORK/rss.txt" &
  SAMPLER=$!
  trap 'kill "$SAMPLER" 2>/dev/null; rm -rf "$WORK"' EXIT
fi

echo "playing $(basename "$RUN") on ${DEVICE}…"
(
  cd "$APP" &&
    FLUTTER3D_PACING_OUT="$WORK/pacing.json" flutter drive --profile \
      -d "$DEVICE" \
      --driver=test_driver/pacing_driver.dart \
      --target=integration_test/pacing_test.dart \
      --dart-define-from-file="$WORK/defines.json"
)
drove=$?
if [[ -n "$SAMPLER" ]]; then
  kill "$SAMPLER" 2>/dev/null
  wait "$SAMPLER" 2>/dev/null
fi
if [[ $drove -ne 0 || ! -f "$WORK/pacing.json" ]]; then
  echo "the run did not report (flutter drive exited $drove)" >&2
  exit 1
fi
if [[ "$MEMORY" != none ]]; then
  dart run tool/pacing_report.dart rss "$WORK/pacing.json" "$WORK/rss.txt" \
    "$RSS_SOURCE" || exit 1
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
