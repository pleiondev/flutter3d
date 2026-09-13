#!/usr/bin/env bash
# Compiles the service into one Linux x86-64 executable:
# cloud/lessons/server/build/lessons.
#
# Same reasoning as cloud/tool/build_server.sh: bob has Dart 3.11, this
# package's floor is 3.10, and the compiler comes to the code in a pinned
# container rather than the other way round. Only this service's own
# directory goes in — it has no path dependency on any engine package.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$here/server/build"
image="${LESSONS_DART_IMAGE:-dart:3.13}"

mkdir -p "$out"

docker run --rm --platform linux/amd64 \
  -v "$here/server:/src:ro" \
  -v "$out:/out" \
  -v flutter3d-lessons-pub-cache:/root/.pub-cache \
  "$image" bash -euo pipefail -c '
    mkdir -p /work
    cp -r /src /work/server
    rm -rf /work/server/.dart_tool /work/server/build
    cd /work/server
    dart pub get
    dart compile exe lib/main.server.dart -o /out/lessons
  '

echo "built $out/lessons"
