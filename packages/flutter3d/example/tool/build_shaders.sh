#!/usr/bin/env bash
# Builds the example's own loadable shader bundle.
#
#   tool/build_shaders.sh
#
# Writes assets/shaders/example.f3dshaders: the stages in
# shaders/example.shaderbundle.json compiled by impellerc for Impeller and
# translated to GLSL ES for WebGL, in one file the example loads through
# `GraphicsDevice.loadShaders` on whichever backend it is running. The
# `loaded-shader` golden is what it is for, so tool/golden.sh, golden_web.sh
# and conformance.sh all want this to have run.
#
# Generated and gitignored, like the engine's bundle and for the same reason:
# the Impeller section is tied to the Flutter version. Two steps, and both are
# the ordinary tools — the engine's build_shaders.sh pointed at this package,
# then the WebGL package's packer — so there is nothing here a second
# application with a bundle of its own would do differently.
set -euo pipefail

cd "$(dirname "$0")/.."
EXAMPLE="$(pwd)"
IMPELLER="$EXAMPLE/../../flutter3d_impeller"
WEBGL="$EXAMPLE/../../flutter3d_webgl"

# The SDK, the same way the engine's script finds it, because the packer has
# to run on the Dart that belongs to the impellerc that compiled the section:
# the bundle's header carries that Dart's version, and the Impeller backend
# holds a loaded bundle to the version it is running on.
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  SDK="$FLUTTER_ROOT"
else
  SDK="$(flutter --version --machine | tr -d ' \n' |
    sed -n 's/.*"flutterRoot":"\([^"]*\)".*/\1/p')"
fi
DART="$SDK/bin/cache/dart-sdk/bin/dart"

mkdir -p build assets/shaders

"$IMPELLER/tool/build_shaders.sh" \
  --package "$EXAMPLE" \
  --manifest shaders/example.shaderbundle.json \
  --out "$EXAMPLE/build/example.shaderbundle" \
  --package-include flutter3d_shaders

(cd "$WEBGL" && "$DART" run tool/pack_shaders.dart \
  --manifest "$EXAMPLE/shaders/example.shaderbundle.json" \
  --impeller "$EXAMPLE/build/example.shaderbundle" \
  --name example \
  --out "$EXAMPLE/assets/shaders/example.f3dshaders")
