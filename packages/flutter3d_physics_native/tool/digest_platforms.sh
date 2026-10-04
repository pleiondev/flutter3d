#!/bin/bash
# The core's digests on the platforms a Mac can reach — P9, phase 13.
#
#     tool/digest_platforms.sh [linux] [android] [ios]
#
# csrc/tests/test_digest.c steps seven scenes and fails unless they hash to
# the numbers written in it; this builds it, in both precisions, for:
#
#   linux    Debian in Docker on arm64, x86-64 and 32-bit ARM, with gcc and
#            clang each (the last under emulation: minutes);
#   android  arm64 with the NDK's clang, run on the emulator or device adb
#            sees (ANDROID_HOME, or ~/Library/Android/sdk);
#   ios      the simulator, booted if none is.
#
# Windows is CI's (`physics-native-windows`): MSVC, through
# test/c_unit_test.dart. With no argument, all three.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCES=$(sed -n '/coreSources = /,/];/p' hook/build.dart | grep -o 'csrc/src/[a-z_0-9]*\.c' | tr '\n' ' ')
FLAGS='-std=c11 -O2 -w -ffp-contract=off -fno-fast-math -Icsrc/include -Icsrc/src'
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
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

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(linux android ios)
for target in "${targets[@]}"; do "$target"; done
exit $failed
