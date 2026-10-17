#!/usr/bin/env bash
# Runs the sample plugin's render checks on WebGL2, WebGPU and Impeller, and
# says so with a code.
#
#   tool/render_conformance.sh            all three
#   tool/render_conformance.sh --web      WebGL2 and WebGPU only
#   tool/render_conformance.sh --impeller Impeller only
#
# The software rasteriser and the recording fake run in the plugin example's
# own suite (`../test/render_conformance_test.dart`); these three need a
# browser and a GPU. Impeller's half is an application, because Flutter GPU
# needs Impeller and a headless test does not enable it.
set -uo pipefail

cd "$(dirname "$0")/.."

WEB=true
IMPELLER=true
for arg in "$@"; do
  case "$arg" in
    --web) IMPELLER=false ;;
    --impeller) WEB=false ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# The plugin's stages for the SDK on this machine: impellerc's output is
# refused by any other, so the bundle is built here rather than committed.
dart run tool/build_bundle.dart || exit 2

STATUS=0

if [[ "$WEB" == true ]]; then
  flutter test --platform chrome test/render_conformance_web_test.dart || STATUS=1
fi

if [[ "$IMPELLER" == true ]]; then
  # A file rather than a pipe, as the backend's conformance script does: the
  # application inherits the write end of a pipe and can hold it open.
  LOG="$(mktemp -t render_conformance.XXXXXX)"
  TIMEOUT=${FLUTTER3D_CONFORMANCE_TIMEOUT:-600}
  ( flutter run -d macos > "$LOG" 2>&1 ) &
  RUN=$!
  for ((i = 0; i < TIMEOUT; i++)); do
    if grep -q '^=== .* on impeller ===' "$LOG" || ! kill -0 "$RUN" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  sleep 2
  kill "$RUN" 2>/dev/null
  wait "$RUN" 2>/dev/null
  # The report is one print: its first line carries the `flutter: ` prefix
  # and the rest do not.
  awk '/^flutter: (PASS|SKIP|FAIL)/ { on = 1 } on { sub(/^flutter: /, ""); print }
       /^=== .* on impeller ===/ { on = 0 }' "$LOG"
  if ! grep -q '^=== [0-9]* passed, 0 failed, .* on impeller ===' "$LOG"; then
    echo "the Impeller run did not pass; its log is $LOG" >&2
    STATUS=1
  fi
fi

exit $STATUS
