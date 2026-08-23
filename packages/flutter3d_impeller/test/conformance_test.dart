/// This backend runs the conformance checks from a script, not from here.
///
///     tool/conformance.sh          exits non-zero on a failure
///     tool/conformance.sh --stay   leaves the list on screen
///
/// Flutter GPU needs Impeller enabled and a headless `flutter test` does not
/// provide it — the same platform fact that makes the golden suite drive an
/// application. The checks are the same list either way; only the harness
/// differs, which is why `conformanceChecks` is a list of functions rather than
/// a file of `test()` calls.
///
/// **The pointer used to be the whole content, and that was not enough.** A
/// `skip` with a sentence in it says where to look and does not make anybody
/// look, and this backend went unchecked long enough that
/// `a pipeline switch leaves no stale bindings` — added in the same commit as
/// the fix it guards — had never once been run against the backend that fix was
/// written for. It passes. So do the other eleven. Nobody knew.
///
/// So the script exists and reports with an exit code, and this file now checks
/// the one thing about it that a headless test can: that it is there, that it
/// is executable, and that it names the entry point it drives. A pointer that
/// has rotted is worse than no pointer, and every other rule in this repository
/// that reads a file is here for the same reason.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the script that runs them is there and can be run', () {
    // Mutation: rename the script. The message below is what a reader gets
    // instead of a `skip` that still cheerfully names a file nobody kept.
    final script = File('tool/conformance.sh');
    expect(script.existsSync(), isTrue,
        reason: 'tool/conformance.sh is how this backend is checked, and it is '
            'not there. See the note at the top of this file.');

    final mode = script.statSync().mode;
    expect(mode & 0x40 /* owner execute */, isNot(0),
        reason: 'tool/conformance.sh is not executable, so the one thing that '
            'runs the checks on this backend cannot be run');
  });

  test('and it drives the application that holds the checks', () {
    // The other half, and the half that rots: a script naming an entry point
    // that has moved fails at the worst moment, which for this one is "on the
    // machine with a GPU, once a month".
    final script = File('tool/conformance.sh').readAsStringSync();
    expect(script, contains('lib/conformance_main.dart'));

    final app = File('../flutter3d/example/lib/conformance_main.dart');
    expect(app.existsSync(), isTrue,
        reason: 'the script drives an entry point that is not there');

    // And that the entry point still reports in the shape the script greps
    // for. These two agreeing is the whole mechanism.
    final source = app.readAsStringSync();
    expect(source, contains('passed, '),
        reason: 'the application no longer prints the line the script reads '
            'its verdict from');
    expect(source, contains('exit('),
        reason: 'the application no longer exits with a code, so the script '
            'would wait for it for ever');
  });
}
