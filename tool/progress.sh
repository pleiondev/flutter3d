#!/usr/bin/env bash
# Builds the 1.0 progress page (tool/progress.dart) and pushes it to
# bob:/opt/f3d-progress, where nginx serves it on 127.0.0.1:8798 and the
# flutter3d Cloudflare tunnel publishes it.
#
# The hostname is unlisted rather than password-closed, so it is not in this
# repository: it is read from ~/.config/flutter3d/progress-host (or
# FLUTTER3D_PROGRESS_HOST) and only printed at the end.
#
#   tool/progress.sh [--no-structure]   rebuild the page and push it
#   tool/progress.sh --live             push only live.json, the Now panel
#
# live.json is what the work is doing this minute: the step, who is on what
# since when, the last events. It changes far more often than the plan, so it
# lives outside the repository (~/.config/flutter3d/progress-live.json, or
# FLUTTER3D_PROGRESS_LIVE) and the page reads it every ten seconds.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
server="${FLUTTER3D_PROGRESS_SERVER:-bob}"
target="${FLUTTER3D_PROGRESS_PATH:-/opt/f3d-progress}"
name="${FLUTTER3D_PROGRESS_HOST:-$(cat "$HOME/.config/flutter3d/progress-host" 2>/dev/null || true)}"
live="${FLUTTER3D_PROGRESS_LIVE:-$HOME/.config/flutter3d/progress-live.json}"

cd "$here"
if [ "${1:-}" = "--live" ]; then
  [ -f "$live" ] || { echo "no $live" >&2; exit 1; }
  rsync -az "$live" "$server:$target/live.json"
  ssh "$server" "chown www-data:www-data $target/live.json"
  echo "live.json pushed"
  exit 0
fi

dart run tool/progress.dart --out build/progress "$@"
[ -f "$live" ] && cp "$live" build/progress/live.json
rsync -az --delete build/progress/ "$server:$target/"
ssh "$server" "chown -R www-data:www-data $target"

if [ -n "$name" ]; then
  echo "deployed to https://$name/"
else
  echo "deployed to $server:$target (no hostname configured)"
fi
