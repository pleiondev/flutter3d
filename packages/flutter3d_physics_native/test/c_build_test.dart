/// The core's kept C build is built afresh when the compiler changes.
///
///     ft test test/c_build_test.dart
///
/// `c_build.dart` keeps the core's objects between runs so the C tests do
/// not compile the same sources again. A kept object stands for one
/// compiler's build of those bytes: one the toolchain was updated past would
/// hold the C tests, and the sanitisers' runtime they link, to a compiler
/// that is no longer the one on the machine. So the compiler's own word for
/// what it is, `--version`, is part of the key, and the same path with a new
/// version builds again.
///
/// Mutation: leave the version out of the key, and the updated compiler is
/// handed the old compiler's objects.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'c_build.dart';

void main() {
  test(
    'the same compiler finds its kept build, an updated one builds again',
    () async {
      final scratch = Directory.systemTemp.createTempSync('f3d_c_build');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final version = File('${scratch.path}/version')
        ..writeAsStringSync('cc 1\n');
      // The machine's cc, under a path of its own and saying the version
      // the file holds: an update of the compiler with nothing else moved.
      final compiler = '${scratch.path}/cc';
      File(compiler).writeAsStringSync(
        '#!/bin/sh\n'
        'if [ "\$1" = "--version" ]; then cat "${version.path}"; exit 0; fi\n'
        'exec cc "\$@"\n',
      );
      expect(Process.runSync('chmod', <String>['+x', compiler]).exitCode, 0);
      const flags = <String>['-std=c11', '-O0'];
      void forget(List<String> objects) => addTearDown(() {
        final kept = File(objects.first).parent;
        if (kept.existsSync()) kept.deleteSync(recursive: true);
      });

      final first = await coreObjects(compiler, flags);
      forget(first);
      expect(await coreObjects(compiler, flags), first);

      version.writeAsStringSync('cc 2\n');
      final updated = await coreObjects(compiler, flags);
      forget(updated);
      expect(updated, isNot(first));
      expect(updated.every((o) => File(o).existsSync()), isTrue);
    },
  );
}
