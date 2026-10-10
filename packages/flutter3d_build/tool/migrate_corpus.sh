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
#    The Dart blocks of the site's guide pages at the tag (the quickstart,
#    the first-project page, each tutorial and any cookbook page) become a
#    project each too, `site_<page>`, built by `site_pages.py`: the code a
#    user copied from the site is migrated like the apps are.
# 3. `dart run flutter3d_build:migrate --lints-from <this repo>` on each.
# 4. `flutter analyze` on each. The line per project says how many errors are
#    left; the release needs zero. Warnings and infos (a TODO the migration
#    left, an unused import) are not counted.
#
#    A page's blocks are fragments: they name a `world` or a `device` an
#    earlier block made, so they have errors before any migration. A page
#    project is analysed first against the tag's own packages, and only the
#    errors the migration adds count; the ones it already had are listed
#    beside them.
#
# Reports land in <scratch>/reports/. Re-running needs a fresh scratch dir.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../../.." && pwd)"
scratch="${1:?usage: migrate_corpus.sh <empty scratch dir> [tag]}"
tag="${2:-v0.8.5}"
# Which projects to migrate, as a glob over their names: `site_*` for the
# pages alone. Everything by default.
only="${CORPUS_ONLY:-*}"
mkdir -p "$scratch"
if [ -n "$(ls -A "$scratch")" ]; then
  echo "$scratch is not empty" >&2
  exit 2
fi
archive="$scratch/archive"
corpus="$scratch/corpus"
reports="$scratch/reports"
mkdir -p "$archive" "$corpus" "$reports"

git -C "$repo" archive "$tag" apps packages site/content | tar -x -C "$archive"
# No trailing slash on a source: BSD cp would copy what is inside it.
for app in "$archive"/apps/*/; do
  cp -R "${app%/}" "$corpus/"
done
for example in "$archive"/packages/*/example/; do
  name="$(basename "$(dirname "$example")")_example"
  cp -R "${example%/}" "$corpus/$name"
done
python3 -I "$repo/packages/flutter3d_build/tool/site_pages.py" \
  "$archive/site/content" "$archive/packages" "$corpus"

# Each page project as the tag left it, resolved against the tag's own
# packages: the errors its fragments have before anything is migrated.
baseline="$scratch/baseline"
mkdir -p "$baseline"
{
  echo "dependency_overrides:"
  for dir in "$archive"/packages/*/; do
    [ -f "$dir/pubspec.yaml" ] || continue
    name="$(grep -m1 '^name:' "$dir/pubspec.yaml" | awk '{print $2}')"
    echo "  $name: {path: ${dir%/}}"
  done
} > "$scratch/pubspec_overrides.tag.yaml"
for page in "$corpus"/$only/; do
  name="$(basename "$page")"
  case "$name" in site_*) ;; *) continue ;; esac
  [ -d "$page" ] || continue
  cp -R "${page%/}" "$baseline/$name"
  cp "$scratch/pubspec_overrides.tag.yaml" "$baseline/$name/pubspec_overrides.yaml"
  (cd "$baseline/$name" && flutter pub get &&
    flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings) \
    > "$reports/$name.baseline.txt" 2>&1 || true
done

# An analyzer's errors without their line and column, which a migration
# moves: what stays the same error when the code around it is rewritten.
errors_of() {
  grep '^ *error ' "$1" | sed -E 's/:[0-9]+:[0-9]+ •/ •/' | sort || true
}

overrides="$scratch/pubspec_overrides.yaml"
{
  echo "dependency_overrides:"
  for dir in "$repo"/packages/*/; do
    [ -f "$dir/pubspec.yaml" ] || continue
    name="$(grep -m1 '^name:' "$dir/pubspec.yaml" | awk '{print $2}')"
    echo "  $name: {path: ${dir%/}}"
  done
} > "$overrides"

for project in "$corpus"/$only/; do
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
for project in "$corpus"/$only/; do
  name="$(basename "$project")"
  (cd "$repo/packages/flutter3d_build" &&
    dart run flutter3d_build:migrate --lints-from "$repo" "$project") \
    > "$reports/$name.migrate.txt" 2>&1 || true
  (cd "$project" && flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings) \
    > "$reports/$name.analyze.txt" 2>&1 || true
  changed="$(grep -m1 'files changed\|files would change' "$reports/$name.migrate.txt" || echo 'migrate failed')"
  if [ -f "$reports/$name.baseline.txt" ]; then
    # Only what the migration added: an error the page had at the tag is
    # the page's own, and stays in <name>.baseline.txt.
    comm -13 <(errors_of "$reports/$name.baseline.txt") \
      <(errors_of "$reports/$name.analyze.txt") > "$reports/$name.new-errors.txt"
    errors="$(wc -l < "$reports/$name.new-errors.txt" | tr -d ' ')"
    before="$(errors_of "$reports/$name.baseline.txt" | wc -l | tr -d ' ')"
    echo "$name: $errors errors the migration added ($before at $tag); $changed"
  else
    errors="$(grep -c '^ *error ' "$reports/$name.analyze.txt" || true)"
    echo "$name: $errors errors; $changed"
  fi
  total=$((total + errors))
done
echo "corpus: $total errors after migration"
[ "$total" -eq 0 ]
