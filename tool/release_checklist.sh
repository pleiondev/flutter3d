#!/usr/bin/env bash
# The last line of a release: the five pages a reader of the announcement
# lands on answer 200 from the live site, or the release is not done.
#
#   tool/release_checklist.sh
#   tool/release_checklist.sh --version 1.0.0-rc.1
#   tool/release_checklist.sh --base http://127.0.0.1:8765
#
# The index, the quickstart, the migration guide, the download page and the
# changelog: what a post links to and what somebody upgrading from 0.8 opens
# first. `.github/workflows/site.yml` runs this after it deploys a tag, so a
# deploy that left one of them behind (a page dropped from the nav, a
# `--delete` that took a directory with it) is red on the tag and not found by
# the first reader.
#
# A 200 and nothing else: a redirect is a page that moved, and the link in a
# post that points at it is the old address. `--version` also asks that the
# index name the version the tag is for, because a deploy of the wrong
# checkout serves five pages at 200 too.
#
# The site sits behind basic auth until launch; `FLUTTER3D_SITE_AUTH`
# (user:password) is handed to curl when it is set, through a file rather
# than the command line, where `ps` could read it.
set -uo pipefail

BASE="${FLUTTER3D_SITE_URL:-https://flutter3d.pleion.dev}"
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
BASE="${BASE%/}"

PAGES=(
  /
  /quickstart/
  /reference/migrating-to-1.0/
  /download/
  /changelog/
)

WORK="$(mktemp -d "${TMPDIR:-/tmp}/release-checklist.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

CURL=(curl --silent --show-error --max-time 30 --retry 2 --retry-delay 5)
if [[ -n "${FLUTTER3D_SITE_AUTH:-}" ]]; then
  printf 'user = "%s"\n' "$FLUTTER3D_SITE_AUTH" > "$WORK/auth"
  CURL+=(--config "$WORK/auth")
fi

failed=0
for page in "${PAGES[@]}"; do
  status="$("${CURL[@]}" --output "$WORK/body" --write-out '%{http_code}' \
    "$BASE$page" 2>"$WORK/error")"
  if [[ "$status" == 200 ]]; then
    echo "200  $page"
  else
    echo "${status:-000}  $page  $(head -c 200 "$WORK/error")"
    failed=1
    continue
  fi
  if [[ "$page" == / && -n "$VERSION" ]] && ! grep -qF "$VERSION" "$WORK/body"; then
    echo "     $page does not name $VERSION: is this the tag's build?"
    failed=1
  fi
done

if [[ $failed -ne 0 ]]; then
  echo "the release checklist failed on $BASE"
  exit 1
fi
echo "the five pages answer on $BASE"
