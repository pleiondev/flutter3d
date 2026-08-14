/// A genre package is two libraries, and only one of them may see a renderer.
///
/// `flutter3d_shooter.dart` is the simulation: monsters, weapons, the
/// inventory, the step order. It is held to the same rule as `flutter3d_game`
/// — no `flutter3d`, no `flutter_gpu` — because that is what lets three hundred
/// tests in this package run without a device, and because a collision that
/// lets the player through a wall once in a thousand steps is not visible in a
/// screenshot.
///
/// `bridge.dart` is the other half, and it exists precisely so the rule can
/// hold: the weapon in the player's hands has to be drawn by somebody, and a
/// genre package sits above the bridge, which is the one place the two halves
/// are allowed to meet.
///
/// So the package depends on `flutter3d` and this test says which files may
/// spend that dependency. An allowlist rather than a directory rule, so that
/// adding a second renderer-facing file is a deliberate line in this file
/// rather than a `mv`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The renderer-facing half, named file by file.
///
/// `bridge.dart` itself is not here: it re-exports and names nothing, which is
/// what a barrel should do.
const Set<String> _mayDraw = <String>{
  'lib/src/weapon_view.dart',
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
  test('the simulation half draws nothing', () {
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        if (!_mayDraw.contains(file.path))
          if (_reaches(file, 'package:flutter3d/') ||
              _reaches(file, 'flutter_gpu'))
            file.path,
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'move it into bridge.dart, or add it to _mayDraw and say why',
    );
  });

  test('the allowlist fails in both directions', () {
    // An allowlist that names a file which no longer exists is a rule rotting
    // into a description of work already done — and one that has stopped
    // reaching a renderer is a line that should be deleted rather than kept
    // out of politeness.
    for (final path in _mayDraw) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$path is allowed to draw and is not there',
      );
      expect(
        _reaches(file, 'package:flutter3d/') || _reaches(file, 'flutter_gpu'),
        isTrue,
        reason: '$path no longer draws; take it off the list',
      );
    }
  });
}
