/// The rule that keeps a package from learning what game it is for.
///
/// **Two copies of two hundred lines is how this came to be a package.** The
/// scan lived in `flutter3d_game/test/no_genre_test.dart` and again in
/// `flutter3d_bridge/test/`, the same file but for its doc comments — and the
/// bridge's copy had **lost the test that proves the detector works**, so it
/// passed whether or not the rule was being kept. Six more packages were
/// unguarded entirely, and six more copies was not a plan.
///
/// One call registers the whole rule:
///
/// ```dart
/// void main() => expectNoGenre();
/// ```
///
/// which is five tests: nothing in `lib/` imports a genre package, nothing
/// depends on an application, nothing *says* a genre word, and — the two that
/// keep the other three honest — both detectors fire on input that breaks the
/// rule and stay quiet on input that only looks like it.
///
/// ## What this is not
///
/// It is not a linter and it does not read Dart. It splits identifiers into
/// words and compares them to a list, which is crude and is the point: a rule
/// that needs an analyser is a rule nobody runs, and every previous attempt at
/// this one died of false positives rather than of missed cases.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every package that holds one genre's vocabulary.
///
/// Two of them do not exist yet. They are named anyway, because the cost of a
/// name in a list is nothing and the cost of finding out later is a package
/// that was allowed to grow the wrong way for a month.
///
/// **Public, and that is the whole of how the repository keeps one list.** A
/// checkout that adds a fourth genre has two places that must learn about it —
/// this constant and the workspace in the root `pubspec.yaml` — and a
/// repository-level test compares the two. Deriving the list from the pubspec
/// instead was the other option and was rejected: this package is published,
/// and a rule that only works inside one checkout is not a rule a consumer can
/// keep.
const List<String> genrePackages = <String>[
  'flutter3d_game_shooter',
  'flutter3d_game_platformer',
  'flutter3d_game_racing',
];

/// Every application in this repository.
///
/// Public for the reason [genrePackages] is, and it was inline in one test —
/// four names in a loop, with `template_app` missing from it, which is exactly
/// the drift a second copy produces.
const List<String> applications = <String>[
  'flutter3d_demo_dungeon',
  'flutter3d_demo_platformer',
  'flutter3d_demo_racing',
  'flutter3d_editor',
  'flutter3d_template_app',
];

/// Genre vocabulary, as words rather than as imports.
///
/// **The hole the import scan leaves.** `CollisionLayers.oneWay` imports
/// nothing. Neither does `int ammo`, nor `double lapTime`, nor a `crouch` on
/// the shared action table. Every one of those is the exact mistake the scan
/// above exists to prevent, and every one of them passes it — which is not a
/// hypothetical: writing this list found `CollisionLayers.monster` in
/// `flutter3d_game`, in a file whose own doc comment says that a collision
/// world knowing what a monster is cannot be used by a game that has none.
///
/// **Where the line is.** These are words of a *fiction* and of one genre's
/// *repertoire* — what a thing is in the story, and what one kind of game lets
/// you do. They are not words for mechanisms. That distinction is what keeps
/// the list honest and small:
///
///   * `pickup` stays allowed: it names what a volume does when you walk into
///     it, and all three genres have one.
///   * `sprint` and `jump` stay allowed: they are entries in the shared action
///     table, which is a list of inputs a game may bind, not a claim about
///     what the game is.
///   * `platform` stays allowed: a lift in a shooter and a moving platform in a
///     platformer are the same furniture, and it is also the word for an
///     operating system.
///   * `coyote` stays allowed where it lives, on `CharacterController`: it is
///     the name the whole industry uses for a grace period after leaving the
///     ground, and renaming a mechanism to avoid its own name makes it harder
///     to find, not more general.
///   * `drift` is *not* on the list at all, because `DriftEmitter` in
///     `flutter3d_particles` is particles drifting and has nothing to do with
///     racing. A word that cannot be told apart from an innocent one is a word
///     that will be silenced with a comment the first time it fires.
const List<String> _genreWords = <String>[
  // Fiction.
  'monster', 'zombie', 'boss', 'loot', 'treasure', 'mana',
  // A shooter's repertoire.
  'weapon', 'gun', 'ammo', 'magazine', 'grenade', 'headshot', 'reload',
  // A platformer's.
  'one way', 'crouch', 'dash', 'double jump', 'wall jump', 'coin', 'stomp',
  'powerup', 'power up', 'spike', 'lava',
  // A racer's.
  'lap', 'nitro', 'chicane', 'pit stop',
];

