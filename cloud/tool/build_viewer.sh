#!/usr/bin/env bash
# Builds the modeller for the web into cloud/server/build/app, served at /app/.
#
# The same build the documentation site's demos get, for the same reasons, and
# the reasons are written down in site/tool/demos.sh rather than repeated: the
# generated GLSL is regenerated first because a stale translation is a blank
# frame, `--wasm` stays off because the WebGL backend's dart2wasm build draws
# nothing, and the WebGPU backend is compiled in so a browser that has an
# adapter gets it.
#
# One addition: `--no-web-resources-cdn`. Flutter otherwise fetches CanvasKit
# from gstatic.com, and the privacy page says these pages load nothing from
# anywhere else.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$here/server/build/app"

(cd "$repo/packages/flutter3d_webgl" && dart run tool/generate_shaders.dart >/dev/null)

(cd "$repo/apps/flutter3d_modeler" && flutter build web --release \
  --base-href=/app/ \
  --no-web-resources-cdn \
  --dart-define=FLUTTER3D_WEBGPU=true)

rm -rf "$out"
mkdir -p "$(dirname "$out")"
cp -R "$repo/apps/flutter3d_modeler/build/web" "$out"

echo "built $out"
