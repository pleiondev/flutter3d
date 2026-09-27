#!/usr/bin/env bash
# Compares or records an application's `golden` tag the way the CI runner
# draws it, from a Mac.
#
#   tool/goldens_linux.sh apps/flutter3d_modeler            compare
#   tool/goldens_linux.sh apps/flutter3d_modeler --update   record
#   tool/goldens_linux.sh apps/flutter3d_modeler --update test/frame_test.dart
#
# **The runner's pictures are the reference.** A screenshot with Roboto in it
# rasterises its glyphs differently on macOS and on Linux, one to three per
# cent of the frame, so a set recorded on a Mac never passes in `render-apps`.
# This runs the same Flutter on the same architecture as that job, in a
# container: `linux/amd64`, which a Mac with Apple silicon runs through
# Rosetta. Native arm64 would be faster and would probably agree, but Skia's
# vector paths differ between NEON and SSE, and "probably" is what a golden
# is there to replace.
#
# **A copy, not a mount.** The checkout goes in as a tar of what git tracks
# plus what it would track, and comes back as the application's goldens
# directory and nothing else. A mounted checkout would have `flutter pub get`
# rewrite `.dart_tool/package_config.json` with the container's paths, and
# the next run on the Mac would resolve packages into a directory that does
# not exist.
#
# The pub cache and Flutter's own artifacts live in named volumes, so only the
# first run downloads them.
set -euo pipefail

FLUTTER_VERSION=3.47.0
IMAGE="ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION}"

if [[ $# -lt 1 ]]; then
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi
app=${1%/}
shift
update=""
if [[ ${1:-} == --update ]]; then
  update=--update-goldens
  shift
fi
tests=("$@")

root=$(git rev-parse --show-toplevel)
cd "$root"
[[ -d $app/test/goldens ]] || { echo "no $app/test/goldens" >&2; exit 66; }

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

set +e
git ls-files -z --cached --others --exclude-standard |
  tar --null -T - -cf - |
  docker run -i --rm --platform linux/amd64 \
    -v flutter3d-linux-pub-cache:/pub-cache \
    -e PUB_CACHE=/pub-cache \
    -v "$out":/out \
    "$IMAGE" bash -euo pipefail -c '
      mkdir /work && cd /work && tar -xf -
      flutter pub get >/dev/null
      (cd packages/flutter3d_impeller && dart run bin/build_shader_bundle.dart)
      cd "$1"; shift
      status=0
      flutter test --tags golden "$@" || status=$?
      cp -R test/goldens/. /out/
      exit $status
    ' _ "$app" $update ${tests[@]+"${tests[@]}"}
status=$?
set -e

if [[ -n $update ]]; then
  rsync -a --checksum "$out"/ "$app/test/goldens/"
  git status --short -- "$app/test/goldens"
fi
exit $status