/// Splits an identifier into lowercase words: `oneWay` → `one`, `way`.
///
/// **Segments and not a substring search**, and that is the whole of why this
/// detector is usable. `overlaps` contains `lap`, `elapsed` contains `lap`,
/// `collapse` contains `lap`; a substring search fires on all three and gets
/// switched off within a week. `currentLap` is what should fire, and does.
List<String> _words(String identifier) => <String>[
      for (final chunk in identifier.split('_'))
        for (final match in _camel.allMatches(chunk))
          match.group(0)!.toLowerCase(),
    ];

final RegExp _camel = RegExp(r'[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+');
final RegExp _identifier = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

/// The file with its comments removed.
///
/// **Comments are exempt on purpose.** Half of this repository explains itself
/// by naming the thing it is deliberately not doing — `GameAction`'s own doc
/// shows `GameAction('dash')` as the example of how a genre extends the table,
/// which is the rule being kept, written out. A detector that fires on prose is
/// a detector that gets deleted.
String _code(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
    .split('\n')
    .map((String line) => line.replaceAll(RegExp(r'//.*'), ''))
    .join('\n');

/// Every genre word [source] says, with the identifier that said it.
///
/// Public because a package with a rule of its own can ask directly, and
/// because the tests that prove this detector works are the reason anybody
/// believes the ones that use it.
List<String> genreWordsIn(String source, {List<String>? words}) {
  final forbiddenWords = words ?? _genreWords;
  final found = <String>[];
  for (final match in _identifier.allMatches(_code(source))) {
    final words = _words(match.group(0)!);
    for (final forbidden in forbiddenWords) {
      final wanted = forbidden.split(' ');
      for (var i = 0; i + wanted.length <= words.length; i++) {
        if (_sameWords(words.sublist(i, i + wanted.length), wanted)) {
          found.add('${match.group(0)} says "$forbidden"');
        }
      }
    }
  }
  return found;
}

bool _sameWords(List<String> a, List<String> b) {
  for (var i = 0; i < a.length - 1; i++) {
    if (a[i] != b[i]) return false;
  }
  return _sameWord(a.last, b.last);
}

/// Whether one word is another, allowing for how English inflects it.
///
/// `stompedThisStep` and `coins` are the same leak as `stomp` and `coin`, and a
/// detector that only knows the dictionary form misses the identifiers people
/// actually write. Three suffixes and no more: the guard against `overlaps`
/// still holds — `overlaps` less its `s` is `overlap`, which is not `lap` —
/// and every suffix added past this point buys a false positive.
bool _sameWord(String said, String forbidden) =>
    said == forbidden ||
    said == '${forbidden}s' ||
    said == '${forbidden}es' ||
    said == '${forbidden}ed' ||
    said == '${forbidden}ing';

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

/// Whether [file] imports or exports something from [what].
///
/// Public for the same reason [genreWordsIn] is: the test that proves it fires
/// is what makes the scan mean anything, and it ships with the scan.
bool reaches(File file, String what) => file.readAsLinesSync().any((line) {
      final trimmed = line.trim();
      return (trimmed.startsWith('import ') || trimmed.startsWith('export ')) &&
          trimmed.contains(what);
    });

/// Registers the whole rule for the package the test is running in.
///
/// [also] adds words this package must not say — a caller that knows something
/// about its own place in the world can tighten the rule for itself. [allowing]
/// removes them, and every use of it should say why in a comment: a rule with
/// an exception nobody explained is a rule on its way out.
void expectNoGenre({
  List<String> also = const <String>[],
  List<String> allowing = const <String>[],
}) {
  final words = <String>[
    for (final word in <String>[..._genreWords, ...also])
      if (!allowing.contains(word)) word,
  ];

  test('nothing in this package names a genre', () {
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        for (final genre in genrePackages)
          if (reaches(file, genre)) '${file.path} reaches $genre',
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'the engine half must not learn what a monster, a lap or a '
          'double jump is — that is what the genre packages are for',
    );
  });

  test('and this package depends on no application at all', () {
    // **It did, and the pubspec said otherwise four lines above.** Two
    // `dev_dependencies` — on a genre package and on the `platformer`
    // application — existed so that one test could mount that game's HUD, which
    // also meant importing `package:flutter3d_demo_platformer/src/hud.dart`: another package's
    // private half. A cycle, a genre and a `lib/src`, in two lines.
    //
    // The mechanism is tested here and the sentence on the screen is tested in
    // the game that says it.
    final pubspec = File('pubspec.yaml').readAsStringSync();

    for (final app in applications) {
      expect(RegExp('^\\s+$app:', multiLine: true).hasMatch(pubspec), isFalse,
          reason: 'this package depends on the $app application');
    }
  });

  test('the detector fires on input that breaks the rule', () {
    // The scan above passes trivially if `_reaches` is wrong, and a rule nobody
    // can see fail is a rule nobody is keeping. So: prove it on a file that
    // does break it, written here rather than committed.
    final temp = Directory.systemTemp.createTempSync('no_genre_test');
    addTearDown(() => temp.deleteSync(recursive: true));
    final offender = File('${temp.path}/offender.dart')
      ..writeAsStringSync(
        "import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';\n",
      );

    expect(reaches(offender, 'flutter3d_game_shooter'), isTrue);

    // And not on a mention that is not an import: a doc comment naming the
    // package is how half this repository explains itself.
    final innocent = File('${temp.path}/innocent.dart')
      ..writeAsStringSync('/// See flutter3d_game_shooter for the monsters.\n');
    expect(reaches(innocent, 'flutter3d_game_shooter'), isFalse);
  });

  test('nothing in this package says a genre word either', () {
    // The scan above reads imports, and an import is not how this rule gets
    // broken. A constant is.
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        for (final said in genreWordsIn(file.readAsStringSync(), words: words))
          '${file.path}: $said',
    ];

    expect(offenders, isEmpty,
        reason: 'a word from one genre in the engine half is that genre '
            'leaking, whether or not anything was imported');
  });

  test('the word detector fires on a constant and not on a comment', () {
    // Self-proving, for the same reason the import detector is: a scan that
    // cannot fail is a rule nobody is keeping. Both halves matter here — the
    // constant is the bug that was actually found, and the comment is what
    // every previous attempt at a rule like this died of.
    expect(genreWordsIn('static const int oneWay = 1 << 6;'), isNotEmpty);
    expect(genreWordsIn('int ammo = 0;'), isNotEmpty);
    expect(genreWordsIn('double get lapTime => 0.0;'), isNotEmpty);

    expect(genreWordsIn('/// A monster is not our business.'), isEmpty);
    expect(genreWordsIn('// ammo, weapons, lap times: all elsewhere.'), isEmpty);
    expect(genreWordsIn('/* a boss with a gun */ int x = 0;'), isEmpty);
  });

  test('and not on words that merely contain one', () {
    // The failure mode that kills detectors like this: `overlaps` holds `lap`,
    // `collapse` holds `lap`, `elapsed` holds `lap`. Three false positives in
    // the first hour and the test is deleted.
    //
    // Mutation: match on substrings rather than on identifier words.
    for (final innocent in <String>[
      'bool overlaps = true;',
      'double elapsed = 0.0;',
      'void collapse() {}',
      'final DriftEmitter drift = DriftEmitter();',
      'void dashboard() {}',
      'int coinage = 0;',
    ]) {
      expect(genreWordsIn(innocent), isEmpty, reason: innocent);
    }

    // And the camel hump *is* a boundary, which is the other half of the same
    // claim: `currentLap` must fire where `overlaps` must not.
    expect(genreWordsIn('int currentLap = 0;'), isNotEmpty);
    expect(genreWordsIn('void stomp() {}'), isNotEmpty);

    // And inflections, because `stompedThisStep` is the identifier somebody
    // would really write.
    expect(genreWordsIn('bool stompedThisStep = false;'), isNotEmpty);
    expect(genreWordsIn('int coins = 0;'), isNotEmpty);
  });
}

