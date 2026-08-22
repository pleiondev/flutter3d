#!/usr/bin/env bash
# Everything a machine can check, in the order that fails fastest.
#
# One script rather than a list of steps in a workflow file, so that what CI
# runs and what you can run are the same thing. A workflow that drifts from
# what a developer can reproduce is a workflow whose failures nobody can fix.
#
#   tool/ci.sh
#
# What it does NOT do, stated so the gap is not mistaken for coverage:
#
#   * The Impeller half of the golden set. Those thirty scenes render through
#     flutter_gpu and need a real device, so they run from
#     packages/flutter3d/tool/golden.sh on a machine with a GPU. The software
#     half runs here, and cross_backend_test.dart compares the two committed
#     reference sets with no device at all — which is the question that
#     actually matters.
#   * The performance budgets in docs/SPEC.md §5.1. There is no profiler yet
#     and no stored baseline to compare against.
set -uo pipefail
cd "$(dirname "$0")/.."

FAILED=()
step() {
  local name="$1"; shift
  echo ""
  echo "── $name"
  if ! "$@"; then
    FAILED+=("$name")
  fi
}

in_dir() {
  local dir="$1"; shift
  ( cd "$dir" && "$@" )
}

step "pub get" flutter pub get

# The shader bundle is gitignored and its format is tied to the SDK version, so
# a fresh checkout has none. A test asserts it was built — deliberately a
# failure rather than a skip, because "CI built only one bundle" is one of the
# traps that test exists to catch.
step "shaders" in_dir packages/flutter3d_impeller ./tool/build_shaders.sh

# The generators reproduce what is committed, or the committed thing is not
# the thing the generator makes any more. Same rule as the levels and the
# tracks — this one covers the four applications' icons.
step "icons" bash -c 'python3 tool/make_icons.py >/dev/null && git diff --exit-code -- "apps/*/macos/Runner/Assets.xcassets" "apps/*/web/icons" "apps/*/web/favicon.png"'

# The models a template gives a new game. Regenerated and compared for the
# same reason the icons are — and for one more: `math.sin` is libm, so a
# generator that did not quantise its coordinates produces different bytes on a
# different machine, and this is the step that would say so.
step "models" bash -c 'python3 tool/make_models.py >/dev/null && python3 tool/make_templates.py >/dev/null && git diff --exit-code -- "apps/editor/assets/templates" "apps/dungeon/assets/models"'

# **The WebGL table is generated and nothing checked that it was current.** Its
# own header says so — "there is no check that this file is current" — and when
# somebody finally regenerated it, it turned out to be holding a sky shader from
# before the sky was rewritten: the browser was drawing a different sky from
# Impeller and no test could see it. Same shape as the icons and the models.
step "webgl shaders" bash -c 'cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart >/dev/null && git diff --exit-code -- lib/engine_shaders.dart'

step "analyze" flutter analyze

# What `pub publish` would say about each package, without publishing anything.
# Twenty-six seconds, and it is the only thing that notices a package losing its
# licence, its changelog, or its version constraint on a sibling — none of which
# an analyser or a test can see, and all of which are found at the worst
# possible moment otherwise.
step "publish check" bash tool/publish_check.sh

for package in packages/*/; do
  name="$(basename "$package")"
  [ -d "$package/test" ] || continue
  # Plain Dart, and it is the point of that package that it needs no Flutter.
  if [ "$name" = "flutter3d_physics" ]; then
    step "test $name" in_dir "$package" dart test
  else
    step "test $name" in_dir "$package" flutter test
  fi
done

# **Five test files that nothing had ever run.** `flutter3d_webgl` marks them
# `@TestOn('browser')` — the conformance suite, the parity comparison against
# Impeller, a whole engine frame — so the loop above skips every one of them and
# reports the package green off its one platform-agnostic file. The first run of
# this step failed: the conformance table still paired the sky's cube fragment
# with a vertex stage it stopped sharing, which a browser refuses to link and
# which nothing else in the repository can see.
#
# Chrome, because that is what `flutter test --platform chrome` drives. A
# machine without it fails this step rather than skipping it, for the reason the
# shader bundle does.
step "test flutter3d_webgl (browser)" in_dir packages/flutter3d_webgl flutter test --platform chrome

# An example with tests, which until `packages/pad_input/example` there was none of.
# Its tests are the only ones that mount the tool the gamepad's manual acceptance
# is walked with, and a test CI never runs is a test that rots.
for example in packages/*/example/; do
  # Matched on the files rather than on the directory: an empty `test/` makes
  # `flutter test` exit non-zero rather than skip, and there is one of those in
  # the tree already.
  compgen -G "$example/test/*_test.dart" > /dev/null || continue
  step "test $(basename "$(dirname "$example")") example" in_dir "$example" flutter test
done

for app in apps/*/; do
  [ -d "$app/test" ] || continue
  step "test $(basename "$app")" in_dir "$app" flutter test
done

echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "all green"
  exit 0
fi
echo "failed: ${FAILED[*]}"
exit 1
