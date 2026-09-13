#!/usr/bin/env bash
# Builds the lesson viewer for the web into
# cloud/lessons/server/build/app, served at /app/.
#
# Same shape as cloud/tool/build_viewer.sh, pointed at
# apps/flutter3d_lesson_viewer instead of apps/flutter3d_modeler: shaders are
# regenerated first because a stale translation is a blank frame, and
# `--no-web-resources-cdn` keeps CanvasKit from being fetched from
# gstatic.com.
#
# **Not `--dart-define=FLUTTER3D_WEBGPU=true` yet.** `flutter3d_lesson_viewer`
# was proved with the software `flutter3d_cpu` renderer in its own tests
# (headless, no window); turning WebGPU on for the deployed build is a
# separate decision once the tour has actually been watched running in a
# real browser (edu-02's own verification step), not assumed here.
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
