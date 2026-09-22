#!/usr/bin/env bash
# Builds the lesson viewer for the web into cloud/lti/server/build/app,
# served at /app/ — the same build cloud/lessons/tool/build_viewer.sh makes,
# copied rather than shared for the reason its own comment gives: this
# service resolves its dependencies independently.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="$here/server/build/app"

(cd "$repo/packages/flutter3d_webgl" && dart run tool/generate_shaders.dart >/dev/null)

(cd "$repo/apps/flutter3d_lesson_viewer" && flutter build web --release \
  --base-href=/app/ \
  --no-web-resources-cdn)

rm -rf "$out"
mkdir -p "$(dirname "$out")"
cp -R "$repo/apps/flutter3d_lesson_viewer/build/web" "$out"

echo "built $out"