/// A `static final` holding something mutable, which is a global variable
/// wearing a constant's clothes.
///
/// `Vector3`, `Matrix4` and their relatives are mutable. A `static final` one
/// is written once and shared for the life of the process, so the first caller
/// to write `Colors.bounds.scale(2)` or `Kind.defaultSize.setValues(...)`
/// changes it for every other caller, in a declaration that reads like a
/// constant and that nothing marks as changeable. The compiler has nothing to
/// say about it: `final` is about the reference.
///
/// Thirty-two of these existed across the repository when this rule was
/// written, twelve of them sizes handed straight to entities that a level could
/// have scaled. None was being mutated, which is why writing the rule was
/// cheap. A getter returning a fresh value costs one allocation and cannot be
/// shared at all.
///
/// Public so its own test can prove it fires — the same reason [genreWordsIn]
/// is.
List<String> sharedMutablesIn(String source) {
  final found = <String>[];
  for (final match in _sharedMutable.allMatches(source)) {
    found.add(match.group(0)!.trim());
  }
  return found;
}

/// `static final Vector3 name = …`, and the same for the other mutable value
/// types this repository uses.
///
/// Deliberately not "any `static final`": a `static final List` of constants, a
/// `static final RegExp`, a `static final Map` used as a lookup are all
/// ordinary and none of them is a value somebody scales in place. What this
/// catches is the vector-maths types, which are mutable *and* look like maths.
final RegExp _sharedMutable = RegExp(
  r'static final (Vector[234]|Matrix[234]|Quaternion|Aabb[23])\s+\w+\s*=',
);

