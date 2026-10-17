#!/usr/bin/env bash
# Builds every application under `apps/`, each on a platform it has a
# folder for, and every one with a web folder for the web.
#
#   tool/build_apps.sh --matrix                  the cells, as GitHub's matrix
#   tool/build_apps.sh --list                    the same, for a person
#   tool/build_apps.sh <app> <target>            build one: web, macos, linux
#   tool/build_apps.sh --all <target>            every cell of one target
#
# **The list is the disk's, not this file's.** `.github/workflows/ci.yml`
# reads `--matrix` in a job of its own and builds what it prints, so an
# eighteenth application is built the day it is committed. A list kept in
# YAML was how the other jobs came to build six applications of seventeen.
#
# Which platform: the web where the application has a `web/` folder, because
# every runner can build it and it is the build a demo ships on the site;
# otherwise macOS, then Linux, for an application that only ever ran on the
# desk it was written at. An application with no platform folder at all
# cannot be built by anybody, and is listed below with the reason, or the
# matrix fails.
#
# Release, and for the web the site's flags (dart2js, the WebGPU backend
# compiled in): the demos' web builds are the ones `site/tool/demos.sh`
# deploys, so the build proved here is the build a visitor gets. The dungeon
# is built with `--wasm` as well, in `tool/ci.sh`.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# An application with no platform folder, and why it has none. Its suite
# still runs in `tool/ci.sh`. A function rather than an associative array,
# which the bash macOS ships (3.2) does not have.
exempt_reason() {
  case "$1" in
    flutter3d_lab_incident)
      echo "it has no platform folder yet, so only its suite runs (in tool/ci.sh)"
      ;;
  esac
}

# The target an application is built for, or nothing.
target_of() {
  local app="$1"
  for target in web macos linux; do
    if [[ -d "apps/$app/$target" ]]; then
      echo "$target"
      return
    fi
  done
}

runner_of() {
  case "$1" in
    web | linux) echo ubuntu-latest ;;
    macos) echo macos-latest ;;
    windows) echo windows-latest ;;
  esac
}

# Every application, sorted, as `app target` lines; exempt ones to stderr.
cells() {
  local status=0
  for dir in apps/*/; do
    local app
    app="$(basename "$dir")"
    [[ -f "$dir/pubspec.yaml" ]] || continue
    local target
    target="$(target_of "$app")"
    if [[ -n "$target" ]]; then
      echo "$app $target"
    elif [[ -n "$(exempt_reason "$app")" ]]; then
      echo "$app: not built, $(exempt_reason "$app")" >&2
    else
      echo "$app: has no platform folder and is not exempt in tool/build_apps.sh" >&2
      status=1
    fi
  done
  return $status
}

build() {
  local app="$1" target="$2"
  if [[ ! -f "apps/$app/pubspec.yaml" ]]; then
    echo "no application apps/$app" >&2
    return 2
  fi
  if [[ ! -d "apps/$app/$target" ]]; then
    echo "apps/$app has no $target folder" >&2
    return 2
  fi
  echo "── build $app ($target)"
  case "$target" in
    web)
      (cd "apps/$app" && flutter build web --release \
        --dart-define=FLUTTER3D_WEBGPU=true)
      ;;
    macos | linux | windows)
      (cd "apps/$app" && flutter build "$target" --release)
      ;;
    *)
      echo "no target called '$target'" >&2
      return 2
      ;;
  esac
}

case "${1:-}" in
  --matrix)
    lines="$(cells)" || exit 1
    first=true
    printf '{"include":['
    while read -r app target; do
      [[ -n "$app" ]] || continue
      $first || printf ','
      first=false
      printf '{"app":"%s","target":"%s","os":"%s"}' "$app" "$target" "$(runner_of "$target")"
    done <<<"$lines"
    printf ']}\n'
    ;;
  --list)
    cells | while read -r app target; do
      printf '%-36s %-6s %s\n' "$app" "$target" "$(runner_of "$target")"
    done
    ;;
  --all)
    [[ $# -eq 2 ]] || { echo "usage: tool/build_apps.sh --all <target>" >&2; exit 2; }
    lines="$(cells)" || exit 1
    failed=()
    while read -r app target; do
      [[ "$target" == "$2" ]] || continue
      build "$app" "$target" || failed+=("$app")
    done <<<"$lines"
    if [[ ${#failed[@]} -ne 0 ]]; then
      echo "failed: ${failed[*]}"
      exit 1
    fi
    ;;
  -* | "")
    echo "usage: tool/build_apps.sh --matrix | --list | --all <target> | <app> <target>" >&2
    exit 2
    ;;
  *)
    [[ $# -eq 2 ]] || { echo "usage: tool/build_apps.sh <app> <target>" >&2; exit 2; }
    build "$1" "$2"
    ;;
esac
