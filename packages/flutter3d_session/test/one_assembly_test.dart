/// One assembly per game, and now it is checked rather than remembered.
///
///     flutter test test/one_assembly_test.dart
///
/// **The rule has already paid for itself twice.** The platformer assembled a
/// level in six places — the application and five test harnesses — and the
/// drift had cost something: one harness left the surfaces out, so a level's
/// ice walked exactly like its moss, and the note it still carries says "a
/// harness that is not the game is a harness that agrees with any bug the game
/// has". Other drift was live at the time: one harness ran the validator and
/// three did not, one seeded the purse and four did not, and none passed the
/// next level's name, so no test had ever seen a level that knew where it was
/// going. The crypt had two copies. The racing game had three.
///
/// Each of those was found by somebody reading. This is the part a reader
/// should not have to do again.
///
/// ## Why a scan, and why it lives here
///
/// The rule is textual — "no test builds its own world" — and a scan says which
/// file broke it. It sits in this package rather than in each application
/// because it is one rule about all three, and because this package is where
/// the shape of an application already lives. It is the same shape as
/// `flutter3d_game`'s `no_genre_test.dart`, which reads its sibling packages
/// for the same reason.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The applications, relative to this package.
const List<String> _apps = <String>['platformer', 'dungeon', 'racing'];

String _pathTo(String app) => '../../apps/$app';

/// Calls that put a document's contents into a world.
///
/// Two, and both are the same act in two genres: `spawnInto` turns a level's
/// entities into bodies, and `startSlot` puts a field of cars on the grid. Each
/// is something the shipped game does exactly once, in its own `staging.dart`,
/// and a second caller is a second answer to "what is in this level" — which
/// will disagree with the first, not today but on the day somebody adds a field
/// to one of them.
///
/// **Deliberately not the simulation constructors**, and this list was narrowed
/// after they were tried: `slope_test.dart` builds a bare
/// `PlatformerSimulation` on purpose and says so in the file — it measures the
/// shape of a level's brushes, and spawning the level's entities would put a
/// crate in the way of the geometry the test is about. `playthrough_test.dart`
/// builds one on a bare plane to measure how high a double jump goes. Those are
/// narrower harnesses, not second assemblies, and a rule that called them
/// offenders would be a rule people learn to route around.
const List<String> _assemblies = <String>[
  'spawnInto(',
  'startSlot(',
];

/// Source with comments and strings taken out.
///
/// A doc comment naming `spawnInto` is a doc comment, and this file is full of
/// them. A string is how the scan tests itself.
String _code(String source) => source
    .split('\n')
    .map((String line) => line.replaceAll(RegExp(r'//.*'), ''))
    .join('\n')
    .replaceAll(RegExp("'[^']*'"), "''");

Iterable<File> _dartFilesIn(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'));
}

List<String> _assembliesIn(File file) {
  final code = _code(file.readAsStringSync());
  return <String>[
    for (final call in _assemblies)
      if (code.contains(call)) '${file.path} calls $call',
  ];
}

void main() {
  test('every application has exactly one place that assembles a run', () {
    for (final app in _apps) {
      final root = Directory(_pathTo(app));
      expect(root.existsSync(), isTrue,
          reason: 'run from the package root, beside the other packages');

      final offenders = <String>[
        for (final file in _dartFilesIn('${root.path}/lib'))
          if (!file.path.endsWith('staging.dart')) ..._assembliesIn(file),
      ];

      expect(offenders, isEmpty,
          reason: '$app assembles a run outside its staging.dart');
    }
  });

  test('and no test in an application builds its own', () {
    final offenders = <String>[
      for (final app in _apps)
        for (final file in _dartFilesIn('${_pathTo(app)}/test'))
          ..._assembliesIn(file),
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'a harness that is not the game is a harness that agrees with '
          'any bug the game has — call the game\'s own stage() instead',
    );
  });

  test('and every application has a staging.dart to call', () {
    // The other direction. A game with no shipped assembly passes both tests
    // above by having nothing to be the second copy of.
    for (final app in _apps) {
      expect(File('${_pathTo(app)}/lib/src/staging.dart').existsSync(), isTrue,
          reason: '$app has no one place that assembles a run');
    }
  });

  test('the scan fires on input that breaks the rule', () {
    // A rule nobody can see fail is a rule nobody is keeping. Proved on a file
    // written here rather than committed.
    final temp = Directory.systemTemp.createTempSync('one_assembly_test');
    addTearDown(() => temp.deleteSync(recursive: true));

    final offender = File('${temp.path}/harness_test.dart')
      ..writeAsStringSync('void main() { level.spawnInto(context); }\n');
    expect(_assembliesIn(offender), isNotEmpty);

    // And not on a file that only talks about it.
    final talker = File('${temp.path}/talker.dart')
      ..writeAsStringSync('// call spawnInto( here and this test is wrong\n');
    expect(_assembliesIn(talker), isEmpty);
  });
}
