/// `window_id.swift`'s own pure-logic self-test, run through `dart test` so
/// it is part of this package's own suite rather than a step somebody has
/// to remember to run by hand.
///
/// `window_id.swift` is a standalone script, not a Dart file — nothing here
/// can call `bestWindowNumber` directly, so this shells out to
/// `swift window_id.swift --self-test`, which exercises that same function
/// against synthetic window lists and exits non-zero on the first
/// assertion that fails. See `window_id.swift`'s own header for what
/// `--self-test` covers and why nothing here can fake a real window list
/// through `CGWindowListCopyWindowInfo`.
///
/// Skipped outside macOS, and when no `swift` binary is on `PATH` — the
/// shape every other machine-specific check in this repository already
/// uses (`flutter3d_impeller`'s own conditional runners, for one); Linux CI
/// runs the rest of this package's suite regardless.
///
///     dart test tool/tutorial/test/window_id_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final hasSwift =
      Platform.isMacOS &&
      Process.runSync('which', const <String>['swift']).exitCode == 0;

  test('the pure matching rule passes its own synthetic-window assertions', () {
    // Relative to this package's own root — where `dart test` runs from
    // in this repository (`tool/ci.sh`'s `in_dir` cds there first), and
    // where `window_id.swift` sits beside `lib/`, `bin/` and `test/`.
    final result = Process.runSync('swift', const <String>[
      'window_id.swift',
      '--self-test',
    ]);
    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
    expect(result.stdout, contains('ok'));
  }, skip: hasSwift ? false : 'needs a macOS machine with swift on PATH');
}
