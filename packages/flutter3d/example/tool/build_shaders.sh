#!/usr/bin/env bash
# Builds the example's own loadable shader bundle.
#
#   tool/build_shaders.sh
#
# Writes assets/shaders/example.f3dshaders: the stages in
# shaders/example.shaderbundle.json compiled by impellerc for Impeller,
# translated to GLSL ES for WebGL and compiled to WGSL for WebGPU, in one file
# the example loads through `GraphicsDevice.loadShaders` on whichever backend it
# is running. The `loaded-shader` golden is what it is for, so tool/golden.sh,
# golden_web.sh and conformance.sh all want this to have run.
#
# Generated and gitignored, like the engine's bundle and for the same reason:
# the Impeller section is tied to the Flutter version. Three steps, and all
# three are the ordinary tools — the engine's build_shaders.sh pointed at this
# package, the WebGPU package's section packer, then the WebGL package's bundle
# packer — so there is nothing here a second application with a bundle of its
# own would do differently.
#
# **The WGSL step is allowed to be missing and the build is not.** It needs
# glslangValidator and naga, which the green CI installs neither of, and a
# machine without them must still produce a bundle the other three backends
# read. So its exit code is read rather than trusted: 3 means "no compilers
# here", which becomes a line and a bundle with two sections, and anything else
# means the shader itself is wrong and stops the build the way a bad shader
# should.
set -euo pipefail

cd "$(dirname "$0")/.."
EXAMPLE="$(pwd)"
IMPELLER="$EXAMPLE/../../flutter3d_impeller"
WEBGL="$EXAMPLE/../../flutter3d_webgl"
WEBGPU="$EXAMPLE/../../flutter3d_webgpu"

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

WGSL="$EXAMPLE/build/example.webgpu.json"
rm -f "$WGSL"
WEBGPU_SECTION=()
WGSL_STATUS=0
(cd "$WEBGPU" && "$DART" run tool/pack_wgsl_section.dart \
  --manifest "$EXAMPLE/shaders/example.shaderbundle.json" \
  --out "$WGSL") || WGSL_STATUS=$?
if [[ $WGSL_STATUS -eq 0 ]]; then
  WEBGPU_SECTION=(--webgpu "$WGSL")
elif [[ $WGSL_STATUS -ne 3 ]]; then
  exit "$WGSL_STATUS"
fi

(cd "$WEBGL" && "$DART" run tool/pack_shaders.dart \
  --manifest "$EXAMPLE/shaders/example.shaderbundle.json" \
  --impeller "$EXAMPLE/build/example.shaderbundle" \
  ${WEBGPU_SECTION[@]+"${WEBGPU_SECTION[@]}"} \
  --name example \
  --out "$EXAMPLE/assets/shaders/example.f3dshaders")
