#!/usr/bin/env bash
# Builds the showcase app for the web into the site's own dist/showcase/.
#
#   tool/showcase.sh
#
# **The app goes beside its guides, in the same directory.** `npm run build`
# has already written /showcase/learn/ and /showcase/source/ there, from the
# bundle `apps/flutter3d_showcase/tool/showcase_bundle.dart` wrote, and the app
# is copied in around them. That is why the rsync below excludes both, and why
# the exclude is anchored: an unanchored `learn/` would also match a directory
# of that name deeper in the Flutter build, and a plain `--delete` without the
# exclude would delete every guide the moment the app was copied in. It is the
# mistake `tool/demos.sh` tells about `demo/`, and it is made the same way.
#
# It runs after `npm run build` for the reason demos.sh does: the build wipes
# dist/. The order is in tool/deploy.sh.
#
# The flags are the demos' flags, and for the same reasons, which demos.sh
# spells out: dart2js and not `--wasm` (the WebGL backend throws on its first
# frame under dart2wasm), the generated GLSL regenerated first, WebGPU compiled
# in so a browser that has it uses it, and the bootstrap stamped so the cache in
# front of the site cannot keep a stale one.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
app="$repo/apps/flutter3d_showcase"
target="$here/dist/showcase"

# A missing learn/ means npm run build has not run, or ran without the bundle:
# copying the app in now would leave a site whose guides are 404, and nobody
# would be told.
if [[ ! -f "$target/learn/index.html" ]]; then
  echo "dist/showcase/learn/ is missing: run the bundle and 'npm run build' first" >&2
  exit 1
fi

(cd "$repo/packages/flutter3d_webgl" && dart run tool/generate_shaders.dart >/dev/null)

# --no-web-resources-cdn: CanvasKit comes from this host and not from gstatic,
# as the modeller's build does, so the page works with that host blocked.
(cd "$app" && flutter build web --release --base-href="/showcase/" \
  --no-web-resources-cdn --dart-define=FLUTTER3D_WEBGPU=true)

rsync -a --delete --exclude '/learn/' --exclude '/source/' "$app/build/web/" "$target/"

stamp="$(date -u +%Y%m%d%H%M%S)"
perl -pi -e "s{flutter_bootstrap\\.js(\\?v=[0-9]+)?}{flutter_bootstrap.js?v=$stamp}g" \
  "$target/index.html"

echo "   → dist/showcase (bootstrap v=$stamp)"
echo "preview: python3 -m http.server 8765 --directory dist   (then /showcase/)"
