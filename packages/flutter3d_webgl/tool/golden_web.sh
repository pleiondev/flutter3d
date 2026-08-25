#!/usr/bin/env bash
# Records or compares this backend's golden references, in a real browser.
#
#   tool/golden_web.sh                 compare every scene
#   tool/golden_web.sh --update        record them instead
#   tool/golden_web.sh cube-shadow     just that one
#   tool/golden_web.sh --no-build      reuse the build already there
#
# Builds the engine's example for the web — which selects this backend by
# conditional import, because `flutter3d_impeller` reaches `dart:ffi` and cannot
# be compiled for a browser at all — and then hands over to golden_web.py, which
# serves the build, answers the page's fetches and drives Chrome.
#
# **One build for the whole suite.** The scene is a query parameter rather than
# a compile-time define, so twenty-six scenes are twenty-six navigations instead
# of twenty-six dart2js runs. That is the only reason this is minutes rather
# than an hour.
set -euo pipefail

cd "$(dirname "$0")/.."
PACKAGE_DIR="$(pwd)"
EXAMPLE_DIR="$PACKAGE_DIR/../flutter3d/example"

BUILD=true
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=false ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [[ "$BUILD" == true ]]; then
  echo "building the example for the web…"
  # Not --release: the release compiler drops the assertions this engine uses to
  # say what went wrong, and a golden run that fails silently is the thing the
  # whole suite exists to prevent. Debug is also what tool/golden.sh uses on the
  # desktop, so the two runs are as alike as the platforms allow.
  (cd "$EXAMPLE_DIR" && flutter build web --profile --no-web-resources-cdn)
fi

exec python3 "$PACKAGE_DIR/tool/golden_web.py" ${ARGS[@]+"${ARGS[@]}"}
