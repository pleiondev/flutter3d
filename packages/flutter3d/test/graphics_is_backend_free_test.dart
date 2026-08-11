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

/// Files inside `graphics/` allowed to name `dart:ui`, and why.
///
/// The `flutter_gpu` half of the rule has no exceptions and never will — that
/// is the whole reason the directory exists. The `dart:ui` half is narrower
/// than it first looked: it is there to stop Flutter's vocabulary leaking into
/// the engine's, and `PixelFormat` is the collision it was written for, already
/// handled by naming ours [TextureFormat].
///
/// Handing back a finished frame is different. Every backend has to answer it,
/// so a device that could not would not be a usable device. It sat on a second
/// interface in `render/` for one release to preserve the blanket ban, and that
/// cost more than it saved: it made the backend depend on the engine, so
/// implementing a device meant importing the scene graph.
const Map<String, String> _mayUseDartUi = <String, String>{
  'graphics_device.dart':
      'GraphicsDevice.imageOf returns the finished frame, which every backend '
          'must be able to produce and only dart:ui can name',
};

/// Files outside `graphics/` held to the same rule, and why each one is.
const Map<String, String> _alsoBackendFree = <String, String>{
  'lib/src/engine/render/frame_resources.dart':
      'the frame graph would stop being unit-testable off a device',
};

void _check(File file, {String? because}) {
  final allowsDartUi = _mayUseDartUi.containsKey(file.uri.pathSegments.last);
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
      continue;
    }
    expect(
      trimmed.contains('flutter_gpu'),
      isFalse,
      reason: '${file.path} reaches a backend: $trimmed'
          '${because == null ? '' : ' — $because'}',
    );
    if (allowsDartUi) continue;
    expect(
      trimmed.contains('dart:ui'),
      isFalse,
      reason: '${file.path} reaches dart:ui: $trimmed — the engine\'s '
          'vocabulary is its own. If this is genuinely something every backend '
          'must answer, name it in _mayUseDartUi with the reason'
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
