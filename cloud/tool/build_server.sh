#!/usr/bin/env bash
# Compiles the service into one Linux x86-64 executable: cloud/server/build/models.
#
# **In a container, not on the server.** The engine packages the service reads
# models with ask for Dart 3.12.2, bob has 3.11 — and other services on that
# machine were built against it. Upgrading a shared SDK to deploy one service is
# the kind of change that breaks something unrelated a week later, so the
# compiler comes to the code instead: a pinned image, the sources copied in, and
# an executable that needs no Dart on the machine it runs on.
#
# The repository is mounted read-only and copied inside, because `pub get` in a
# bind mount would rewrite .dart_tool with container paths and break the
# developer's own checkout until their next `pub get`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$here/server/build"
image="${MODELS_DART_IMAGE:-dart:3.13}"

mkdir -p "$out"

docker run --rm --platform linux/amd64 \
  -v "$repo:/src:ro" \
  -v "$out:/out" \
  -v flutter3d-models-pub-cache:/root/.pub-cache \
  "$image" bash -euo pipefail -c '
    mkdir -p /work/cloud /work/packages
    cp -r /src/cloud/server /work/cloud/
    # The four engine packages the service depends on by path until they are
    # published. Nothing else from the repository goes in.
    for package in flutter3d_geometry flutter3d_formats flutter3d_mesh flutter3d_model_core; do
      cp -r "/src/packages/$package" /work/packages/
    done
    rm -rf /work/cloud/server/.dart_tool /work/cloud/server/build /work/packages/*/.dart_tool
    cd /work/cloud/server
    dart pub get
    dart compile exe lib/main.server.dart -o /out/models
  '

echo "built $out/models"
