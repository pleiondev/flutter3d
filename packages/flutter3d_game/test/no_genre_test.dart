/// The engine half names no genre. Not in one directory — anywhere.
///
/// This rule used to be a convention and a pair of unexported files:
/// `shooter.dart` and `sample.dart` sat in `lib/`, and the barrel simply did
/// not export them. That worked exactly as well as everybody remembering it.
/// Meanwhile the weapons, the inventory, the pickup and `GameSimulation` — the
/// step order of a shooter — were in `lib/src/` with no marking at all, and a
/// platformer inherited all of it.
///
/// The genres are packages now, and the rule is arithmetic: a dependency this
/// package does not declare is a dependency it cannot import. This test is the
/// part `pub` will not say out loud — that nobody added one.
///
/// Deliberately a file scan. The rule is textual, and a scan says which file
/// broke it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every package that holds one genre's vocabulary.
///
/// Two of them do not exist yet. They are named anyway, because the cost of a
/// name in a list is nothing and the cost of finding out later is a package
/// that was allowed to grow the wrong way for a month.
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
      reason: 'the engine half must not learn what a monster, a lap or a '
          'double jump is — that is what the genre packages are for',
    );
  });

  test('the detector fires on input that breaks the rule', () {
    // The scan above passes trivially if `_reaches` is wrong, and a rule nobody
    // can see fail is a rule nobody is keeping. So: prove it on a file that
    // does break it, written here rather than committed.
    final temp = Directory.systemTemp.createTempSync('no_genre_test');
    addTearDown(() => temp.deleteSync(recursive: true));
    final offender = File('${temp.path}/offender.dart')
      ..writeAsStringSync(
        "import 'package:flutter3d_shooter/flutter3d_shooter.dart';\n",
      );

    expect(_reaches(offender, 'flutter3d_shooter'), isTrue);

    // And not on a mention that is not an import: a doc comment naming the
    // package is how half this repository explains itself.
    final innocent = File('${temp.path}/innocent.dart')
      ..writeAsStringSync('/// See flutter3d_shooter for the monsters.\n');
    expect(_reaches(innocent, 'flutter3d_shooter'), isFalse);
  });
}
