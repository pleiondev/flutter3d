#!/usr/bin/env bash
# Builds the site and pushes it to bob:/opt/flutter3d.
#
# nginx serves it on 127.0.0.1:8790 behind basic auth, and a Cloudflare tunnel
# (cloudflared-flutter3d.service) publishes that as flutter3d.pleion.dev. None
# of that changes on a redeploy — this only replaces the files.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${FLUTTER3D_SITE_HOST:-bob}"
target="${FLUTTER3D_SITE_PATH:-/opt/flutter3d}"

cd "$here"
npm run build

# **The games are part of the site now.** `npm run build` wipes dist/, so they
# are rebuilt into it afterwards rather than before — see tool/demos.sh, which
# is a separate script because editing prose should not cost a minute of
# dart2wasm. It runs every deploy: Flutter's own incremental build makes a
# rebuild of an unchanged game about twenty seconds rather than a cold minute,
# and a demo quietly older than the engine it documents is worse than the wait.
tool/demos.sh

# --delete, because a page removed from the nav must stop being reachable.
# The generated API reference still lives beside the site rather than inside
# dist/ — twenty-three dartdoc trees are minutes to regenerate and change only
# when a public API moves — so `/docs/` is still excluded, anchored: an
# unanchored `docs/` would also match a page called that.
rsync -az --delete --exclude '/docs/' dist/ "$host:$target/"
ssh "$host" "chown -R www-data:www-data $target"

echo "deployed to https://flutter3d.pleion.dev/"
