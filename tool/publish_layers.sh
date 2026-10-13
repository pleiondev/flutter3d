#!/usr/bin/env bash
# Publish the packages layer by layer, and wait for each layer on pub.dev
# before the next one.
#
#   tool/publish_layers.sh                     # dry run: every layer, nothing uploaded
#   tool/publish_layers.sh --from 3 --to 5     # dry run of L3 to L5
#   tool/publish_layers.sh --publish --from 0  # the real thing, from L0
#
# **The order is ARCHITECTURE.md's**, the numbered list after "The order, used
# on the day", which the structure rule `the publishing order names every
# package` derives from the pubspecs and holds. This reads that list and
# nothing else, so the script and the rule cannot disagree about a layer.
#
# **Why it waits.** A package resolves its siblings against pub.dev when it is
# uploaded, so L4 cannot go up until pub.dev answers for everything in L3.
# After a layer is uploaded this asks `https://pub.dev/api/packages/<p>` for
# each package until its version list holds the version the pubspec says. The
# API lists pre-releases too; `latest` stays on 0.8.x, so it is the list that
# is read, not `latest`.
#
# **A dry run by default.** Without `--publish` it uploads nothing. It prints
# each layer, each package's version here and whether pub.dev already has it,
# and the command it would run. `--check` adds `flutter pub publish --dry-run`
# for each package that is not up yet, which is what `tool/publish_check.sh`
# does for all of them at once.
#
# **It can be run again after a failure.** A package whose version pub.dev
# already lists is skipped, so after a fix the same command carries on where
# it stopped. When an upload fails it stops before the next layer and prints
# plan B (`tasks/1.0-publish.md`, "Plan B: when a package goes up broken").
#
# Publishing needs `flutter pub login` done first. Nothing here pushes or tags.
set -uo pipefail
cd "$(dirname "$0")/.."

PUBLISH=0
CHECK=0
FROM=0
TO=99
TIMEOUT="${PUBLISH_WAIT_SECONDS:-1200}"
POLL="${PUBLISH_POLL_SECONDS:-20}"

while [ $# -gt 0 ]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --check) CHECK=1 ;;
    --from) FROM="${2#L}"; shift ;;
    --to) TO="${2#L}"; shift ;;
    --layer) FROM="${2#L}"; TO="${2#L}"; shift ;;
    -h|--help)
      sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "publish_layers: unknown argument $1 (see --help)" >&2
      exit 2
      ;;
  esac
  shift
done

# "L<n> pkg pkg ..." per line, read from the numbered list. Continuation lines
# belong to the step above them; the list ends at the first blank line. Step
# <n> is layer L<n-1>; the step of the packages that are never published is
# left out.
LAYERS="$(awk '
  /\*\*The order, used on the day\*\*/ { inside = 1; next }
  !inside { next }
  /^[[:space:]]*[0-9]+\./ { listing = 1 }
  listing && /^[[:space:]]*$/ { exit }
  !listing { next }
  {
    if (match($0, /^[[:space:]]*[0-9]+\./)) {
      if (layer != "") print layer line
      line = ""
      if ($0 ~ /Not published/) { layer = ""; next }
      step = substr($0, RSTART, RLENGTH)
      gsub(/[^0-9]/, "", step)
      layer = "L" (step - 1)
    }
    if (layer == "") next
    rest = $0
    while (match(rest, /`[a-z0-9_]+`/)) {
      line = line " " substr(rest, RSTART + 1, RLENGTH - 2)
      rest = substr(rest, RSTART + RLENGTH)
    }
  }
  END { if (layer != "") print layer line }
' ARCHITECTURE.md)"

if [ -z "$LAYERS" ]; then
  echo "publish_layers: ARCHITECTURE.md has no publishing order to read" >&2
  exit 1
fi

