#!/usr/bin/env bash
# Builds the level editor for one desktop and packs it the way a download
# page hands it out.
#
#   tool/editor_release.sh macos   <version> <out-dir>   a .dmg
#   tool/editor_release.sh windows <version> <out-dir>   a .zip
#   tool/editor_release.sh linux   <version> <out-dir>   a .tar.gz
#   tool/editor_release.sh sums    <out-dir>             SHA256SUMS over the rest
#
# `.github/workflows/editor_release.yml` runs it on a tag, one desktop per
# runner, and the sums once the three are together. The same command builds
# the same file on a developer's machine, which is the point of it being a
# script and not a workflow's inline steps.
#
# **macOS is signed and notarised when the certificate is there, and says
# so in the name when it is not.** With `MACOS_CERTIFICATE_P12` (base64),
# `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY` ("Developer ID
# Application: …"), `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD` (an
# app-specific password) in the environment, the app is signed with the
# hardened runtime, the image is notarised and the ticket stapled. Without
# them the image is built all the same and named `-unsigned`, so nobody
# uploads it thinking it is the other one: Gatekeeper refuses it until
# `xattr -dr com.apple.quarantine` is run on the app, which the download page
# says. Windows and Linux are not signed.
set -euo pipefail
# The out-dir is the caller's, so it is resolved before the script moves to
# the repository root.
CALLER="$(pwd)"
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
absolute() {
  case "$1" in
    /*) echo "$1" ;;
    *) echo "$CALLER/$1" ;;
  esac
}
APP_DIR="$ROOT/apps/flutter3d_editor"
NAME=flutter3d-editor

usage() {
  echo "usage: tool/editor_release.sh macos|windows|linux <version> <out-dir>" >&2
  echo "       tool/editor_release.sh sums <out-dir>" >&2
  exit 2
}

# The checksums, over every archive in the directory, in the format
# `sha256sum -c` and `shasum -a 256 -c` both read.
sums() {
  local out="$1"
  (
    cd "$out"
    rm -f SHA256SUMS
    local files=()
    for file in "$NAME"-*; do
      [[ -f "$file" ]] && files+=("$file")
    done
    [[ ${#files[@]} -gt 0 ]] || { echo "nothing to sum in $out" >&2; exit 1; }
    if command -v sha256sum >/dev/null; then
      sha256sum "${files[@]}" > SHA256SUMS
    else
      shasum -a 256 "${files[@]}" > SHA256SUMS
    fi
    cat SHA256SUMS
  )
}

signing_ready() {
  [[ -n "${MACOS_CERTIFICATE_P12:-}" && -n "${MACOS_CERTIFICATE_PASSWORD:-}" &&
     -n "${MACOS_SIGNING_IDENTITY:-}" && -n "${APPLE_ID:-}" &&
     -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]
}

# A keychain of its own, made for this run and deleted after it, so the
# certificate never lands in the login keychain of whatever machine runs this.
import_certificate() {
  local work="$1"
  local keychain="$work/release.keychain-db"
  local password
  password="$(openssl rand -hex 16)"
  printenv MACOS_CERTIFICATE_P12 | base64 --decode > "$work/certificate.p12"
  # Everything here to stderr: the one line on stdout is the keychain's path,
  # which the caller reads.
  {
    security create-keychain -p "$password" "$keychain"
    security set-keychain-settings -lut 3600 "$keychain"
    security unlock-keychain -p "$password" "$keychain"
    security import "$work/certificate.p12" -k "$keychain" \
      -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "$password" \
      "$keychain"
    # Searched first, and the user's own keychains after it.
    # shellcheck disable=SC2046
    security list-keychains -d user -s "$keychain" \
      $(security list-keychains -d user | tr -d '"')
  } >&2
  rm -f "$work/certificate.p12"
  echo "$keychain"
}

macos() {
  local version="$1" out="$2"
  (cd "$APP_DIR" && flutter build macos --release)
  local app="$APP_DIR/build/macos/Build/Products/Release/editor.app"
  [[ -d "$app" ]] || { echo "no $app after the build" >&2; exit 1; }

  local work="$WORK"
  local keychain=""
  local suffix=""
  if signing_ready; then
    keychain="$(import_certificate "$work")"
    KEYCHAIN="$keychain"
    # Inside out, as Apple asks: the frameworks and their binaries first,
    # then the app with the hardened runtime and the entitlements it ships.
    find "$app/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) \
      -exec codesign --force --timestamp --options runtime \
        --keychain "$keychain" --sign "$MACOS_SIGNING_IDENTITY" {} \;
    codesign --force --timestamp --options runtime \
      --entitlements "$APP_DIR/macos/Runner/Release.entitlements" \
      --keychain "$keychain" --sign "$MACOS_SIGNING_IDENTITY" "$app"
    codesign --verify --deep --strict --verbose=2 "$app"
  else
    suffix="-unsigned"
    echo "no signing certificate in the environment: building an unsigned image" >&2
  fi

  # The image: the app and a link to /Applications to drag it onto.
  mkdir -p "$work/image" "$out"
  cp -R "$app" "$work/image/flutter3d editor.app"
  ln -s /Applications "$work/image/Applications"
  local dmg="$out/$NAME-$version-macos$suffix.dmg"
  rm -f "$dmg"
  hdiutil create -volname "flutter3d editor $version" -srcfolder "$work/image" \
    -ov -format UDZO "$dmg"

  if signing_ready; then
    codesign --force --timestamp --keychain "$keychain" \
      --sign "$MACOS_SIGNING_IDENTITY" "$dmg"
    # notarytool takes the app-specific password only as an argument; it is
    # one for this job, revocable on its own, on a runner nobody else uses.
    xcrun notarytool submit "$dmg" --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose "$dmg"
  fi
  echo "wrote $dmg"
}

windows() {
  local version="$1" out="$2"
  (cd "$APP_DIR" && flutter build windows --release)
  local release="$APP_DIR/build/windows/x64/runner/Release"
  [[ -d "$release" ]] || { echo "no $release after the build" >&2; exit 1; }
  mkdir -p "$out"
  local zip
  zip="$(cd "$out" && pwd)/$NAME-$version-windows-x64.zip"
  rm -f "$zip"
  # Git Bash on a Windows runner has 7-Zip and no `zip`; a developer's Linux
  # or macOS machine has `zip`. Either way the archive opens to one folder.
  cp -R "$release" "$WORK/$NAME-$version"
  if command -v 7z >/dev/null; then
    (cd "$WORK" && 7z a -tzip "$zip" "$NAME-$version" >/dev/null)
  else
    (cd "$WORK" && zip -qr "$zip" "$NAME-$version")
  fi
  echo "wrote $zip"
}

linux() {
  local version="$1" out="$2"
  (cd "$APP_DIR" && flutter build linux --release)
  local bundle="$APP_DIR/build/linux/x64/release/bundle"
  [[ -d "$bundle" ]] || { echo "no $bundle after the build" >&2; exit 1; }
  mkdir -p "$out"
  local tarball
  tarball="$(cd "$out" && pwd)/$NAME-$version-linux-x64.tar.gz"
  # One folder in the archive, named with the version, so two of them
  # unpacked side by side do not write over each other.
  cp -R "$bundle" "$WORK/$NAME-$version"
  tar -czf "$tarball" -C "$WORK" "$NAME-$version"
  echo "wrote $tarball"
}

WORK=""
KEYCHAIN=""
cleanup() {
  if [[ -n "$KEYCHAIN" ]]; then
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  fi
  if [[ -n "$WORK" ]]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

case "${1:-}" in
  macos | windows | linux)
    [[ $# -eq 3 ]] || usage
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/editor-release.XXXXXX")"
    "$1" "$2" "$(absolute "$3")"
    ;;
  sums)
    [[ $# -eq 2 ]] || usage
    sums "$(absolute "$2")"
    ;;
  *) usage ;;
esac
