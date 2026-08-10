/// `lib/src/engine/graphics/` may not import a graphics backend.
///
/// That is the entire reason the directory exists, and a rule nobody can check
/// by looking is a rule that lasts until the first hurried afternoon. One
/// `import 'package:flutter_gpu/gpu.dart'` in there and the engine's vocabulary
/// silently becomes flutter_gpu's again, with the type names unchanged so
/// nothing else looks different.
///
/// Deliberately a file scan rather than a dependency assertion: the directory
/// is small, the rule is textual, and a scan says which file broke it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing in graphics/ imports a backend', () {
    final dir = Directory('lib/src/engine/graphics');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'run from the package root, where lib/ is',
    );

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    expect(
      files,
      isNotEmpty,
      reason: 'a scan that finds nothing proves nothing',
    );

    for (final file in files) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        expect(
          trimmed.contains('flutter_gpu') || trimmed.contains('dart:ui'),
          isFalse,
          reason: '${file.path} reaches a backend: $trimmed',
        );
      }
    }
  });
}
