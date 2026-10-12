#!/usr/bin/env bash
# The benchmarks: the frame's allocations on the software backend, and every
# other test tagged `benchmark`, in every package that declares the tag.
#
#   tool/benchmarks.sh               # both
#   tool/benchmarks.sh allocations   # the frame's allocations only
#   tool/benchmarks.sh tagged        # the other tagged tests only
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

what="${1:-all}"
case "$what" in
  all | allocations | tagged) ;;
  *)
    echo "usage: tool/benchmarks.sh [allocations|tagged]" >&2
    exit 64
    ;;
esac

# The one benchmark that is not run with the others: it counts the objects a
# warm frame allocates through the VM service, so it needs the service on.
allocations_package=packages/flutter3d
allocations_file=test/frame_allocation_benchmark_test.dart

failed=()

# **A warm frame's allocations, held to their baseline.** The draw calls are
# exact and the objects the engine and the software rasteriser allocate stay
# within the file's margin of the numbers it writes down. Without
# `--enable-vmservice` the test has no service to count with and skips
# itself, which would read as green; so its output is asked for the count it
# prints, and a run that printed none failed.
if [ "$what" != tagged ]; then
  echo ""
  echo "── benchmarks frame allocations (cpu)"
  log="$(mktemp)"
  if (cd "$allocations_package" &&
    flutter test --enable-vmservice --tags benchmark --run-skipped \
      "$allocations_file") 2>&1 | tee "$log"; then
    if ! grep -q '^per frame: ' "$log"; then
      echo "the allocation benchmark counted nothing: was the VM service on?"
      failed+=("frame allocations")
    fi
  else
    failed+=("frame allocations")
  fi
  # The counts as a file, when CI asks for one (`FLUTTER3D_BENCH_OUT`, a
  # directory): ci.yml keeps it as an artefact beside the mesh benchmark's,
  # so a count that crept up within the margin is a series and not a guess.
  if [ -n "${FLUTTER3D_BENCH_OUT:-}" ]; then
    mkdir -p "$FLUTTER3D_BENCH_OUT"
    # The `per frame:` line and the owners and classes indented under it.
    awk '/^per frame: / { on = 1; print; next } on && /^  / { print; next } on { exit }' \
      "$log" > "$FLUTTER3D_BENCH_OUT/frame-allocations.txt"
  fi
  rm -f "$log"
fi

if [ "$what" != allocations ]; then
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
    # ones carry it. The allocation benchmark is left to its own run above.
    files=()
    while IFS= read -r file; do
      [ "$dir/${file#"$dir"/}" = "$allocations_package/$allocations_file" ] &&
        continue
      files+=("${file#"$dir"/}")
    done < <(
      grep -rlE "@Tags\(.*'benchmark'" "$dir/test" --include='*_test.dart' | sort
    )
    [ ${#files[@]} -ne 0 ] || continue
    if ! (cd "$dir" && "${runner[@]}" --tags benchmark --run-skipped "${files[@]}"); then
      failed+=("$(basename "$dir")")
    fi
  done
fi

if [ ${#failed[@]} -ne 0 ]; then
  echo "benchmarks failed: ${failed[*]}"
  exit 1
fi
