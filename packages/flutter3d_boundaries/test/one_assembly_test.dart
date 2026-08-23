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
/// file broke it.
///
/// **It moved here from `flutter3d_session`**, which was the wrong home for two
/// reasons that only show up outside this checkout: that package is published,
/// so the test travelled with it to machines where `../../apps/platformer` does
/// not exist, and it kept its own list of applications that had already drifted
/// from the one in this package — `editor` in one, not the other, and
/// `template_app` in neither. This package is where the repository's lists
/// live, so the rule lives beside them and reads [applications]. The guard at
/// the top of [main] skips the whole file when the checkout is not this
/// repository, which is the honest answer for a consumer who installed the
/// package and got a test about somebody else's games.
library;

import 'dart:io';

import 'package:flutter3d_boundaries/flutter3d_boundaries.dart';
import 'package:test/test.dart';

String _pathTo(String app) => '../../apps/$app';

/// Whether this is the flutter3d checkout rather than somebody's pub cache.
///
/// The rule is about applications this repository ships. A consumer who
/// depends on this package has neither them nor any reason to be told about
/// them.
bool _inTheRepository() {
  final root = File('../../pubspec.yaml');
  return root.existsSync() &&
      root.readAsStringSync().contains('name: flutter3d_workspace');
}

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
/// **The visual half was outside this list, and that is what it cost.** The
/// crypt's `run_cubit_test.dart` rebuilt the game's `openScene` by hand —
/// `ActorVisuals` and `FixtureVisuals` over the loaded scene — and its copy had
/// lost one line, `..bindLights()`. Every torch in that harness lit nothing
/// while the game's lit the room, and the rule named after exactly this failure
/// watched two calls that the file did not make. A second `FixtureVisuals` is a
/// second answer to "what does this level look like", for the same reason a
/// second `spawnInto` is a second answer to what is in it.
const List<String> _assemblies = <String>[
  'spawnInto(',
  'startSlot(',
  'ActorVisuals(',
  'FixtureVisuals(',
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
  // A consumer's checkout has no `apps/`, and a test about somebody else's
  // games has nothing to tell them.
  if (!_inTheRepository()) {
    test('the assembly rule is about this repository', () {}, skip: true);
    return;
  }

  test('each assembly call has at most one home in each application', () {
    // **"At most one file", not "only staging.dart".** The rule used to name
    // the file, and that was wrong in a way the crypt paid for: `staging.dart`
    // is deliberately device-free — it is what a test with no GPU can call —
    // so the visual half genuinely cannot live there and had nowhere else it
    // was required to be. Counting homes says what the rule actually means
    // without deciding which file each game keeps them in: the platformer's
    // visuals are in `run.dart`, the crypt's in `run_cubit.dart`, and neither
    // is wrong.
    for (final app in applications) {
      final lib = Directory('${_pathTo(app)}/lib');
      if (!lib.existsSync()) continue;

      final homes = <String, List<String>>{};
      for (final file in _dartFilesIn(lib.path)) {
        final code = _code(file.readAsStringSync());
        for (final call in _assemblies) {
          if (code.contains(call)) {
            homes.putIfAbsent(call, () => <String>[]).add(file.path);
          }
        }
      }

      for (final entry in homes.entries) {
        expect(entry.value, hasLength(1),
            reason: '$app calls ${entry.key} in ${entry.value.length} places: '
                '${entry.value.join(', ')} — the second one is a second answer '
                'to what a level contains, and it will disagree with the first');
      }
    }
  });

  test('and no test in an application builds its own', () {
    final offenders = <String>[
      for (final app in applications)
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

  test('and the repository lists agree with the workspace', () {
    // **The single source of truth, kept by comparison rather than by
    // derivation.** `applications` and `genrePackages` are constants because
    // this package is published and cannot read a checkout it is not in. What
    // stops them rotting is this: the workspace in the root pubspec is the list
    // `pub` actually uses, and a fourth game that reaches one list and not the
    // other fails here rather than in six months.
    final workspace = File('../../pubspec.yaml').readAsStringSync();
    final members = <String>[
      for (final line in workspace.split('\n'))
        if (RegExp(r'^\s+-\s+(packages|apps)/').hasMatch(line)) line.trim()
    ];

    final inWorkspace = <String>{
      for (final member in members)
        if (member.startsWith('- apps/')) member.substring('- apps/'.length),
    };
    expect(applications.toSet(), inWorkspace,
        reason: 'the applications list and the workspace disagree');

    final genresInWorkspace = <String>{
      for (final member in members)
        if (member.startsWith('- packages/flutter3d_game_'))
          member.substring('- packages/'.length),
    };
    expect(genrePackages.toSet(), genresInWorkspace,
        reason: 'the genre list and the workspace disagree');
  });

  test('and every game has a staging.dart to call', () {
    // The other direction. A game with no shipped assembly passes both tests
    // above by having nothing to be the second copy of.
    //
    // The three games, not every application: `editor` builds levels rather
    // than playing one, and `template_app` is the seed a new project starts
    // from. Neither has a run to assemble, and demanding one of them would be
    // the rule describing work already done rather than work that must hold.
    for (final app in <String>['dungeon', 'platformer', 'racing']) {
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

    // The visual half too, which is the pair that was missing: the crypt's
    // harness said exactly this and the rule did not look.
    final looks = File('${temp.path}/looks_test.dart')
      ..writeAsStringSync('final v = FixtureVisuals(scene, loaded);\n');
    expect(_assembliesIn(looks), isNotEmpty);

    // And not on a file that only talks about it.
    final talker = File('${temp.path}/talker.dart')
      ..writeAsStringSync('// call spawnInto( here and this test is wrong\n');
    expect(_assembliesIn(talker), isEmpty);
  });
}
