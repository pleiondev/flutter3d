/// `lib/src/engine/graphics/` may not import a graphics backend, and neither
/// may the resource layer of the frame graph.
///
/// That is the entire reason the directory exists, and a rule nobody can check
/// by looking is a rule that lasts until the first hurried afternoon. One
/// `import 'package:flutter_gpu/gpu.dart'` in there and the engine's vocabulary
/// silently becomes flutter_gpu's again, with the type names unchanged so
/// nothing else looks different.
///
/// `render/frame_resources.dart` is named separately because it cannot move
/// here — it belongs to the frame graph and imports it — and because it is the
/// file whose freedom from the backend is worth the most: it is what makes
/// `test/frame_resources_test.dart` possible, and that suite is the only check
/// this engine has ever had on which texture goes back to the pool and when.
/// Nothing here is enforced by the type system; a single `gpu.Texture` in a
/// signature would take the whole suite down with it, and the analyzer would
/// report only that a test no longer compiles.
///
/// Deliberately a file scan rather than a dependency assertion: the set is
/// small, the rule is textual, and a scan says which file broke it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files outside `graphics/` held to the same rule, and why each one is.
const Map<String, String> _alsoBackendFree = <String, String>{
  'lib/src/engine/render/frame_resources.dart':
      'the frame graph would stop being unit-testable off a device',
};

void _check(File file, {String? because}) {
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
      continue;
    }
    expect(
      trimmed.contains('flutter_gpu') || trimmed.contains('dart:ui'),
      isFalse,
      reason: '${file.path} reaches a backend: $trimmed'
          '${because == null ? '' : ' — $because'}',
    );
  }
}

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
      _check(file);
    }
  });

  test('nor does the frame graph resource layer', () {
    for (final entry in _alsoBackendFree.entries) {
      final file = File(entry.key);
      expect(
        file.existsSync(),
        isTrue,
        reason: '${entry.key} moved or was renamed; the rule moves with it',
      );
      _check(file, because: entry.value);
    }
  });
}
