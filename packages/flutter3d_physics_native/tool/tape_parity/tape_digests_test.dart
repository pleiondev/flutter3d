// The tape parity on the VM and in a browser: what
// `tool/digest_platforms.sh tapes` runs on each of them and compares, for
// the parity table in doc/parity/c-core.md. See `tape_play.dart` for what is
// played and digested.
//
//     dart test tool/tape_parity/tape_digests_test.dart              (VM)
//     dart test -p chrome tool/tape_parity/tape_digests_test.dart    (dart2js)
//     dart test -p chrome -c dart2wasm tool/tape_parity/tape_digests_test.dart
//
// The script stages the tapes and their levels in `build/tape_parity/` first,
// where a browser test can fetch them; without them each test fails saying
// so.
//
// A measurement, not a suite: it lives under tool/ because it plays two
// games this package does not depend on, and passes whatever it prints; the
// script holds the targets to one another.
// ignore_for_file: avoid_print
library;

import 'package:test/test.dart';

import 'files_io.dart' if (dart.library.js_interop) 'files_web.dart';
import 'tape_play.dart';

void main() {
  // The browser fetches the module from the package root, two up from this
  // page; natively the hook's library is already there.
  setUpAll(
    () async => print(
      'parity physics ${await startCore(wasmUrl: '../../web/f3d_physics.wasm')}',
    ),
  );

  for (final name in tapes) {
    test(name, () async {
      (await playTape(name, readStaged)).forEach(print);
    });
  }
}