/// The rule that this package holds no shared mutable value pretending to be a
/// constant.
///
/// Two tests: the scan, and the proof that the scan fires.
void expectNoSharedMutables({List<String> allowing = const <String>[]}) {
  test('nothing in this package shares a mutable value as a constant', () {
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        for (final said in sharedMutablesIn(file.readAsStringSync()))
          if (!allowing.any(said.contains)) '${file.path}: $said',
    ];

    expect(offenders, isEmpty,
        reason: 'a `static final Vector3` is a global variable that reads as a '
            'constant — the first caller to scale it in place changes it for '
            'the whole process. Return a fresh one from a getter.');
  });

  test('and that detector fires too', () {
    expect(sharedMutablesIn('static final Vector3 up = Vector3(0.0, 1.0, 0.0);'),
        isNotEmpty);
    expect(sharedMutablesIn('static final Matrix4 identity = Matrix4.zero();'),
        isNotEmpty);

    // And stays quiet on the shapes that are not this mistake.
    expect(sharedMutablesIn('static Vector3 get up => Vector3(0.0, 1.0, 0.0);'),
        isEmpty,
        reason: 'the fix was reported as the fault');
    expect(sharedMutablesIn('final Vector3 position = Vector3.zero();'), isEmpty,
        reason: 'an instance field is not shared with anybody');
    expect(sharedMutablesIn('static const double gravity = -9.8;'), isEmpty);
    expect(sharedMutablesIn('static final RegExp _key = RegExp(r"a");'), isEmpty,
        reason: 'a compiled pattern is not a value anybody scales');
  });
}

/// The two rules a genre package is held to.
///
/// **The mirror image of [expectNoGenre], and it was in three states at once.**
/// A genre package is allowed to know what a monster is — that is what it is
/// for — so the rule it keeps instead is that its *simulation* half draws
/// nothing, and that it does not reach sideways into another genre. Racing kept
/// both, the shooter kept one, and the platformer kept neither; each of the two
/// that existed carried its own private copy of [reaches], which is the same
/// two-copies-of-a-scan that made this package.
///
/// [mayDraw] names the renderer-facing files, one path at a time, relative to
/// the package root. An allowlist rather than a directory rule, so that a second
/// file needing a renderer is a deliberate line here rather than a `mv`.
///
/// [otherGenres] defaults to every entry of [genrePackages] that is not this
/// package. `pub` cannot say what was never declared, and a `dev_dependency` on
/// a sibling genre would tie the two together for as long as nobody looked.
///
/// Three tests, and the second is the one that keeps the first honest: an
/// allowlist naming a file that no longer draws is a rule rotting into a
/// description of work already done.
void expectGenreIsolation({
  Set<String> mayDraw = const <String>{},
  List<String>? otherGenres,
}) {
  // Read inside the test rather than here. `expect` throws
  // `OutsideTestException` when no test is running, and everything in this
  // function body runs at registration time — the same trap
  // `flutter3d_conformance` writes down on its own `require`, met from the
  // other side.
  List<String> siblings() =>
      otherGenres ??
      <String>[
        for (final genre in genrePackages)
          if (genre != _packageName()) genre,
      ];

  bool draws(File file) =>
      reaches(file, 'package:flutter3d/') || reaches(file, 'flutter_gpu');

  test('the simulation half draws nothing', () {
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        if (!mayDraw.contains(file.path))
          if (draws(file)) file.path,
    ];

    expect(offenders, isEmpty,
        reason: 'move it into the bridge, or add it to mayDraw and say why — '
            'the simulation half is what lets this package be tested without a '
            'device, and a collision that lets a body through a wall once in a '
            'thousand steps is not visible in a screenshot');
  });

  test('and the allowlist fails in both directions', () {
    for (final path in mayDraw) {
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: '$path is allowed to draw and is not there');
      expect(draws(file), isTrue,
          reason: '$path no longer draws; take it off the list');
    }
  });

  test('and this package does not reach into another genre', () {
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        for (final genre in siblings())
          if (reaches(file, genre)) '${file.path} reaches $genre',
    ];

    expect(offenders, isEmpty,
        reason: 'a racing game borrowing a platformer\'s runner would compile, '
            'and would tie the two together for as long as nobody looked');
  });
}