package_dir() {
  for dir in packages/*/; do
    [ -f "$dir/pubspec.yaml" ] || continue
    if [ "$(awk '/^name:/ { print $2; exit }' "$dir/pubspec.yaml")" = "$1" ]; then
      echo "${dir%/}"
      return 0
    fi
  done
  return 1
}

local_version() {
  awk '/^version:/ { print $2; exit }' "$1/pubspec.yaml"
}

# 0 when pub.dev lists this exact version of the package.
on_pub() {
  curl -sf --max-time 15 "https://pub.dev/api/packages/$1" 2>/dev/null |
    grep -Fq "\"version\":\"$2\""
}

plan_b() {
  cat <<EOF

Stopped at $1. Nothing after it was uploaded.

Plan B (tasks/1.0-publish.md, "Plan B: when a package goes up broken"):
  - If the upload itself failed, fix it and run this again with --from ${2}:
    what pub.dev already has is skipped.
  - If a version went up broken, do not retract it on the day. Publish the
    same version with build metadata, $3+1, with the fix and a CHANGELOG
    line. Siblings asking for ^1.0.0-rc.1 take it on their next resolve.
  - Retract (within 7 days) only a version that does harm when resolved.
EOF
}

if [ "$PUBLISH" = 1 ]; then
  echo "Publishing for real, layers L$FROM to L$TO."
else
  echo "Dry run, layers L$FROM to L$TO: nothing is uploaded. --publish uploads."
fi

FAILED=0
while read -r layer names; do
  n="${layer#L}"
  [ "$n" -ge "$FROM" ] && [ "$n" -le "$TO" ] || continue
  echo
  echo "== $layer"
  uploaded=""
  for name in $names; do
    dir="$(package_dir "$name")" || {
      echo "  $name: no such package under packages/" >&2
      FAILED=1
      continue
    }
    version="$(local_version "$dir")"
    if on_pub "$name" "$version"; then
      printf '  %-30s %-12s already on pub.dev, skipped\n' "$name" "$version"
      continue
    fi
    if [ "$PUBLISH" = 0 ]; then
      printf '  %-30s %-12s would run: (cd %s && flutter pub publish --force)\n' \
        "$name" "$version" "$dir"
      if [ "$CHECK" = 1 ]; then
        if ! out="$(cd "$dir" && flutter pub publish --dry-run 2>&1)"; then
          printf '  %-30s %-12s the dry run of pub publish fails:\n' "$name" "$version"
          echo "$out" | sed -n '/^Package validation/,$p' | sed 's/^/      /'
          FAILED=1
        fi
      fi
      continue
    fi
    printf '  %-30s %-12s uploading\n' "$name" "$version"
    # A version uploaded by a run that stopped before pub.dev listed it is
    # refused as existing; it is up, and this waits for it like the rest.
    if ! out="$(cd "$dir" && flutter pub publish --force 2>&1)"; then
      echo "$out"
      if ! echo "$out" | grep -Fq "Version $version of package $name already exists"; then
        plan_b "$name $version" "$n" "$version"
        exit 1
      fi
    else
      echo "$out"
    fi
    uploaded="$uploaded $name=$version"
  done

  [ "$PUBLISH" = 1 ] || continue
  [ -n "$uploaded" ] || continue

  # The layer is up when pub.dev lists every version just uploaded.
  echo "  waiting for pub.dev to list$uploaded"
  waited=0
  for pair in $uploaded; do
    name="${pair%%=*}"
    version="${pair#*=}"
    until on_pub "$name" "$version"; do
      if [ "$waited" -ge "$TIMEOUT" ]; then
        echo "  $name $version is still not listed after ${TIMEOUT}s." >&2
        plan_b "$layer (waiting for $name)" "$n" "$version"
        exit 1
      fi
      sleep "$POLL"
      waited=$((waited + POLL))
    done
    printf '  %-30s %-12s listed\n' "$name" "$version"
  done
done <<EOF
$LAYERS
EOF

exit "$FAILED"
