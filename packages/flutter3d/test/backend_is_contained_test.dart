/// `flutter3d` names no graphics API. Not in one directory — anywhere.
///
/// This used to be a subtler claim. The backend lived inside this package, in
/// `lib/src/engine/gpu/`, and the rule was "only that directory imports
/// `flutter_gpu`" — true, checkable, and one afternoon away from being false.
/// The backend is its own package now, so the rule collapsed into something a
/// scan can state without an exception list: **there is no such import here.**
///
/// What that buys is not tidiness. `flutter3d` can be compiled for a target
/// `flutter_gpu` does not support, and a second backend is a package beside
/// `flutter3d_impeller` rather than an edit to the renderer. Neither is true of an
/// engine that contains its backend, however neatly.
///
/// The complement lives in `flutter3d_graphics/test/no_backend_test.dart`: the
/// vocabulary may not reach a backend either.
///
/// Deliberately a file scan. The rule is textual, and a scan says which file
/// broke it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files held to a stricter rule than the rest, and why.
///
/// `frame_resources.dart` is the half of the frame graph where every lifetime
/// bug has lived, and its whole test suite exists because it can be run without
/// a device. A `dart:ui` import would not break the build; it would break the
/// suite, and the analyzer would report only that a test no longer compiles.
const Map<String, String> _alsoFreeOfDartUi = <String, String>{
  'lib/src/engine/render/frame_resources.dart':
      'the frame graph would stop being unit-testable off a device',
};

Iterable<File> _dartFilesIn(String path) {
  final dir = Directory(path);
  expect(
    dir.existsSync(),
    isTrue,
    reason: 'run from the package root, where lib/ is',
  );
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'));
}

bool _reaches(File file, String what) => file.readAsLinesSync().any((line) {
      final trimmed = line.trim();
      return (trimmed.startsWith('import ') || trimmed.startsWith('export ')) &&
          trimmed.contains(what);
    });

void main() {
  test('nothing in this package names a graphics API', () {
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        if (_reaches(file, 'flutter_gpu')) file.path,
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'these name flutter_gpu, which this package must not know '
          'exists. Whatever they need belongs on GraphicsDevice or '
          'CommandEncoder in flutter3d_graphics, with the backend implementing it',
    );
  });

  test('nor does it depend on a backend package', () {
    // The import scan above would miss this: depending on `flutter3d_impeller` and
    // using it through the umbrella library names no backend textually, and
    // would still weld the engine to one.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final forbidden in <String>['flutter_gpu', 'flutter3d_impeller']) {
      expect(
        pubspec.contains('\n  $forbidden:'),
        isFalse,
        reason: 'flutter3d must not depend on $forbidden — an application '
            'chooses a backend, the engine does not',
      );
    }
    expect(
      pubspec.contains('flutter3d_graphics:'),
      isTrue,
      reason: 'a scan that finds nothing proves nothing: if the HAL dependency '
          'is gone, this package is not written against anything and the two '
          'checks above are vacuous',
    );
  });

  test('and the frame graph resource layer reaches no further', () {
    for (final entry in _alsoFreeOfDartUi.entries) {
      final file = File(entry.key);
      expect(
        file.existsSync(),
        isTrue,
        reason: '${entry.key} moved or was renamed; the rule moves with it',
      );
      expect(
        _reaches(file, 'dart:ui'),
        isFalse,
        reason: '${entry.key} reaches dart:ui — ${entry.value}',
      );
    }
  });
}
