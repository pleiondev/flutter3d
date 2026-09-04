#!/usr/bin/env bash
# Runs flutter3d_conformance against this backend, and says so with a code.
#
#   tool/conformance.sh          run the checks and exit non-zero on a failure
#   tool/conformance.sh --stay   leave the application up with the list on screen
#
# **Why this is a script and not a test.** Flutter GPU needs Impeller, and a
# headless `flutter test` does not enable it — the same platform fact that makes
# `packages/flutter3d/tool/golden.sh` drive an application. The checks are the
# same list either way; only the harness differs.
#
# **Why it exists at all.** Before it, the only way this backend's conformance
# was ever checked was somebody remembering to open the app and read a list. It
# went unrun long enough that a check added *together with* a fix had never once
# been executed on the backend the fix was for — which was found by running it
# by hand and is exactly the sort of thing nobody finds twice.
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

# The bundle is impellerc output and only this backend can read it. Without it
# the application starts and every check fails on a shader it cannot find, which
# reads as a broken backend and is a missing build step.
BUNDLE="$(pwd)/assets/shaders/flutter3d.shaderbundle"
if [[ ! -f "$BUNDLE" ]]; then
  echo "shader bundle missing; run tool/build_shaders.sh" >&2
  exit 2
fi

# And the example's own loadable bundle, which its pubspec declares: Flutter
# will not build the harness without it, and the message it gives names an
# asset rather than the script that writes one.
LOADABLE="$EXAMPLE_DIR/assets/shaders/example.f3dshaders"
if [[ ! -f "$LOADABLE" ]]; then
  echo "the example's shader bundle is missing; run $EXAMPLE_DIR/tool/build_shaders.sh" >&2
  exit 2
fi

if [[ "$STAY" == true ]]; then
  ( cd "$EXAMPLE_DIR" && exec flutter run -d macos -t lib/conformance_main.dart \
      --dart-define=stay=true )
  exit $?
fi

# Long enough for a cold build, which is minutes rather than seconds. The checks
# themselves take under a second: they are clears, uploads and a handful of
# draws into sixteen-pixel targets.
TIMEOUT=${FLUTTER3D_CONFORMANCE_TIMEOUT:-600}

# A file rather than command substitution, for the reason golden.sh writes down:
# the application inherits the write end of a pipe, so a surviving app holds the
# substitution open long after `flutter run` has exited — which looks like a
# hang and is not.
LOG="$(mktemp -t flutter3d_conformance)"
trap 'rm -f "$LOG"' EXIT

( cd "$EXAMPLE_DIR" && exec flutter run -d macos --debug \
    -t lib/conformance_main.dart ) >"$LOG" 2>&1 &
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

# The verdict comes from the printed report rather than from `flutter run`'s own
# status, which reports on the tool and not on the application. The application
# exits with a code of its own; this is the second half of the same statement,
# and it also catches a run that never reached the report at all.
# **Matched loosely on purpose, and it was not loose enough once.** The report
# grew a third number when a check the backend cannot be asked stopped counting
# as a pass, and both patterns here were anchored on `failed ===` — so the first
# run after that change reported "the application never reported" on a run where
# all thirty-one checks passed. A verdict read out of a printed line has to be
# written to survive the line gaining a field, because the line will.
if ! grep -qE '=== [0-9]+ passed, [0-9]+ failed' "$LOG"; then
  echo "the application never reported. Last of its output:"
  grep -vE '^(Launching|Syncing|Building|Flutter run|[a-z] [A-Z])' "$LOG" | tail -20
  exit 1
fi

grep -E '^(flutter: )?(PASS|FAIL|SKIP|        |=== )' "$LOG" | sed 's/^flutter: //'

# A decline is not a failure — the backend was asked something it is not in a
# position to answer, and said so. It is also not nothing, so it is named rather
# than left to be counted off the report line by whoever reads it.
DECLINED=$(sed -n 's/.*failed, \([0-9]\+\) declined ===.*/\1/p' "$LOG" | tail -1)
if [[ -n "${DECLINED:-}" && "$DECLINED" != 0 ]]; then
  echo "($DECLINED check(s) declined — this backend was not asked them)"
fi

if grep -qE '=== [0-9]+ passed, 0 failed' "$LOG"; then
  exit 0
fi
exit 1