/// What a step must not reach for, as patterns over the source.
///
/// An unseeded `Random()` and a system clock are the two things that make a
/// step unrepeatable. A **seeded** `Random(n)` is not on trial — it is written
/// down and comes back the same, which is the property being kept — so the
/// pattern deliberately matches only the empty-argument form.
///
/// Public so its own test can prove it fires, the same reason [genreWordsIn]
/// is.
final Map<RegExp, String> stepMustNotReachFor = <RegExp, String>{
  RegExp(r'\bRandom\(\s*\)'): 'an unseeded Random',
  RegExp(r'\bDateTime\.now\(\)'): 'the system clock',
  RegExp(r'\bStopwatch\('): 'a wall clock',
};

/// Whatever [source] reaches for that a step may not, or null.
String? unrepeatableIn(String source) {
  final code = _code(source);
  for (final entry in stepMustNotReachFor.entries) {
    if (entry.key.hasMatch(code)) return entry.value;
  }
  return null;
}

/// The rule that a step is repeatable from its inputs.
///
/// **SPEC §6.4 recorded this as already true and named the test as missing.**
/// It was not true: `ActorSystem` and the shooter's `Hitscan` both defaulted to
/// an unseeded `math.Random`, the shipped dungeon took both defaults, and its
/// simulation's own generator was left null — so the crypt rolled dice nobody
/// could write down and its saves restored none of them. Every part of that
/// survived review for as long as the rule lived only in a document.
///
/// This is the half of the rule a scan can keep: it fails on the *next*
/// `Random()` or `DateTime.now()` somebody writes, at the moment they write it,
/// and names the file. What it cannot do is notice a simulation that diverges
/// for some other reason — that is a behavioural test, and it belongs with the
/// game whose step it is.
///
/// [allowing] exempts a file by path, and every entry should say why in the
/// map's value. Not "anything outside `src/`": an exemption is for a file that
/// is not part of a step at all — a loader, or the generator itself. A file
/// that runs inside `step` and wants to be on the list is the bug.
void expectRepeatableStep({
  Map<String, String> allowing = const <String, String>{},
}) {
  test('nothing here reaches for a clock or for loose dice', () {
    final scanned = _dartFilesIn('lib').toList();

    // A scan of nothing passes. Without this the test goes green from the wrong
    // working directory, which is how a rule quietly stops being kept.
    expect(scanned, isNotEmpty, reason: 'run from the package root');

    final offenders = <String>[
      for (final file in scanned)
        if (!allowing.containsKey(file.path))
          if (unrepeatableIn(file.readAsStringSync()) case final String said)
            '${file.path}: $said',
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'SPEC §6.4: a step takes its randomness from a generator it was '
          'handed and never asks the system what time it is. Take a seeded '
          'generator as a required parameter, or list the file in `allowing` '
          'with the reason it is not part of a step',
    );
  });

  test('and that detector fires on each of the three, and not on a seed', () {
    // Mutation: match `Random(` rather than `Random()`, and the seeded form —
    // which is the fix rather than the fault — is reported as the bug.
    expect(unrepeatableIn('final r = Random();'), 'an unseeded Random');
    expect(unrepeatableIn('final t = DateTime.now();'), 'the system clock');
    expect(unrepeatableIn('final w = Stopwatch()..start();'), 'a wall clock');

    expect(unrepeatableIn('final r = Random(7);'), isNull,
        reason: 'a seed is written down and comes back the same');
    expect(unrepeatableIn('final r = GameRandom(1);'), isNull);
    expect(unrepeatableIn('// Random() would be wrong here.'), isNull,
        reason: 'a comment explaining the rule must not break it');
  });
}

/// This package's name, read from its own pubspec.
///
/// Read rather than passed, because a caller that had to name itself would name
/// itself wrongly the first time a package was renamed — and the pubspec is the
/// one place that cannot be wrong about it.
String _packageName() {
  final match = RegExp(r'^name:\s*(\S+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync());
  if (match == null) {
    throw StateError('no `name:` in pubspec.yaml — run from the package root');
  }
  return match.group(1)!;
}

/// Every rule in this package, for a caller with nothing to say about its own
/// case.
void expectPackageBoundaries() {
  expectNoGenre();
  expectNoSharedMutables();
}
