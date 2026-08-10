/// `flutter_gpu` is imported in `lib/src/engine/gpu/` and nowhere else.
///
/// That is the whole boundary this engine draws, and it is one sentence on
/// purpose. Everything else in `lib/` — the renderer, the frame graph, the
/// nodes, the contributors, the scene, the assets — is written against
/// `graphics/`, so a second backend is a second directory beside `gpu/` rather
/// than an edit to any of them.
///
/// `graphics_is_backend_free_test.dart` states the rule from the other end: the
/// vocabulary may not reach a backend. This one is the complement, and it is
/// the harder half, because the renderer is where a backend import creeps back
/// in for one line and never leaves.
///
/// Deliberately a file scan. The set is small, the rule is textual, and a scan
/// says which file broke it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one directory allowed to name a graphics API.
const String _backendDir = 'lib/src/engine/gpu/';

void main() {
  test('only gpu/ imports flutter_gpu', () {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'run from the package root, where lib/ is',
    );

    final offenders = <String>[];
    var backendFiles = 0;

    for (final file in lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final reaches = file.readAsLinesSync().any((line) {
        final trimmed = line.trim();
        return (trimmed.startsWith('import ') ||
                trimmed.startsWith('export ')) &&
            trimmed.contains('flutter_gpu');
      });
      if (!reaches) continue;
      if (file.path.startsWith(_backendDir)) {
        backendFiles++;
      } else {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these reach flutter_gpu from outside $_backendDir, which is '
          'where the backend lives. Whatever they need belongs on '
          'GraphicsDevice or CommandEncoder',
    );

    // A scan that finds nothing proves nothing: if the backend directory ever
    // moves, the check above would pass by scanning an empty set.
    expect(
      backendFiles,
      greaterThan(0),
      reason: '$_backendDir names no backend at all, so this test is checking '
          'nothing — the directory moved and the rule has to move with it',
    );
  });
}
