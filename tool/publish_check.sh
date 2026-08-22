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
set -uo pipefail
cd "$(dirname "$0")/.."

FAILED=0

for dir in packages/*/; do
  name="$(basename "$dir")"
  cp "$dir/pubspec.yaml" "/tmp/publish_check_$name.yaml"
  python3 - "$dir/pubspec.yaml" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
p.write_text(s.replace("publish_to: 'none'\n", '').replace('publish_to: none\n', ''))
PY
  out="$( (cd "$dir" && dart pub publish --dry-run 2>&1) )"
  cp "/tmp/publish_check_$name.yaml" "$dir/pubspec.yaml"

  if echo "$out" | grep -q 'following error'; then
    printf '%-28s ERROR\n' "$name"
    echo "$out" | grep -A 4 'following error' | sed 's/^/    /'
    FAILED=1
    continue
  fi
  # The dirty-git warning is about the line this script itself just moved.
  warnings="$(echo "$out" | grep -c '^\* ')"
  printf '%-28s %s\n' "$name" "$([ "$warnings" -le 1 ] && echo 'ready' || echo "$warnings warnings")"
  echo "$out" | grep '^\* ' | grep -v 'checked-in file is modified' | sed 's/^/    /'
done

exit $FAILED
