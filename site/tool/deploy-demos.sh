#!/usr/bin/env bash
# Builds the games for the web and pushes them to bob:/opt/flutter3d/demo.
#
# Separate from tool/deploy.sh because these are ~100 MB of Flutter output that
# changes only when a game does, and because the site's own deploy uses
# --delete and would otherwise wipe them.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
host="${FLUTTER3D_SITE_HOST:-bob}"
target="${FLUTTER3D_SITE_PATH:-/opt/flutter3d}/demo"

# The generated GLSL goes stale silently: nothing checks that it matches the
# engine's own shaders, which is the same bargain the compiled Impeller bundle
# makes. Regenerating is cheap and a stale translation is a blank frame.
(cd "$here/packages/flutter3d_webgl" && dart run tool/generate_shaders.dart)

# --base-href, because the demos are served from a subdirectory. The default
# `<base href="/">` makes the app ask for /main.dart.js, which is a 404 and a
# blank page with nothing in the console but the missing file.
(cd "$here/apps/platformer" && flutter build web --release --base-href=/demo/platformer/)
(cd "$here/apps/dungeon"    && flutter build web --release --base-href=/demo/shooter/)
(cd "$here/apps/racing"     && flutter build web --release --base-href=/demo/racing/)

ssh "$host" "mkdir -p $target/platformer $target/shooter $target/racing"
rsync -az --delete "$here/apps/platformer/build/web/" "$host:$target/platformer/"
rsync -az --delete "$here/apps/dungeon/build/web/"    "$host:$target/shooter/"
rsync -az --delete "$here/apps/racing/build/web/"     "$host:$target/racing/"
ssh "$host" "chown -R www-data:www-data $target"

echo "demos deployed to https://flutter3d.pleion.dev/demo/"
