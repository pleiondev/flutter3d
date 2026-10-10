#!/usr/bin/env bash
# Builds the reference share server the platformer's share-and-ghost test
# starts: cloud/server's tool/share_server.dart, compiled with its native
# assets into cloud/server/build/share_server.
#
#   tool/build_share_server.sh
#
# **A script rather than a step inside the test.** The server's packages carry
# native build hooks, and on a machine that has never run them the build takes
# minutes (477 s measured cold, 24 s warm). Inside the test that was minutes on
# the clock of a check that needs a second once the server is up. tool/ci.sh
# runs this before the applications' suites; the test fails, naming this
# script, when the executable is missing or older than the server's sources.
set -euo pipefail
cd "$(dirname "$0")/../cloud/server"

# Outside the pub workspace, so the repository's own `pub get` does not
# resolve it.
[ -f .dart_tool/package_config.json ] || dart pub get
dart build cli --target tool/share_server.dart --output build/share_server
