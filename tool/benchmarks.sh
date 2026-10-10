#!/usr/bin/env bash
# The benchmarks: every test tagged `benchmark`, in every package that
# declares the tag.
#
#   tool/benchmarks.sh
#
# **Out of the ordinary run on purpose.** A test that runs longer than a
# minute is a bug in this repository unless its reason is listed, and a
# benchmark is minutes by nature — a frame at 4K, a stroke over a million
# triangles — measured rather than checked. So a package's dart_test.yaml
# skips the tag, and this lifts the skip with --run-skipped for exactly the
# tagged tests. Which packages have one is read from their dart_test.yaml
# rather than listed here, so a new benchmark is run the day its package
# declares the tag.
#
# A benchmark that holds a timing threshold for one named machine says so in
# its own body and skips itself where CI is set, since --run-skipped would
# lift a `skip:` written on the test along with the tag's.
set -uo pipefail
cd "$(dirname "$0")/.."

failed=()
for config in packages/*/dart_test.yaml apps/*/dart_test.yaml; do
  grep -q '^  benchmark:' "$config" || continue
  dir="$(dirname "$config")"
  echo ""
  echo "── benchmarks $(basename "$dir")"
  if grep -q '^  flutter_test:' "$dir/pubspec.yaml"; then
    runner=(flutter test)
  else
    runner=(dart test)
  fi
  # The tagged files by name as well as by tag: given only the tag, the
  # runner would load and compile every file in the suite to find out which
  # ones carry it.
  files=()
  while IFS= read -r file; do files+=("${file#"$dir"/}"); done < <(
    grep -rlE "@Tags\(.*'benchmark'" "$dir/test" --include='*_test.dart' | sort
  )
  [ ${#files[@]} -ne 0 ] || continue
  if ! (cd "$dir" && "${runner[@]}" --tags benchmark --run-skipped "${files[@]}"); then
    failed+=("$(basename "$dir")")
  fi
done

if [ ${#failed[@]} -ne 0 ]; then
  echo "benchmarks failed: ${failed[*]}"
  exit 1
fi
