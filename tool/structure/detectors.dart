/// The detectors: pure functions over source text, and the checks that prove
/// each one fires.
///
/// **Every rule in this directory is one of these plus a walk of the tree**,
/// and the split matters more than it looks. A scan is only worth what its
/// detector is worth, and a detector nobody has seen fail is a rule nobody is
/// keeping — which is not hypothetical here: the genre scan once lived in two
/// copies and one of them had already lost the check that it fired at all, so
/// it passed whether or not the rule was being kept.
///
/// So [proveDetectorsWork] runs first, every time, before anything is scanned.
/// If a detector cannot fire on input that breaks the rule, or fires on input
/// that only looks like it, the run stops there and the scans are not reported
/// at all — a green scan behind a broken detector is worse than a red one.
library;

/// One thing a rule found, with enough to act on it.
final class Finding {
  const Finding(this.where, this.what);

  /// A path, or a package name for a rule that is about a whole package.
  final String where;

  /// One line. What is wrong, in the words the reader needs.
  final String what;

  @override
  String toString() => '$where: $what';
}

// ---------------------------------------------------------------- genre words

/// Genre vocabulary, as words rather than as imports.
///
/// **The hole an import scan leaves.** `CollisionLayers.oneWay` imports
/// nothing. Neither does `int ammo`, nor `double lapTime`, nor a `crouch` on
/// the shared action table. Every one of those is the mistake the import scan
/// exists to prevent, and every one of them passes it — which is not a
/// hypothetical: writing this list found `CollisionLayers.monster` in
/// `flutter3d_game`, in a file whose own doc comment says that a collision
/// world knowing what a monster is cannot be used by a game that has none.
///
/// **Where the line is.** These are words of a *fiction* and of one genre's
/// *repertoire* — what a thing is in the story, and what one kind of game lets
/// you do. They are not words for mechanisms, and that distinction is what
/// keeps the list small and honest:
///
///   * `pickup` stays allowed: it names what a volume does when you walk into
///     it, and all three genres have one.
///   * `sprint` and `jump` stay allowed: entries in the shared action table,
///     which is a list of inputs a game may bind rather than a claim about
///     what the game is.
///   * `platform` stays allowed: a lift in a shooter and a moving platform in
///     a platformer are the same furniture, and it is also the word for an
///     operating system.
///   * `coyote` stays allowed where it lives, on `CharacterController`: it is
///     the name the whole industry uses for a grace period after leaving the
///     ground, and renaming a mechanism to avoid its own name makes it harder
///     to find rather than more general.
///   * `drift` is *not* on the list at all, because `DriftEmitter` in
///     `flutter3d_particles` is particles drifting and has nothing to do with
///     racing. A word that cannot be told apart from an innocent one is a word
///     that will be silenced with a comment the first time it fires.
const List<String> kGenreWords = <String>[
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

final RegExp _camel = RegExp(r'[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+');
final RegExp _identifier = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

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

/// The source with its comments removed.
///
/// **Comments are exempt on purpose.** Half of this repository explains itself
/// by naming the thing it is deliberately not doing — `GameAction`'s own doc
/// shows `GameAction('dash')` as the example of how a genre extends the table,
/// which is the rule being kept, written out. A detector that fires on prose is
/// a detector that gets deleted.
String codeOf(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
    .split('\n')
    .map((String line) => line.replaceAll(RegExp(r'//.*'), ''))
    .join('\n');

/// Whether one word is another, allowing for how English inflects it.
///
/// `stompedThisStep` and `coins` are the same leak as `stomp` and `coin`, and a
/// detector that only knows the dictionary form misses the identifiers people
/// actually write. Three suffixes and no more: the guard against `overlaps`
/// still holds — `overlaps` less its `s` is `overlap`, which is not `lap` — and
/// every suffix added past this point buys a false positive.
bool _sameWord(String said, String forbidden) =>
    said == forbidden ||
    said == '${forbidden}s' ||
    said == '${forbidden}es' ||
    said == '${forbidden}ed' ||
    said == '${forbidden}ing';

bool _sameWords(List<String> a, List<String> b) {
  for (var i = 0; i < a.length - 1; i++) {
    if (a[i] != b[i]) return false;
  }
  return _sameWord(a.last, b.last);
}

/// Every genre word [source] says, with the identifier that said it.
List<String> genreWordsIn(String source, {List<String> words = kGenreWords}) {
  final found = <String>[];
  for (final match in _identifier.allMatches(codeOf(source))) {
    final said = _words(match.group(0)!);
    for (final forbidden in words) {
      final wanted = forbidden.split(' ');
      for (var i = 0; i + wanted.length <= said.length; i++) {
        if (_sameWords(said.sublist(i, i + wanted.length), wanted)) {
          found.add('${match.group(0)} says "$forbidden"');
        }
      }
    }
  }
  return found;
}

// ------------------------------------------------------------ shared mutables

/// `static final Vector3 name = …`, and the other mutable value types.
///
/// Deliberately not "any `static final`": a `static final List` of constants, a
/// `static final RegExp`, a `static final Map` used as a lookup are all
/// ordinary and none of them is a value somebody scales in place. What this
/// catches is the vector-maths types, which are mutable *and* look like maths.
final RegExp _sharedMutable = RegExp(
  r'static final (Vector[234]|Matrix[234]|Quaternion|Aabb[23])\s+\w+\s*=',
);

/// Every shared mutable value [source] declares as if it were a constant.
///
/// `Vector3`, `Matrix4` and their relatives are mutable. A `static final` one is
/// written once and shared for the life of the process, so the first caller to
/// write `Colors.bounds.scale(2)` changes it for every other caller, in a
/// declaration that reads like a constant and that nothing marks as changeable.
/// The compiler has nothing to say about it: `final` is about the reference.
List<String> sharedMutablesIn(String source) => <String>[
      for (final match in _sharedMutable.allMatches(source)) match.group(0)!.trim(),
    ];

// ------------------------------------------------------------- a step's inputs

/// What a step must not reach for, as patterns over the source.
///
/// An unseeded `Random()` and a system clock are the two things that make a step
/// unrepeatable. A **seeded** `Random(n)` is not on trial — it is written down
/// and comes back the same, which is the property being kept — so the pattern
/// deliberately matches only the empty-argument form.
final Map<RegExp, String> kStepMustNotReachFor = <RegExp, String>{
  RegExp(r'\bRandom\(\s*\)'): 'an unseeded Random',
  RegExp(r'\bDateTime\.now\(\)'): 'the system clock',
  RegExp(r'\bStopwatch\('): 'a wall clock',
};

/// Whatever [source] reaches for that a step may not, or null.
String? unrepeatableIn(String source) {
  final code = codeOf(source);
  for (final entry in kStepMustNotReachFor.entries) {
    if (entry.key.hasMatch(code)) return entry.value;
  }
  return null;
}

// ------------------------------------------------------------------- reaching

/// Whether [source] imports or exports something naming [what].
bool reaches(String source, String what) => source.split('\n').any((String line) {
      final trimmed = line.trim();
      return (trimmed.startsWith('import ') || trimmed.startsWith('export ')) &&
          trimmed.contains(what);
    });

// --------------------------------------------------------------- self-checks

/// Proves every detector above fires, and stays quiet on what only looks alike.
///
/// Returns what is wrong with the *detectors*, which is a different list from
/// what is wrong with the repository — and the runner treats it differently:
/// a broken detector stops the run, because scans behind one mean nothing.
List<Finding> proveDetectorsWork() {
  final broken = <Finding>[];
  void fires(String what, bool condition, String source) {
    if (!condition) broken.add(Finding(what, 'did not fire on: $source'));
  }

  void quiet(String what, bool condition, String source, String why) {
    if (!condition) broken.add(Finding(what, 'fired on $source — $why'));
  }

  // The genre detector. The constant is the bug that was actually found; the
  // comment is what every previous attempt at a rule like this died of.
  fires('genre words', genreWordsIn('static const int oneWay = 1 << 6;').isNotEmpty,
      'oneWay');
  fires('genre words', genreWordsIn('int ammo = 0;').isNotEmpty, 'ammo');
  fires('genre words', genreWordsIn('double get lapTime => 0.0;').isNotEmpty,
      'lapTime');
  fires('genre words', genreWordsIn('bool stompedThisStep = false;').isNotEmpty,
      'stompedThisStep (inflected)');
  fires('genre words', genreWordsIn('int coins = 0;').isNotEmpty, 'coins');

  quiet('genre words', genreWordsIn('/// A monster is not our business.').isEmpty,
      'a doc comment', 'prose explaining the rule must not break it');
  quiet('genre words', genreWordsIn('// ammo, weapons: all elsewhere.').isEmpty,
      'a line comment', 'prose explaining the rule must not break it');
  quiet('genre words', genreWordsIn('/* a boss with a gun */ int x = 0;').isEmpty,
      'a block comment', 'prose explaining the rule must not break it');

  // The failure mode that kills detectors like this: three words that contain
  // `lap` and are not it. Three false positives in the first hour and the rule
  // is deleted.
  for (final innocent in <String>[
    'bool overlaps = true;',
    'double elapsed = 0.0;',
    'void collapse() {}',
    'final DriftEmitter drift = DriftEmitter();',
    'void dashboard() {}',
    'int coinage = 0;',
  ]) {
    quiet('genre words', genreWordsIn(innocent).isEmpty, innocent,
        'a word that merely contains a forbidden one is not that word');
  }

  // And the camel hump *is* a boundary, which is the other half of the claim.
  fires('genre words', genreWordsIn('int currentLap = 0;').isNotEmpty, 'currentLap');
  fires('genre words', genreWordsIn('void stomp() {}').isNotEmpty, 'stomp');

  // Shared mutables.
  fires('shared mutables',
      sharedMutablesIn('static final Vector3 up = Vector3(0.0, 1.0, 0.0);').isNotEmpty,
      'a static final Vector3');
  fires('shared mutables',
      sharedMutablesIn('static final Matrix4 identity = Matrix4.zero();').isNotEmpty,
      'a static final Matrix4');
  quiet('shared mutables',
      sharedMutablesIn('static Vector3 get up => Vector3(0.0, 1.0, 0.0);').isEmpty,
      'a getter', 'the fix must not be reported as the fault');
  quiet('shared mutables',
      sharedMutablesIn('final Vector3 position = Vector3.zero();').isEmpty,
      'an instance field', 'it is not shared with anybody');
  quiet('shared mutables',
      sharedMutablesIn('static const double gravity = -9.8;').isEmpty,
      'a const double', 'a number is not a value anybody scales');
  quiet('shared mutables',
      sharedMutablesIn('static final RegExp _key = RegExp(r"a");').isEmpty,
      'a compiled pattern', 'it is not a value anybody scales');

  // A repeatable step.
  fires('repeatable step', unrepeatableIn('final r = Random();') != null,
      'an unseeded Random');
  fires('repeatable step', unrepeatableIn('final t = DateTime.now();') != null,
      'DateTime.now()');
  fires('repeatable step', unrepeatableIn('final w = Stopwatch()..start();') != null,
      'a Stopwatch');
  quiet('repeatable step', unrepeatableIn('final r = Random(7);') == null,
      'a seeded Random', 'a seed is written down and comes back the same');
  quiet('repeatable step', unrepeatableIn('final r = GameRandom(1);') == null,
      'GameRandom(1)', 'the seeded generator is the fix, not the fault');
  quiet('repeatable step', unrepeatableIn('// Random() would be wrong here.') == null,
      'a comment', 'prose explaining the rule must not break it');

  // Reaching.
  fires('reaches', reaches("import 'package:flutter_gpu/gpu.dart';", 'flutter_gpu'),
      'an import');
  fires('reaches', reaches("export 'package:flutter_gpu/gpu.dart';", 'flutter_gpu'),
      'an export');
  quiet('reaches', !reaches('/// See flutter_gpu for the details.', 'flutter_gpu'),
      'a doc comment naming it', 'a mention is not an import');

  return broken;
}
