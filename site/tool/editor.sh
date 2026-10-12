#!/usr/bin/env bash
# Builds the level editor for the web into the site's own dist/editor/.
#
#   tool/editor.sh
#
# **The editor by URL, first.** The download page leads with it, because a
# browser tab needs no certificate, no `xattr` and no build from source; the
# desktop builds of `.github/workflows/editor_release.yml` come second. It is
# served beside the modeller's pages, at /editor/, from the same deploy as
# the rest of the site, so it is never a release older than the documents
# that describe it.
#
# It runs after `npm run build` for the reason demos.sh gives (the build
# wipes dist/), and with the flags showcase.sh uses for the same reasons:
# dart2js rather than `--wasm`, the generated GLSL regenerated first,
# CanvasKit from this host, WebGPU compiled in, and the bootstrap stamped so
# the cache in front of the site cannot keep a stale one. The order is in
# tool/deploy.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
app="$repo/apps/flutter3d_editor"
target="$here/dist/editor"

(cd "$repo/packages/flutter3d_webgl" && dart run tool/generate_shaders.dart >/dev/null)

(cd "$app" && flutter build web --release --base-href="/editor/" \
  --no-web-resources-cdn --dart-define=FLUTTER3D_WEBGPU=true)

mkdir -p "$target"
rsync -a --delete "$app/build/web/" "$target/"

stamp="$(date -u +%Y%m%d%H%M%S)"
perl -pi -e "s{flutter_bootstrap\\.js(\\?v=[0-9]+)?}{flutter_bootstrap.js?v=$stamp}g" \
  "$target/index.html"

echo "   → dist/editor (bootstrap v=$stamp)"
echo "preview: python3 -m http.server 8765 --directory dist   (then /editor/)"
