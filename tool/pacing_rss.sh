# Sourced by tool/pacing.sh and tool/soak.sh: one resident-memory sample a
# second into $1, `<seconds> <kB>` a line, counted from the first sample the
# application answers.
#
# Reads the caller's MEMORY (android, macos or none), DEVICE, PACKAGE (the
# Android application id) and APP (the application's directory, whose
# profile build is the macOS binary to read). On an Android device through
# `adb shell dumpsys meminfo <package>` (its TOTAL RSS), on macOS through
# `ps` on the application's own binary.
sample_rss() {
  local out="$1" start="" kb pid now product binary
  # The profile build's own binary, not another checkout's game, and not
  # the build's own tools while they still work inside the bundle (codesign
  # names it too, and was read as the game for the minutes the build took).
  product="$(sed -n 's/^PRODUCT_NAME *= *//p' \
    "$APP/macos/Runner/Configs/AppInfo.xcconfig" 2>/dev/null | head -1)"
  binary="$APP/build/macos/Build/Products/Profile/$product.app/Contents/MacOS/$product"
  while :; do
    kb=""
    case "$MEMORY" in
      android)
        kb="$(adb -s "$DEVICE" shell dumpsys meminfo "$PACKAGE" 2>/dev/null |
          awk '/TOTAL RSS:/ { for (i = 1; i < NF; i++) if ($i == "RSS:") { print $(i + 1); exit } }')"
        ;;
      macos)
        pid="$(pgrep -f "^$binary" | head -1)"
        [[ -n "$pid" ]] && kb="$(ps -o rss= -p "$pid" | tr -d ' ')"
        ;;
    esac
    if [[ "$kb" =~ ^[0-9]+$ ]]; then
      now="$(date +%s)"
      start="${start:-$now}"
      echo "$((now - start)) $kb" >> "$out"
    fi
    sleep 1
  done
}
