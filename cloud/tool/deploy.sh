#!/usr/bin/env bash
# Builds the service and the viewer, and replaces both on bob.
#
# Only replaces: the database, the files people uploaded, the environment file,
# the nginx vhost and the tunnel all stay as they are. Setting those up the first
# time is in cloud/README.md, and is deliberately not a script — it is done once,
# and a script that creates a tunnel and a DNS record is a script somebody runs
# twice.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${MODELS_HOST:-bob}"
target="${MODELS_PATH:-/opt/flutter3d-models}"

"$here/tool/build_server.sh"
"$here/tool/build_viewer.sh"

ssh "$host" "mkdir -p $target/assets $target/app"

# The executable goes up under a second name and is renamed into place, so the
# running process is never looking at a half-copied binary.
rsync -az "$here/server/build/models" "$host:$target/models.new"
rsync -az --delete "$here/server/web/assets/" "$host:$target/assets/"
rsync -az --delete "$here/server/build/app/" "$host:$target/app/"

ssh "$host" "set -e
  chmod 755 $target/models.new
  mv $target/models.new $target/models
  chown -R www-data:www-data $target/assets $target/app
  systemctl restart flutter3d-models
  sleep 2
  systemctl is-active flutter3d-models
  curl -fsS http://127.0.0.1:8794/health && echo"

echo "deployed to https://models.pleion.dev/"
