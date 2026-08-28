#!/usr/bin/env bash
# Builds the three games for the web into the site's own dist/demo/.
#
#   tool/demos.sh                  all three
#   tool/demos.sh shooter          just one
#
# **They go inside dist/ now**, which is the whole point of this script
# existing: the playable builds used to live beside the site on the server,
# pushed by a second deploy that had to exclude them from the first one's
# `--delete`. Two rsyncs with an anchored exclude between them is a thing that
# breaks quietly — an unanchored `demo/` matched `platformer/demo/` once and
# deleted two documentation pages — and a page that links to a build the site
# does not carry is a broken link nobody notices until somebody clicks it.
#
# The cost is stated rather than hidden: `npm run build` wipes dist/, so the
# games have to be rebuilt after it, and three Flutter web builds are about a
# minute even warm. That is why this is its own script and not part of the site
# build: editing prose should not cost a minute of dart2wasm.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"

# The generated GLSL goes stale silently: nothing in a web build checks that it
# matches `flutter3d_shaders`, which is the same bargain the compiled Impeller
# bundle makes. Regenerating is seconds and a stale translation is a blank
# frame.
(cd "$repo/packages/flutter3d_webgl" && dart run tool/generate_shaders.dart >/dev/null)

# name:directory. The URL each is served from is /demo/<name>/, which is what
# the iframes in content/*/demo.md point at.
games=(
  "shooter:apps/flutter3d_demo_dungeon"
  "platformer:apps/flutter3d_demo_platformer"
  "racing:apps/flutter3d_demo_racing"
)

wanted="${1:-}"

for entry in "${games[@]}"; do
  name="${entry%%:*}"
  dir="${entry#*:}"
  if [[ -n "$wanted" && "$wanted" != "$name" ]]; then continue; fi

  echo "── $name"
  # --base-href, because the demos are served from a subdirectory: Flutter's
  # default `<base href="/">` makes the app ask for /main.dart.js, which is a
  # 404 and a blank page with nothing in the console but the missing file.
  #
  # --wasm builds dart2wasm and the JavaScript output together, and
  # flutter_bootstrap.js picks between them at load. The games are the one thing
  # on this site that spends its frame budget in Dart rather than in a driver.
  (cd "$repo/$dir" && flutter build web --wasm --release --base-href="/demo/$name/")

  target="$here/dist/demo/$name"
  mkdir -p "$target"
  rsync -a --delete "$repo/$dir/build/web/" "$target/"
  echo "   → dist/demo/$name"
done

echo ""
echo "preview: python3 -m http.server 8765 --directory dist"
