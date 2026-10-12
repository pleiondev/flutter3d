#!/bin/bash
# The core's digests on the platforms a Mac can reach — P9, phase 13.
#
#     tool/digest_platforms.sh [linux] [android] [ios] [windows]
#
# csrc/tests/test_digest.c steps seven scenes and fails unless they hash to
# the numbers written in it; this builds it, in both precisions, for:
#
#   linux    Debian in Docker on arm64, x86-64 and 32-bit ARM, with gcc and
#            clang each (the last under emulation: minutes);
#   android  arm64 with the NDK's clang, run on the emulator or device adb
#            sees (ANDROID_HOME, or ~/Library/Android/sdk);
#   ios      the simulator, booted if none is;
#   windows  x86-64 with mingw-w64 in Docker, run under wine, with
#            test_threads.c beside it for the pool on Win32 threads (under
#            emulation: many minutes).
#
# MSVC is CI's (`physics-native-windows`), through test/c_unit_test.dart.
# With no argument, all four.
#
#     tool/digest_platforms.sh tapes [vm] [dart2js] [dart2wasm] [device:<id>]...
#
# **The tapes**, P3: the racing and shooter tapes played on the core for a
# thousand steps, the world's digest every hundred
# (tool/tape_parity/tape_play.dart), on
#
#   vm         this host's library, built by the package's hook with this
#              host's compiler: clang on macOS and Linux, MSVC on Windows;
#   dart2js    the WebAssembly core in Chrome, the game compiled to JS;
#   dart2wasm  the same, the game compiled to WebAssembly;
#   device:<id>  a phone, a simulator or a desktop `flutter devices` lists,
#              through the racing demo, which has both games.
#
# With no target after `tapes`, the first three. Each target's lines are kept
# in build/tape_parity/<target>.txt; the first target is the reference and
# every other is held to it line by line, and a difference fails. The table
# is doc/parity/c-core.md.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCES=$(sed -n '/coreSources = /,/];/p' hook/build.dart | grep -o 'csrc/src/[a-z_0-9]*\.c' | tr '\n' ' ')
FLAGS='-std=c11 -O2 -w -ffp-contract=off -fno-fast-math -Icsrc/include -Icsrc/src'
SCRATCH=$(mktemp -d)
# Where a device target's harness is copied for its run (see tape_target).
DEVICE_HARNESS=../../apps/flutter3d_demo_racing/integration_test/tape_parity
trap 'rm -rf "$SCRATCH" "$DEVICE_HARNESS"' EXIT
failed=0

# One line per build: where, which compiler and precision, and the result.
report() {
  local where=$1 result=$2
  echo "$where: $result"
  case "$result" in *"checks passed"*) ;; *) failed=1 ;; esac
}

linux() {
  local platform
  for platform in linux/arm64 linux/amd64 linux/arm/v7; do
    # Read from a process substitution, not a pipe: a loop at a pipe's end
    # runs in a subshell, and what report() sets would be lost with it.
    while IFS='|' read -r where result; do report "$where" "$result"; done < <(docker run --rm --platform "$platform" -v "$PWD:/src" -w /src debian:trixie bash -c "
      apt-get update -qq >/dev/null && apt-get install -y -qq gcc clang >/dev/null 2>&1
      for cc in gcc clang; do
        for p in '' -DF3D_REAL_DOUBLE; do
          \$cc $FLAGS -pthread \$p csrc/tests/test_digest.c $SOURCES -lm -o /tmp/digest &&
            echo \"$platform \$cc \${p:-f32}|\$(/tmp/digest 2>&1 | tail -1)\"
        done
      done")
  done
}

android() {
  local sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
  local ndk
  ndk=$(ls -d "$sdk"/ndk/*/toolchains/llvm/prebuilt/*/bin | tail -1)
  local adb=$sdk/platform-tools/adb p
  for p in '' -DF3D_REAL_DOUBLE; do
    # shellcheck disable=SC2086
    "$ndk/aarch64-linux-android26-clang" $FLAGS $p csrc/tests/test_digest.c $SOURCES -lm -o "$SCRATCH/digest"
    "$adb" push "$SCRATCH/digest" /data/local/tmp/f3d_digest >/dev/null
    report "android arm64 ${p:-f32}" "$("$adb" shell /data/local/tmp/f3d_digest 2>&1 | tail -1)"
  done
}

ios() {
  local sdk device p
  sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
  device=$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1 || true)
  if [ -z "$device" ]; then
    device=$(xcrun simctl list devices available | grep -i iphone | grep -o '[0-9A-F-]\{36\}' | head -1)
    xcrun simctl boot "$device"
    xcrun simctl bootstatus "$device" -b >/dev/null
  fi
  for p in '' -DF3D_REAL_DOUBLE; do
    # shellcheck disable=SC2086
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$sdk" \
      $FLAGS $p csrc/tests/test_digest.c $SOURCES -o "$SCRATCH/digest"
    report "ios simulator ${p:-f32}" "$(xcrun simctl spawn "$device" "$SCRATCH/digest" 2>&1 | tail -1)"
  done
}

