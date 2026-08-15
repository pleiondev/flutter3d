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

/// Every genre word this file says, with the identifier that said it.
List<String> _genreWordsIn(String source) {
  final found = <String>[];
  for (final match in _identifier.allMatches(_code(source))) {
    final words = _words(match.group(0)!);
    for (final forbidden in _genreWords) {
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

  test('nothing in this package says a genre word either', () {
    // The scan above reads imports, and an import is not how this rule gets
    // broken. A constant is.
    final offenders = <String>[
      for (final file in _dartFilesIn('lib'))
        for (final said in _genreWordsIn(file.readAsStringSync()))
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
    expect(_genreWordsIn('static const int oneWay = 1 << 6;'), isNotEmpty);
    expect(_genreWordsIn('int ammo = 0;'), isNotEmpty);
    expect(_genreWordsIn('double get lapTime => 0.0;'), isNotEmpty);

    expect(_genreWordsIn('/// A monster is not our business.'), isEmpty);
    expect(_genreWordsIn('// ammo, weapons, lap times: all elsewhere.'), isEmpty);
    expect(_genreWordsIn('/* a boss with a gun */ int x = 0;'), isEmpty);
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
      expect(_genreWordsIn(innocent), isEmpty, reason: innocent);
    }

    // And the camel hump *is* a boundary, which is the other half of the same
    // claim: `currentLap` must fire where `overlaps` must not.
    expect(_genreWordsIn('int currentLap = 0;'), isNotEmpty);
    expect(_genreWordsIn('void stomp() {}'), isNotEmpty);

    // And inflections, because `stompedThisStep` is the identifier somebody
    // would really write.
    expect(_genreWordsIn('bool stompedThisStep = false;'), isNotEmpty);
    expect(_genreWordsIn('int coins = 0;'), isNotEmpty);
  });
}
