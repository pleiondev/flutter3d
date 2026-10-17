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
#
# And the mode, from MODELS_EDITOR — the same setting the service reads, so a
# build and the server it is deployed beside say the same thing. `off` (the
# default) compiles the modeller as a viewer: rendering, orbiting, display
# modes and preview pictures, no editing tools, no autosave, no save-back.
# `on` compiles the whole editor. `tool/deploy.sh` reads the setting from the
# unit on the server and passes it here.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$here/server/build/app"

case "${MODELS_EDITOR:-off}" in
  on) mode=editor ;;
  off) mode=viewer ;;
  *) echo "MODELS_EDITOR is '${MODELS_EDITOR}'; it is on or off" >&2; exit 1 ;;
esac

(cd "$repo/packages/flutter3d_webgl" && dart run tool/generate_shaders.dart >/dev/null)

(cd "$repo/apps/flutter3d_modeler" && flutter build web --release \
  --base-href=/app/ \
  --no-web-resources-cdn \
  --dart-define=FLUTTER3D_WEBGPU=true \
  --dart-define=FLUTTER3D_MODELER_MODE=$mode)

rm -rf "$out"
mkdir -p "$(dirname "$out")"
cp -R "$repo/apps/flutter3d_modeler/build/web" "$out"

echo "built $out ($mode)"
