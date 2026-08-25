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

# --delete, because a page removed from the nav must stop being reachable.
# The playable builds and the generated API reference live beside the site
# instead of inside dist/, which the build wipes on every run; tool/deploy-demos.sh
# and tool/deploy-docs.sh put them there. Both excludes are anchored: an
# unanchored `demo/` also matches `platformer/demo/`, which is a documentation
# page, and deleted both demo pages on the first deploy.
rsync -az --delete --exclude '/demo/' --exclude '/docs/' dist/ "$host:$target/"
ssh "$host" "chown -R www-data:www-data $target"

echo "deployed to https://flutter3d.pleion.dev/"
