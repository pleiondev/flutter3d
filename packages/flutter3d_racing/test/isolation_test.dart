/// The two rules a genre package is held to, checked the only way they can be:
/// by reading the files.
///
/// The first is that only the visual half draws. It is the same arrangement
/// `flutter3d_game_shooter` has: the simulation is held to the rule
/// `flutter3d_game` keeps — no `flutter3d`, no `flutter_gpu` — which is what
/// lets every test here run without a device, and `bridge.dart` is the one
/// place the two halves are allowed to meet. The allowlist below is that place,
/// named a file at a time.
///
/// The second is that this package does not reach sideways into another genre.
/// A racing game borrowing a platformer's runner would compile, and would tie
/// the two together for as long as nobody looked.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The renderer-facing files, named one at a time.
///
/// `bridge.dart` is here rather than being exempt by its name: the rule is a
/// list, and a second file that needs a renderer should be a deliberate line
/// added here rather than a rename.
const Set<String> _mayDraw = <String>{
  'lib/bridge.dart',
};

/// The other genres. Sibling packages, not dependencies — and this is what says
/// so, since `pub` cannot say what was never declared.
const List<String> _otherGenres = <String>[
  'flutter3d_game_shooter',
  'flutter3d_platformer',
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
    // An allowlist naming a file that no longer exists is a rule rotting into a
    // description of work already done; one naming a file that has stopped
    // reaching a renderer is a line kept out of politeness.
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

  test('this genre does not borrow another one', () {
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        for (final genre in _otherGenres)
          if (_reaches(file, genre)) '${file.path} reaches $genre',
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'what is shared between two genres belongs in the engine half, '
          'and what is not shared belongs in one of them',
    );
  });

  test('the detector fires on input that breaks the rule', () {
    // Both scans above pass trivially if `_reaches` is wrong, and a rule nobody
    // can see fail is a rule nobody is keeping.
    final temp = Directory.systemTemp.createTempSync('racing_isolation');
    addTearDown(() => temp.deleteSync(recursive: true));

    final offender = File('${temp.path}/offender.dart')
      ..writeAsStringSync("import 'package:flutter3d/flutter3d.dart';\n");
    expect(_reaches(offender, 'package:flutter3d/'), isTrue);

    // And not on a mention that is not an import: half of what this package
    // explains, it explains by naming the renderer in a doc comment.
    final innocent = File('${temp.path}/innocent.dart')
      ..writeAsStringSync('/// The bridge is where package:flutter3d/ meets.\n');
    expect(_reaches(innocent, 'package:flutter3d/'), isFalse);
  });
}
