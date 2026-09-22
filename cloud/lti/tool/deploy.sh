#!/usr/bin/env bash
# Builds the service and the viewer, and replaces both on bob.
#
# Same discipline as cloud/lessons/tool/deploy.sh: only replaces the
# executable and the built viewer. The environment file, the nginx vhost,
# the tunnel and the LTI platform registration are set up once, by hand —
# cloud/lti/README.md says how — and a script that creates a tunnel and a
# DNS record is a script somebody runs twice.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${LTI_HOST:-bob}"
target="${LTI_PATH:-/opt/flutter3d-lti}"

"$here/tool/build_server.sh"
"$here/tool/build_viewer.sh"

ssh "$host" "mkdir -p $target/app"

rsync -az "$here/server/build/lti" "$host:$target/lti.new"
rsync -az --delete "$here/server/build/app/" "$host:$target/app/"

ssh "$host" "set -e
  chmod 755 $target/lti.new
  mv $target/lti.new $target/lti
  chown -R www-data:www-data $target/app
  systemctl restart flutter3d-lti
  sleep 2
  systemctl is-active flutter3d-lti
  curl -fsS http://127.0.0.1:8798/health && echo"

echo "deployed to https://lti.pleion.dev/"
