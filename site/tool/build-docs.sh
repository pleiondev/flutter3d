#!/usr/bin/env bash
# Generates the API reference into site/docs-dist/, one tree per package.
#
#   tool/build-docs.sh              every package
#   tool/build-docs.sh flutter3d    one of them, while iterating
#
# `dart doc` produces a self-contained tree per package and has no way to merge
# several into one index, so this writes the index itself — from the packages on
# disk rather than from a list, because a hand-kept list is the thing that goes
# stale the day somebody adds a package.
#
# The output does **not** go into site/dist/: `npm run build` wipes that on every
# run, and regenerating a dartdoc tree per package to publish a typo fix would be
# minutes of work for nothing. It is deployed separately by tool/deploy-docs.sh,
# and tool/deploy.sh excludes /docs/ for the same reason it excludes /demo/.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$here/docs-dist"
logs="$here/.docs-logs"

only="${1:-}"
rm -rf "$out" "$logs"
mkdir -p "$out"

generated=()
for dir in "$repo"/packages/*/; do
  name="$(basename "$dir")"
  if [ -n "$only" ] && [ "$name" != "$only" ]; then continue; fi
  # **A directory is not a package.** The twelve folded into others for 0.7.0
  # left their ignored `.dart_tool/` and `build/` behind in any checkout that
  # had built them, so `packages/flutter3d_bridge/` and eleven more were still
  # on disk with no pubspec in them. `dart doc` documented each as an empty
  # package, and the reference went on listing packages that no longer exist.
  [ -f "$dir/pubspec.yaml" ] || continue

  printf '%-26s ' "$name"
  # Retried once, because a failure here is not always about the package.
  # `dart doc` precaches roughly 650k elements per run and one package's was
  # killed with SIGTERM part way through a full sweep, then documented cleanly on
  # its own seconds later. A reference silently missing a package is worse than a
  # slow one.
  if (cd "$dir" && dart doc --output "$out/$name" >/dev/null 2>"$out/$name.log") ||
     (cd "$dir" && dart doc --output "$out/$name" >/dev/null 2>"$out/$name.log"); then
    rm -f "$out/$name.log"
    generated+=("$name")
    echo 'ok'
  else
    # A package that cannot be documented after that is reported and skipped
    # rather than taking the whole reference down with it; the log is left to read.
    #
    # **Left outside `docs-dist/`, and so is nothing else.** The log used to stay
    # beside the trees and went out with them, so the public site served a
    # dartdoc stack trace, and the empty directory `dart doc` had already made
    # was listed by `docs-index.sh` as a package whose link answered 403.
    mkdir -p "$logs"
    mv "$out/$name.log" "$logs/$name.log"
    rm -rf "${out:?}/$name"
    echo "FAILED — see site/.docs-logs/$name.log"
  fi
done

# The landing page is its own script, so it can be changed without a
# twenty-two package dartdoc run behind it.
tool/docs-index.sh

echo
echo "${#generated[@]} packages documented -> $(cd "$repo" && realpath --relative-to=. "$out" 2>/dev/null || echo "$out")"
echo "preview: python3 -m http.server 8765 --directory $here/dist  (with docs-dist copied in as docs/)"
