#!/usr/bin/env bash
# The proof that the 0.8 -> 1.0 migration works: the apps and examples of the
# last 0.8 release, migrated by `migrate` and analysed against this tree.
#
#   packages/flutter3d_build/tool/migrate_corpus.sh <empty scratch dir> [tag]
#
# 1. `git archive <tag>` (v0.8.5 by default) into the scratch dir: nothing in
#    the working tree changes.
# 2. Each app under apps/ and each package's example/ becomes a project of its
#    own: out of the workspace, with a `pubspec_overrides.yaml` pointing every
#    flutter3d package at this tree, and its path dependencies on flutter3d
#    packages turned into `^0.8.0`, the way a project on pub.dev declares them.
# 3. `dart run flutter3d_build:migrate --lints-from <this repo>` on each.
# 4. `flutter analyze` on each. The line per project says how many errors are
#    left; the release needs zero. Warnings and infos (a TODO the migration
#    left, an unused import) are not counted.
#
# Reports land in <scratch>/reports/. Re-running needs a fresh scratch dir.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../../.." && pwd)"
scratch="${1:?usage: migrate_corpus.sh <empty scratch dir> [tag]}"
tag="${2:-v0.8.5}"
mkdir -p "$scratch"
if [ -n "$(ls -A "$scratch")" ]; then
  echo "$scratch is not empty" >&2
  exit 2
fi
archive="$scratch/archive"
corpus="$scratch/corpus"
reports="$scratch/reports"
mkdir -p "$archive" "$corpus" "$reports"

git -C "$repo" archive "$tag" apps packages | tar -x -C "$archive"
# No trailing slash on a source: BSD cp would copy what is inside it.
for app in "$archive"/apps/*/; do
  cp -R "${app%/}" "$corpus/"
done
for example in "$archive"/packages/*/example/; do
  name="$(basename "$(dirname "$example")")_example"
  cp -R "${example%/}" "$corpus/$name"
done

overrides="$scratch/pubspec_overrides.yaml"
{
  echo "dependency_overrides:"
  for dir in "$repo"/packages/*/; do
    [ -f "$dir/pubspec.yaml" ] || continue
    name="$(grep -m1 '^name:' "$dir/pubspec.yaml" | awk '{print $2}')"
    echo "  $name: {path: ${dir%/}}"
  done
} > "$overrides"

for project in "$corpus"/*/; do
  cp "$overrides" "$project/pubspec_overrides.yaml"
  python3 -I - "$project/pubspec.yaml" <<'PY'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = re.sub(r'^resolution: workspace\n', '', text, flags=re.M)
owned = re.compile(r'^(flutter3d.*|flame_flutter3d.*|flame_multiplayer.*|pad_input|pointer_lock)$')
def plain(m):
    return f"{m.group(1)}{m.group(2)}: ^0.8.0\n" if owned.match(m.group(2)) else m.group(0)
text = re.sub(r'^(\s+)([a-z0-9_]+):\s*\n\s+path:[^\n]*\n', plain, text, flags=re.M)
path.write_text(text)
PY
done

total=0
for project in "$corpus"/*/; do
  name="$(basename "$project")"
  (cd "$repo/packages/flutter3d_build" &&
    dart run flutter3d_build:migrate --lints-from "$repo" "$project") \
    > "$reports/$name.migrate.txt" 2>&1 || true
  (cd "$project" && flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings) \
    > "$reports/$name.analyze.txt" 2>&1 || true
  errors="$(grep -c '^ *error ' "$reports/$name.analyze.txt" || true)"
  total=$((total + errors))
  echo "$name: $errors errors; $(grep -m1 'files changed\|files would change' "$reports/$name.migrate.txt" || echo 'migrate failed')"
done
echo "corpus: $total errors after migration"
[ "$total" -eq 0 ]
