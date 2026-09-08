#!/usr/bin/env bash
# Builds the four games for the web into the site's own dist/demo/.
#
#   tool/demos.sh                  all four
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
# games have to be rebuilt after it, and four Flutter web builds are minutes
# even warm. That is why this is its own script and not part of the site
# build: editing prose should not cost a run of dart2wasm.
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
  "strategy:apps/flutter3d_demo_strategy"
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
  # **`--wasm` is off, and it is a workaround rather than a preference.** The
  # dart2wasm build of the WebGL backend throws on the first frame —
  # `framebufferTexture2D: parameter 4 is not of type 'WebGLTexture'` — and
  # draws nothing at all; the shooter and the platformer went out like that and
  # the racer, which reaches that path differently, did not. The same commit
  # built with dart2js renders correctly in the same browser.
  #
  # It is invisible to the tests because `flutter test --platform chrome`
  # compiles with dart2js: all one hundred and forty-eight WebGL checks pass
  # against a compiler the shipped build does not use. That gap is the real
  # defect here, and it outlives this line.
  #
  # Put `--wasm` back when the interop bug is found — and add a browser check
  # that runs against the compiler the demos actually ship with, or this
  # returns.
  #
  # **WebGPU is on for the site, and off everywhere else.** The define is what
  # decides whether the WebGPU backend is *in* the bundle at all; whether it is
  # *used* is a question only the browser can answer, so `backend_web.dart`
  # asks for an adapter and falls back to WebGL2 when there is none. The price
  # is measured in that file — 368 KiB of script on the strategy demo, 14.9% —
  # and the site is the one place worth paying it: these four builds exist to
  # show what the engine does, and one of the things it now does is draw
  # through a fourth backend. A game shipped anywhere else keeps the smaller
  # bundle by default.
  #
  # A visitor whose browser has WebGPU therefore sees the WebGPU picture, and
  # the console line from the fall back says which one arrived.
  (cd "$repo/$dir" && flutter build web --release --base-href="/demo/$name/" \
    --dart-define=FLUTTER3D_WEBGPU=true)

  target="$here/dist/demo/$name"
  mkdir -p "$target"
  rsync -a --delete "$repo/$dir/build/web/" "$target/"

  # **The bootstrap is asked for by a URL of its own, so a fresh page does not
  # make it fresh.** Everything a Flutter build emits is named without a hash,
  # and the one in front of this site keeps files by name for four hours
  # whatever the origin says about caching. When a build changed which bundle
  # the bootstrap names, the kept copy went on naming a `main.dart.mjs` that no
  # longer existed: 404, a blank frame, and an origin that had been right the
  # whole time.
  #
  # A stamp in the reference makes it a different URL, which is the one thing a
  # cache in front of us cannot argue with. Only the bootstrap: it is the file
  # that decides which bundles load, so getting it fresh is enough to get the
  # right ones, and the bundles carry their own revalidation from nginx.
  stamp="$(date -u +%Y%m%d%H%M%S)"
  perl -pi -e "s{flutter_bootstrap\\.js(\\?v=[0-9]+)?}{flutter_bootstrap.js?v=$stamp}g" \
    "$target/index.html"
  echo "   → dist/demo/$name (bootstrap v=$stamp)"
done

echo ""
echo "preview: python3 -m http.server 8765 --directory dist"
