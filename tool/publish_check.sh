#!/usr/bin/env bash
# What `pub publish` would say about every package, without publishing anything.
#
#   tool/publish_check.sh
#
# Every pubspec here carries `publish_to: none` while publishing is not yet a
# decision anybody has acted on, and that line also stops `--dry-run` from
# saying anything useful. So this takes it off, asks, and puts it back — which
# is why it leaves the tree exactly as it found it and why it must never be
# extended into an actual publish.
#
# **It could not fail on the things it exists to catch, and it edited the tree
# with no way back.** `tool/ci.sh` says this step "is the only thing that
# notices a package losing its licence, its changelog, or its version
# constraint on a sibling" — and every one of those is a pub *warning*, not an
# error, so it printed a count and exited zero. Meanwhile the restore was a
# plain `cp` after the dry run with no trap: a Ctrl-C, a cancelled CI job or a
# timeout between the two left a pubspec modified in the working tree, after
# the two `git diff --exit-code` steps that would have noticed. The backups
# were fixed names in /tmp, so two runs on one machine restored each other's.
#
# Both are fixed here: `mktemp -d` and a trap that restores on any exit, and a
# warning allowlist that has to be widened deliberately rather than a count
# that means nothing.
set -uo pipefail
cd "$(dirname "$0")/.."

BACKUPS="$(mktemp -d)"

# On any exit, including a signal: put back every pubspec this touched. The
# list is built as it goes, so a run interrupted before the first copy restores
# nothing and a run interrupted halfway restores exactly what it had moved.
restore_all() {
  for saved in "$BACKUPS"/*.yaml; do
    [ -e "$saved" ] || continue
    name="$(basename "$saved" .yaml)"
    cp "$saved" "packages/$name/pubspec.yaml"
  done
  rm -rf "$BACKUPS"
}
trap restore_all EXIT INT TERM

FAILED=0

# **Warnings that are this script's own doing, and nothing else.** The dry run
# is asked about a tree with one line taken out of a pubspec, so pub notices a
# modified checked-in file; that is the edit above and not a finding. Anything
# else — a missing LICENSE, a missing CHANGELOG, a path dependency where a
# version constraint belongs — is exactly what this exists to see, and is a
# failure rather than a line of output.
#
# Widening this list is a decision. A warning nobody has read is not.
# Matched on 'modified in git' rather than on the singular sentence: pub
# pluralises, so 'checked-in file is modified' let one edited file through and
# failed on two. This warning is only ever about a dirty working tree, which is
# a developer's business — every readiness fact this step exists to catch says
# something else.
ALLOWED='modified in git'

for dir in packages/*/; do
  name="$(basename "$dir")"
  cp "$dir/pubspec.yaml" "$BACKUPS/$name.yaml"
  python3 - "$dir/pubspec.yaml" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
p.write_text(s.replace("publish_to: 'none'\n", '').replace('publish_to: none\n', ''))
PY
  out="$( (cd "$dir" && dart pub publish --dry-run 2>&1) )"
  cp "$BACKUPS/$name.yaml" "$dir/pubspec.yaml"

  if echo "$out" | grep -q 'following error'; then
    printf '%-28s ERROR\n' "$name"
    echo "$out" | grep -A 4 'following error' | sed 's/^/    /'
    FAILED=1
    continue
  fi

  unexpected="$(echo "$out" | grep '^\* ' | grep -v "$ALLOWED")"
  if [ -n "$unexpected" ]; then
    printf '%-28s WARNINGS\n' "$name"
    echo "$unexpected" | sed 's/^/    /'
    FAILED=1
    continue
  fi
  printf '%-28s ready\n' "$name"
done

exit $FAILED
