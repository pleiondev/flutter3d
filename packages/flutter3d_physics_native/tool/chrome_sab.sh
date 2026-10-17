#!/bin/sh
# Chrome with SharedArrayBuffer, for test/web_threads_test.dart.
#
# A page has SharedArrayBuffer only when served cross-origin isolated, and
# the test runner's pages are not, so this asks Chrome for it outright. The
# runner starts whatever CHROME_EXECUTABLE names, so:
#
#     CHROME_EXECUTABLE=tool/chrome_sab.sh dart test -p chrome test/web_threads_test.dart
#
# A platform defined in dart_test.yaml would say the same, but `flutter
# test` refuses a package whose dart_test.yaml names a browser.
for chrome in "$F3D_CHROME" \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "$(command -v google-chrome)" "$(command -v google-chrome-stable)" \
  "$(command -v chromium)" "$(command -v chromium-browser)"; do
  if [ -n "$chrome" ] && [ -x "$chrome" ]; then
    exec "$chrome" --enable-features=SharedArrayBuffer "$@"
  fi
done
echo "chrome_sab.sh: no Chrome found; set F3D_CHROME" >&2
exit 1
