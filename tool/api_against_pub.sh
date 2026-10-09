#!/usr/bin/env bash
# Every published package's API against the version pub.dev has, before it
# goes out.
#
#   tool/api_against_pub.sh                 # every published package
#   tool/api_against_pub.sh flutter3d_core  # one
#
# **The second of the two checks `tasks/1.0-stability.md` decision 3 asks
# for.** The first is `api/<package>.api` and its structure rules, which
# compare the source with the snapshot this repository committed at its last
# release tag. This one compares with what was actually published, through
# a tool that resolves types rather than reading text: `dart_apitool` knows
# that a parameter typed `num` widening to `Object` broke nobody, and that a
# class changing its supertype did. Where they disagree, one of them is wrong,
# and a release is the wrong moment to find out which. So this runs as the
# last step of `tool/publish_check.sh`.
#
# **It skips, saying so, when it cannot ask.** `dart-apitool` is not a
# dependency of this repository and nothing here installs global tools; and
# pub.dev may be out of reach. In either case it prints why, compares nothing,
# and exits 0 — a check that cannot run is not a check that failed. To have
# it run:
#
#   dart pub global activate dart_apitool
#
# **What it hands the tool.** A copy of the package with `resolution:
# workspace` taken out and a `pubspec_overrides.yaml` pointing every sibling
# it names at this checkout, because the copy resolves outside the workspace
# and the siblings' new versions are not on pub.dev yet either. The original
# package is not touched.
set -uo pipefail
cd "$(dirname "$0")/.."

if ! command -v dart-apitool >/dev/null 2>&1; then
  echo "api against pub.dev: skipped, dart-apitool is not installed."
  echo "  Install it with \`dart pub global activate dart_apitool\` to compare"
  echo "  each package with its published version. Nothing was compared."
  exit 0
fi

if ! curl -sf --max-time 5 -o /dev/null https://pub.dev/api/packages/flutter3d; then
  echo "api against pub.dev: skipped, pub.dev is not reachable. Nothing was compared."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Every package of this repository, "name directory" per line, so a copy can
# be pointed at its siblings. A file rather than an associative array: the
# bash macOS ships is 3.2, which has none.
LIST="$WORK/packages.txt"
for dir in packages/*/; do
  [ -f "$dir/pubspec.yaml" ] || continue
  name="$(awk '/^name:/ { print $2; exit }' "$dir/pubspec.yaml")"
  echo "$name $PWD/${dir%/}" >> "$LIST"
done

FAILED=0
while read -r name dir <&3; do
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$name"; then
    continue
  fi
  if grep -Eq "^publish_to:[[:space:]]*['\"]?none" "$dir/pubspec.yaml"; then
    continue
  fi

  status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "https://pub.dev/api/packages/$name")"
  if [ "$status" = 404 ]; then
    printf '%-28s not on pub.dev yet, nothing to compare\n' "$name"
    continue
  fi
  if [ "$status" != 200 ]; then
    printf '%-28s skipped, pub.dev answered %s\n' "$name" "$status"
    continue
  fi

  copy="$WORK/$name"
  mkdir -p "$copy"
  (cd "$dir" && tar --exclude=.dart_tool --exclude=build -cf - .) | (cd "$copy" && tar -xf -)
  grep -v '^resolution: workspace' "$dir/pubspec.yaml" > "$copy/pubspec.yaml"
  # A package inside the package (an `example/`) is a workspace member too and
  # would look for a workspace root the copy does not have. The API is lib/'s,
  # so those go.
  find "$copy" -mindepth 2 -name pubspec.yaml -exec dirname {} \; |
    while read -r nested; do rm -rf "$nested"; done
  {
    echo "dependency_overrides:"
    # Every sibling, not only the ones this package names: a sibling's own
    # siblings resolve here too, and their new versions are not on pub.dev
    # either. An override nothing depends on is ignored.
    while read -r sibling home; do
      [ "$sibling" = "$name" ] && continue
      echo "  $sibling:"
      echo "    path: $home"
    done < "$LIST"
  } > "$copy/pubspec_overrides.yaml"

  # `fully`: a break needs a major, an addition a minor, as pub.dev's latest
  # version and the pubspec's say.
  out="$(dart-apitool diff --old "pub://$name" --new "$copy" \
    --version-check-mode=fully 2>&1)"
  if [ $? -ne 0 ]; then
    printf '%-28s FAILED\n' "$name"
    echo "$out" | sed 's/^/    /'
    FAILED=1
  else
    printf '%-28s agrees with its version\n' "$name"
  fi
done 3< "$LIST"

exit $FAILED
