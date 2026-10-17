#!/usr/bin/env bash
# Every kind `flutter3d create plugin` writes, generated and analysed against
# this tree.
#
#     packages/flutter3d_build/tool/compile_plugin_kinds.sh <empty dir>
#
# A template is a string in a scaffolder, and a string nobody compiles stops
# compiling the day an API it names moves: the tests of `plugin_template.dart`
# hold the files around the code, and only this holds the code. Each kind is
# created under the scratch directory, resolved against the packages of this
# checkout through a `pubspec_overrides.yaml` (the templates name hosted
# versions, which an unpublished tree does not have), analysed with
# warnings fatal, and its own tests run: the unit test and the conformance
# suite a plugin made from it earns its badge with. The backend is left
# out: `plugin_template_test.dart` holds it to
# `examples/flutter3d_backend_null` file for file, and CI tests that
# example.
#
# ANALYZE replaces the analyser, which is `flutter analyze` by default, and
# TEST the test runner, `dart test` by default.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../../.." && pwd)"
scratch="${1:?usage: compile_plugin_kinds.sh <empty directory>}"
analyze="${ANALYZE:-flutter analyze --no-pub --no-fatal-infos}"
run_tests="${TEST:-dart test}"
mkdir -p "$scratch"
scratch="$(cd "$scratch" && pwd)"
if [ -n "$(ls -A "$scratch")" ]; then
  echo "$scratch is not empty" >&2
  exit 2
fi

overrides="$scratch/pubspec_overrides.yaml"
{
  echo "dependency_overrides:"
  for dir in "$repo"/packages/*/; do
    [ -f "$dir/pubspec.yaml" ] || continue
    name="$(grep -m1 '^name:' "$dir/pubspec.yaml" | awk '{print $2}')"
    echo "  $name: {path: ${dir%/}}"
  done
} > "$overrides"

kinds="$(cd "$repo/packages/flutter3d_build" &&
  dart run flutter3d_build:create --list | awk '{print $1}')"
failed=()
for kind in $kinds; do
  [ "$kind" = backend ] && continue
  name="sample_${kind//-/_}"
  target="$scratch/$name"
  (cd "$repo/packages/flutter3d_build" &&
    dart run flutter3d_build:create plugin --kind "$kind" --name "$name" \
      --target "$target" >/dev/null)
  cp "$overrides" "$target/pubspec_overrides.yaml"
  echo "== $kind"
  if ! (cd "$target" && flutter pub get >/dev/null && $analyze &&
    $run_tests); then
    failed+=("$kind")
  fi
done

if [ "${#failed[@]}" -ne 0 ]; then
  echo "kinds that do not compile or pass their tests: ${failed[*]}" >&2
  exit 1
fi
echo "every plugin kind compiles and passes its tests"
