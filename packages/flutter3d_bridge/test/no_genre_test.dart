/// The bridge binds the two halves without learning what game it is bridging.
///
/// The complement of `flutter3d_game/test/no_genre_test.dart`, and the one that
/// was actually being broken: this package shipped a `WeaponView`, so the
/// mapping between renderer and simulation knew what a weapon was. Its own
/// library doc even admitted the problem and called it "a separate problem".
/// It is not separate any more — the view model is in `flutter3d_shooter`,
/// which is allowed to know, and this scan is what keeps the next one out.
///
/// Deliberately a file scan. The rule is textual, and a scan says which file
/// broke it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _genres = <String>[
  'flutter3d_shooter',
  'flutter3d_platformer',
  'flutter3d_racing',
];

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
  test('nothing in this package names a genre', () {
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        for (final genre in _genres)
          if (_reaches(file, genre)) '${file.path} reaches $genre',
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'a bridge that knows what a weapon is cannot carry a racing game',
    );
  });
}
