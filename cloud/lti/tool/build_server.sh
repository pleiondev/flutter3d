#!/usr/bin/env bash
# Compiles the service into one Linux x86-64 executable: cloud/lti/server/build/lti.
#
# Same reasoning as cloud/tool/build_server.sh: bob's Dart is older than the
# workspace floor, and the compiler comes to the code in a pinned container.
# Unlike cloud/lessons/server (no path dependency on any engine package),
# this service depends on packages/flutter3d_education_lti by path
# (`flutter3d_lti` until 1.0.0-rc.1), so that package comes into the
# container too, at the same relative path its pubspec.yaml names
# (../../../packages/flutter3d_education_lti), with the plain Dart packages
# its overrides point at.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="$here/server/build"
image="${LTI_DART_IMAGE:-dart:3.13}"

mkdir -p "$out"

docker run --rm --platform linux/amd64 \
  -v "$repo:/src:ro" \
  -v "$out:/out" \
  -v flutter3d-lti-pub-cache:/root/.pub-cache \
  "$image" bash -euo pipefail -c '
    mkdir -p /work/cloud /work/packages
    cp -r /src/cloud/lti/server /work/cloud/
    for p in flutter3d_education_lti flutter3d_education flutter3d_fields \
        flutter3d_foundation flutter3d_matter flutter3d_plugin_api \
        flutter3d_physics flutter3d_sim; do
      cp -r "/src/packages/$p" /work/packages/
      rm -rf "/work/packages/$p/.dart_tool" "/work/packages/$p/build"
    done
    rm -rf /work/packages/flutter3d_education/example
    rm -rf /work/cloud/server/.dart_tool /work/cloud/server/build
    cd /work/cloud/server
    dart pub get
    dart compile exe lib/main.server.dart -o /out/lti
  '

echo "built $out/lti"
