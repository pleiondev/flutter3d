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
#   * The performance budgets in ARCHITECTURE.md §14. There is no profiler yet
#     and no stored baseline to compare against.
#   * The Android and iOS builds. Both are configured and neither is compiled
#     here: a toolchain and an SDK image apiece, for platforms nothing has yet
#     been played on. The web build below is compiled, because that is a
#     platform the demos are published to.
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

# **First, because it is the only step that needs nothing.** Every rule in it
# reads source text: no `pub get`, no shader bundle, no device, under a second.
# Finding out that a package imports a genre after four minutes of building is
# finding out late what could have been known before anything started.
#
# It replaced twenty-three test files and two `grep` steps that used to be
# here. See tool/structure.dart for why they moved.
step "structure" dart run tool/structure.dart

# **`ARCHITECTURE.md` §13 has claimed `dart format` as this repository's style
# since before there was a check for it, and 637 of 874 files did not match.**
# Not through neglect: Dart 3.7 changed the formatter, and a repository nobody
# reformats simply stays in the old shape while every document says otherwise.
#
# --output=none, so this reports and changes nothing; the fix is `dart format .`
# and it is one commit. Second in the order for the same reason the structure
# scan is first: it needs no packages resolved and finishes in under two
# seconds.
step "format" dart format --output=none --set-exit-if-changed packages apps tool

step "pub get" flutter pub get

# The shader bundle is gitignored and its format is tied to the SDK version, so
# a fresh checkout has none. A test asserts it was built — deliberately a
# failure rather than a skip, because "CI built only one bundle" is one of the
# traps that test exists to catch.
step "shaders" in_dir packages/flutter3d_impeller ./tool/build_shaders.sh

# The generators reproduce what is committed, or the committed thing is not
# the thing the generator makes any more. Same rule as the levels and the
# tracks — this one covers the four applications' icons.
#
# A script rather than `make_icons.py && git diff`, because that shape was wrong
# twice: its pathspecs named directories with a `*` in them, which in git
# matches the directory and nothing inside it, so it compared three files out of
# forty-three; and it compared bytes, which Pillow's per-platform LANCZOS does
# not reproduce across operating systems. See tool/check_icons.py.
step "icons" python3 tool/check_icons.py

# The models a template gives a new game. Regenerated and compared for the
# same reason the icons are — and for one more: `math.sin` is libm, so a
# generator that did not quantise its coordinates produces different bytes on a
# different machine, and this is the step that would say so.
step "models" bash -c 'python3 tool/make_models.py >/dev/null && python3 tool/make_templates.py >/dev/null && git diff --exit-code -- "apps/flutter3d_editor/assets/templates" "apps/flutter3d_demo_dungeon/assets/models"'

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
  # Matched on the files rather than on the directory, for the reason the
  # example loop below already gives: an empty `test/` makes `flutter test`
  # exit non-zero rather than skip. Two packages lost their only test when the
  # structure rules moved out of them and turned this loop red for having
  # nothing to run.
  compgen -G "$package/test/*_test.dart" > /dev/null || continue
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

# **The same trap, one package over.** `pointer_lock` grew a web backend — the
# browser has had `requestPointerLock` all along and this package was answering
# "unsupported" for it — and its tests are `@TestOn('browser')` for the reason
# the WebGL ones are: `dart:js_interop` is not a library the VM has. The loop
# above skips them and reports the package green off its platform-agnostic
# files.
step "test pointer_lock (browser)" in_dir packages/pointer_lock flutter test --platform chrome

# **The simulation is platform-agnostic Dart, and that is exactly why it needed
# a second platform.** Both packages ran only on the VM, where an `int` is 64
# bits — and the web, where it is a double with 32-bit bitwise operations, is a
# supported target. Three places packed two numbers into one integer with a
# shift past bit 31: the collision world's pair key, the broadphase's cell key
# and the entity handle. On the VM all three were right. In a browser the first
# dropped a collision pair whenever two colliders stood in one trigger, the
# second collapsed every cell of a Z row into one bucket, and the third aliased
# an entity handle after 256 recycles of its index. None of it was reachable
# from a test nobody ran on the platform it broke on.
#
# Chrome rather than the VM only — the VM run above stays, because these are the
# packages whose failures need thousands of steps in a loop and the browser is
# the slower place to do that.
step "test flutter3d_physics (browser)" in_dir packages/flutter3d_physics dart test -p chrome
step "test flutter3d_game (browser)" in_dir packages/flutter3d_game flutter test --platform chrome

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
  compgen -G "$app/test/*_test.dart" > /dev/null || continue
  step "test $(basename "$app")" in_dir "$app" flutter test
done

# **A build nobody runs is a platform nobody supports.** Everything above tests
# the web backend and nothing above compiles a game for the web, so the one
# thing that breaks a browser build outright — a dependency that reaches for
# `dart:io`, an asset path that only exists on a developer's machine — was
# invisible here until somebody deployed.
#
# --wasm, because that is the compiler with something to say: it rejects
# `dart:html` and the legacy interop libraries outright, so this step is also
# what keeps the whole dependency tree on `package:web`. It builds the
# JavaScript output alongside, and `flutter_bootstrap.js` picks between them, so
# nothing is lost by asking for it.
#
# One of the three games and not all three: they differ in their level and their
# genre package, not in how they reach the browser, and three builds is three
# times the minutes for the same answer.
step "build web (wasm)" in_dir apps/flutter3d_demo_dungeon \
  flutter build web --wasm --release

echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "all green"
  exit 0
fi
echo "failed: ${FAILED[*]}"
exit 1
