#!/usr/bin/env bash
# Builds the service and the viewer, and replaces both on bob.
#
# Same discipline as cloud/tool/deploy.sh: only replaces the executable and
# the built viewer. The environment file, the nginx vhost and the tunnel are
# set up once, by hand — cloud/lessons/README.md says how — and a script that
# creates a tunnel and a DNS record is a script somebody runs twice.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${LESSONS_HOST:-bob}"
target="${LESSONS_PATH:-/opt/flutter3d-lessons}"

"$here/tool/build_server.sh"
"$here/tool/build_viewer.sh"

ssh "$host" "mkdir -p $target/app"

# The executable goes up under a second name and is renamed into place, so
# the running process is never looking at a half-copied binary.
rsync -az "$here/server/build/lessons" "$host:$target/lessons.new"
rsync -az --delete "$here/server/build/app/" "$host:$target/app/"

ssh "$host" "set -e
  chmod 755 $target/lessons.new
  mv $target/lessons.new $target/lessons
  chown -R www-data:www-data $target/app
  systemctl restart flutter3d-lessons
  sleep 2
  systemctl is-active flutter3d-lessons
  curl -fsS http://127.0.0.1:8796/health && echo"

echo "deployed to https://lessons.pleion.dev/"
