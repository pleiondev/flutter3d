#!/usr/bin/env bash
# Every plain Dart package, resolved and run by a Dart SDK with no Flutter.
#
#   tool/flat_dart_check.sh
#
# **What `tool/structure.dart` cannot answer, and why it is a separate script.**
# The scan reads text: it knows which packages are meant to be plain Dart and
# walks their pubspecs for a dependency that would drag the Flutter SDK in. What
# it cannot do is *resolve* anything — and resolution is where this fails in
# practice, on a machine that has `dart` and no `flutter`, several months after
# the import that caused it. A host starting `flutter3d_model_mcp` with `dart
# run` is exactly that machine.
#
# The workspace hides it. One `flutter pub get` at the root resolves all
# thirty-three packages against one lock file, using the Flutter SDK it has, so
# a plain package with a Flutter dependency resolves perfectly well here and
# nowhere else. So this copies the packages out of the workspace, drops the
# `resolution: workspace` line that ties each one to it, points the siblings at
# each other with path overrides, and asks a bare `dart pub get` — which is the
# question a container asks.
#
# It needs `dart` and must not find `flutter`: run it in CI's `setup-dart` job.
# Locally it works anyway — a Flutter SDK on the PATH is not used by `dart pub
# get` unless a pubspec asks for it, which is the whole point.
set -uo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=()

# Every package, copied without its build output. All of them rather than the
# plain ones: `flutter3d_model_core` needs `flutter3d_mesh` and
# `flutter3d_formats` beside it, and an override that points at a directory
# which is not there is a different failure with the same colour.
for package in packages/*/; do
  name="$(basename "$package")"
  mkdir -p "$WORK/packages/$name"
  # `lib`, `bin` and the pubspec are what a resolve and a `--help` need. Tests
  # and examples are not copied: they carry `flutter_test` on purpose in the
  # packages that are allowed it, and copying them would ask this check a
  # question it is not for.
  cp "$package/pubspec.yaml" "$WORK/packages/$name/pubspec.yaml"
  for directory in lib bin; do
    [ -d "$package/$directory" ] && cp -R "$package/$directory" "$WORK/packages/$name/"
  done
done

# `resolution: workspace` says "my versions come from the workspace above me",
# and there is no workspace above these copies. Dropped rather than rewritten,
# so what is left is an ordinary package the way pub.dev would see it.
python3 - "$WORK" <<'PY'
import pathlib
import sys

work = pathlib.Path(sys.argv[1])
names = sorted(p.name for p in (work / 'packages').iterdir())
for name in names:
    pubspec = work / 'packages' / name / 'pubspec.yaml'
    text = pubspec.read_text()
    text = '\n'.join(
        line for line in text.split('\n') if line.strip() != 'resolution: workspace'
    )
    # Siblings by path, so nothing reaches pub.dev for a version that is not
    # published yet — which is every one of the modeller's packages today.
    overrides = ''.join(
        f'  {other}:\n    path: ../{other}\n' for other in names if other != name
    )
    text += f'\ndependency_overrides:\n{overrides}'
    pubspec.write_text(text)
PY

while read -r name; do
  [ -n "$name" ] || continue
  echo ""
  echo "── $name"
  if ! (cd "$WORK/packages/$name" && dart pub get); then
    FAILED+=("$name: dart pub get")
    continue
  fi
  # The one that has an entry point is also asked to start. A package that
  # resolves and then cannot run is the same problem one step later.
  if [ "$name" = "flutter3d_model_mcp" ]; then
    if ! (cd "$WORK/packages/$name" && dart run flutter3d_model_mcp:model_mcp --help); then
      FAILED+=("$name: --help")
    fi
  fi
  if [ "$name" = "flutter3d_editor_mcp" ]; then
    # It takes a level and prints usage to stderr with exit 64 when given none,
    # which is a server that started far enough to refuse.
    (cd "$WORK/packages/$name" && dart run flutter3d_editor_mcp:editor_mcp)
    if [ $? -ne 64 ]; then
      FAILED+=("$name: usage")
    fi
  fi
done < <(dart run "$ROOT/tool/structure.dart" --flat-dart)

echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "every plain Dart package resolves and runs without a Flutter SDK"
  exit 0
fi
echo "failed:"
for failure in "${FAILED[@]}"; do
  echo "  $failure"
done
exit 1