windows() {
  while IFS='|' read -r where result; do report "$where" "$result"; done < <(docker run --rm --platform linux/amd64 -v "$PWD:/src" -w /src debian:trixie bash -c "
    apt-get update -qq >/dev/null && apt-get install -y -qq gcc-mingw-w64-x86-64 wine wine64 >/dev/null 2>&1
    export WINEDEBUG=-all
    for t in test_digest test_threads; do
      for p in '' -DF3D_REAL_DOUBLE; do
        x86_64-w64-mingw32-gcc $FLAGS -D_USE_MATH_DEFINES -static \$p csrc/tests/\$t.c $SOURCES -o /tmp/t.exe &&
          echo \"windows (wine) \$t \${p:-f32}|\$(wine /tmp/t.exe 2>&1 | tail -1)\"
      done
    done")
}

# One tape target's `parity` lines into build/tape_parity/<name>.txt.
tape_target() {
  local target=$1 harness=tool/tape_parity/tape_digests_test.dart name log
  name=${target//:/-}
  log=build/tape_parity/$name.log
  case "$target" in
    vm) dart test "$harness" -r expanded >"$log" 2>&1 || true ;;
    dart2js) dart test -p chrome "$harness" -r expanded >"$log" 2>&1 || true ;;
    dart2wasm) dart test -p chrome -c dart2wasm "$harness" -r expanded >"$log" 2>&1 || true ;;
    device:*)
      # `flutter test -d` runs a file on the device only from the
      # application's integration_test/; anywhere else it runs on this host
      # and says so in a warning. So the harness is copied in for the run
      # and taken out again.
      cp tool/tape_parity/tape_play.dart tool/tape_parity/tape_digests_device_test.dart "$DEVICE_HARNESS/"
      (cd ../../apps/flutter3d_demo_racing &&
        flutter test -d "${target#device:}" \
          integration_test/tape_parity/tape_digests_device_test.dart \
          --dart-define-from-file=../../packages/flutter3d_physics_native/build/tape_parity/defines.json) \
        >"$log" 2>&1 || true
      rm -f "$DEVICE_HARNESS"/*.dart
      ;;
    *) echo "no tape target '$target': vm, dart2js, dart2wasm or device:<id>" >&2; return 2 ;;
  esac
  # The lines alone, whatever the runner wrapped them in.
  grep -Eo 'parity (racing|shooter) (start|[0-9]+) [0-9a-f]{8}' "$log" >"build/tape_parity/$name.txt" || true
  echo "$target: $(wc -l <"build/tape_parity/$name.txt" | tr -d ' ') digests (log $log)"
}

tapes() {
  local targets=("$@") reference first status=0 target
  [ ${#targets[@]} -eq 0 ] && targets=(vm dart2js dart2wasm)
  dart run tool/tape_parity/stage.dart
  case " ${targets[*]}" in *" device:"*) mkdir -p "$DEVICE_HARNESS" ;; esac
  for target in "${targets[@]}"; do tape_target "$target" || return $?; done
  first=${targets[0]//:/-}
  reference=build/tape_parity/$first.txt
  # Two tapes, a start and ten digests each.
  if [ "$(wc -l <"$reference")" -ne 22 ]; then
    echo "${targets[0]} did not play both tapes through; see build/tape_parity/$first.log" >&2
    return 1
  fi
  for target in "${targets[@]:1}"; do
    if diff -q "$reference" "build/tape_parity/${target//:/-}.txt" >/dev/null; then
      echo "$target: every digest equals ${targets[0]}'s"
    else
      echo "$target: differs from ${targets[0]}:"
      diff "$reference" "build/tape_parity/${target//:/-}.txt" | sed -n '1,12p'
      status=1
    fi
  done
  return $status
}

if [ "${1:-}" = tapes ]; then
  shift
  tapes "$@"
  exit $?
fi

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(linux android ios windows)
for target in "${targets[@]}"; do "$target"; done
exit $failed
