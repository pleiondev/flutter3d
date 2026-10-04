/// The C core's own tests, built and run with the sanitisers — P9.
///
///     dart test test/c_unit_test.dart
///
/// `csrc/tests/*.c` hold the core's unit tests in C, so a test can reach
/// what the API does not show: an arena slot's generation, the allocator.
/// This builds each with every warning an error and the address and
/// undefined-behaviour sanitisers on, runs it, and fails on a failed check or
/// on anything a sanitiser reports — a use after free or an overflow in the
/// arena is caught here, not in a game.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../hook/build.dart' show coreSources;

void main() {
  final tests = Directory(
    'csrc/tests',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.c')).toList();

  test('there are C tests to run', () => expect(tests, isNotEmpty));

  // Each in both precisions: the doubles build is one a simulation can
  // choose, so it is held to the same tests rather than only compiled.
  for (final source in tests) {
    for (final precision in const <String>['f32', 'f64']) {
      final name = '${source.uri.pathSegments.last} ($precision)';
      test(name, () {
        final scratch = Directory.systemTemp.createTempSync('f3d_ctest');
        addTearDown(() => scratch.deleteSync(recursive: true));
        final binary = '${scratch.path}/test';
        final built = Process.runSync('cc', <String>[
          '-std=c11',
          // The sanitisers see as much at -O1, and the heaps of debris and
          // cloth step in seconds instead of minutes.
          '-O1',
          '-Wall',
          '-Wextra',
          '-Werror',
          '-pedantic',
          '-ffp-contract=off',
          '-fsanitize=address,undefined',
          '-fno-sanitize-recover=all',
          '-g',
          if (precision == 'f64') '-DF3D_REAL_DOUBLE',
          '-Icsrc/include',
          '-Icsrc/src',
          ...coreSources,
          source.path,
          '-o',
          binary,
        ]);
        expect(built.exitCode, 0, reason: '${built.stderr}');
        final ran = Process.runSync(binary, const <String>[]);
        expect(ran.exitCode, 0, reason: '${ran.stdout}${ran.stderr}');
        expect('${ran.stdout}', contains('checks passed'));
      });
    }
  }
}
