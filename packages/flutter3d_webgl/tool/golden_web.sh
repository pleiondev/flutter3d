#!/usr/bin/env bash
# Records or compares a browser backend's golden references, in a real browser.
#
#   tool/golden_web.sh                    compare every scene, on WebGL2
#   tool/golden_web.sh --update           record them instead
#   tool/golden_web.sh cube-shadow        just that one
#   tool/golden_web.sh --no-build         reuse the build already there
#   tool/golden_web.sh --backend=webgpu   hold the other browser backend to its
#                                         own set instead
#
# Builds the engine's example for the web — which excludes Impeller by
# conditional import, because `flutter3d_impeller` reaches `dart:ffi` and cannot
# be compiled for a browser at all — and then hands over to golden_web.py, which
# serves the build, answers the page's fetches and drives Chrome. Every argument
# but `--no-build` goes straight through, `--backend=` included: the build is
# the same one either way, so this script has no reason to read it.
#
# **One build for the whole suite, and for both browser backends.** The scene is
# a query parameter rather than a compile-time define, so the forty-three scenes
# are one dart2js run and a navigation each, rather than a dart2js run each.
# That is the only reason this is minutes rather than an hour, and it is why the
# backend arrives the same way: a define per backend would have spent the saving
# twice over.
#
# One number, on purpose. The line used to carry three; a structure rule holds
# the count of scenes and nothing held the other two, so they were bumped by
# hand until they disagreed with it and with each other.
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
  # The example's own loadable bundle, for `loaded-shader`: its pubspec
  # declares the asset, so the web build fails without it, naming an asset
  # rather than the script that writes one.
  if [[ ! -f "$EXAMPLE_DIR/assets/shaders/example.f3dshaders" ]]; then
    echo "the example's shader bundle is missing; run $EXAMPLE_DIR/tool/build_shaders.sh" >&2
    exit 2
  fi
  echo "building the example for the web…"
  # Not --release: the release compiler drops the assertions this engine uses to
  # say what went wrong, and a golden run that fails silently is the thing the
  # whole suite exists to prevent. Debug is also what tool/golden.sh uses on the
  # desktop, so the two runs are as alike as the platforms allow.
  (cd "$EXAMPLE_DIR" && flutter build web --profile --no-web-resources-cdn)
fi

exec python3 "$PACKAGE_DIR/tool/golden_web.py" ${ARGS[@]+"${ARGS[@]}"}
