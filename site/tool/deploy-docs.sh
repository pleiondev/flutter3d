#!/usr/bin/env bash
# Builds the API reference and pushes it to bob:/opt/flutter3d/docs.
#
# Separate from tool/deploy.sh because the two change at different rates: the
# prose is edited daily and the generated reference only when the source's public
# API moves. Running dartdoc over every package to publish a typo fix would
# be minutes of work for nothing.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${FLUTTER3D_SITE_HOST:-bob}"
target="${FLUTTER3D_SITE_PATH:-/opt/flutter3d}"

cd "$here"
tool/build-docs.sh

# --delete, because a package that goes away must stop being reachable. Safe to
# use here where it is not in deploy.sh: this rsync's target is the docs
# directory alone, so nothing else on the server is in its scope.
rsync -az --delete docs-dist/ "$host:$target/docs/"
ssh "$host" "chown -R www-data:www-data $target/docs"

echo "deployed to https://flutter3d.pleion.dev/docs/"
