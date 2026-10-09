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

import 'api.dart';
import 'boundaries.dart';
import 'layers.dart';
import 'migration.dart';
import 'naming.dart';
import 'schema.dart';

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

/// Names another program chose, which this repository calls by them and
/// cannot rename, each exempt from [kGenreWords] whole and only whole.
///
///   * `reloadSources` is the service the flutter tool registers on a game's
///     VM service for a hot reload (`flutter3d_editor_play`'s `AttachedRun`
///     calls it, as DevTools does). Spelling it any other way is a call that
///     finds nothing; `reloadAll` of our own still fires.
///   * `shouldReload` is Flutter's `LocalizationsDelegate` member, which
///     `Flutter3dGameLocalizations.delegate` has to override by that name.
const Set<String> kProtocolNames = <String>{'reloadSources', 'shouldReload'};

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
    for (final match in _camel.allMatches(chunk)) match.group(0)!.toLowerCase(),
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

/// The source's prose: its comments, with the markers off and the wrap undone.
///
/// **The mirror of [codeOf], and the reason a rule can read Dart at all.** A
/// claim in a doc comment is wrapped wherever eighty columns fell, so
/// `thirty-one` and `goldens` are one sentence to a reader and two lines to a
/// regular expression — and a counting rule that reads the file as it is on
/// disk sees half the claims in the repository and misses the other half for no
/// reason it could ever explain.
///
/// A line that is not a comment ends the run rather than joining it, so the last
/// word of one comment and the first word of the next, three hundred lines
/// apart, never read as a phrase.
///
/// It takes `//` inside a string literal for a comment, which [codeOf] does from
/// the other side. Left alone: the counting rules read this for sentences about
/// how many of something there are, and no URL has ever been one.
String proseOf(String source) {
  final out = StringBuffer();
  var running = false;
  for (final line in source.split('\n')) {
    final match = _commentText.firstMatch(line);
    if (match == null) {
      if (running) out.write('\n');
      running = false;
      continue;
    }
    if (running) out.write(' ');
    out.write(match.group(1)!.trim());
    running = true;
  }
  return out.toString();
}

final RegExp _commentText = RegExp(r'//+ ?(.*)$');

// ------------------------------------------------------ who a member is for

/// Words for somebody this repository does not contain.
///
/// A public member nothing here calls exists for a caller outside, and the rule
/// that finds it cannot tell a sentence naming that caller from a sentence
/// restating the member's own name. This list is what it *can* tell: whether the
/// sentence names anybody at all.
///
/// **Stated so it is not mistaken for coverage.** A doc comment saying "the
/// caller must not hold this past the frame" passes on the word `caller` while
/// naming nobody. What the check buys is that the omission is visible — an
/// accessor with a one-line restatement of its own name is reported, every time,
/// which is the shape every member in the found set had.
const List<String> kOutsideCallerWords = <String>[
  'caller',
  'callers',
  'whoever',
  'anybody',
  'anyone',
  'a game',
  'a tool',
  'a level editor',
  'an editor',
  'an application',
  'a profiler',
  'a debugger',
  'a reader',
  'an embedder',
];

/// Whether [doc] names somebody outside this repository.
bool saysWhoReachesForIt(String doc) {
  final said = doc.toLowerCase();
  return kOutsideCallerWords.any(said.contains);
}

// ------------------------------------------------------------ public members

/// One member a class offers: its name, where it is, and what it says for itself.
typedef Member = ({String name, int line, String doc});

/// The declarations a member can be written as.
///
/// Indented on purpose — a member is inside something, and a top-level function
/// is a different question with a different answer. Ordered getter, setter,
/// method, field, because a getter's `get` would otherwise be read as a method's
/// return type.
final List<RegExp> _memberForms = <RegExp>[
  RegExp(
    r'''^\s+(?:external\s+)?(?:static\s+)?[\w<>,\s?\[\]$.]+?\s+get\s+([a-zA-Z]\w*)\s*(?:=>|\{)''',
  ),
  RegExp(r'^\s+(?:static\s+)?set\s+([a-zA-Z]\w*)\s*\('),
  RegExp(
    r'^\s+(?:external\s+)?(?:static\s+)?'
    r'(?:void|bool|int|double|String|num|Future<[^>]*>|List<[^>]*>|'
    r'Map<[^>]*>|Iterable<[^>]*>|[A-Z]\w*(?:<[^=;]*>)?\??)'
    r'\s+([a-z]\w*)\s*(?:<[\w,\s]+>)?\s*\(',
  ),
  RegExp(
    r'''^\s+(?:static\s+)?(?:late\s+)?(?:final|const)\s+[\w<>,\s?\[\]$.]+\s+([a-z]\w*)\s*(?:=|;)''',
  ),
];

/// Words that begin a line the way a declaration does and are not one.
const Set<String> _notAMemberName = <String>{
  'assert', 'await', 'case', 'const', 'else', 'factory', 'final', 'for', 'get',
  'if', 'late', 'new', 'operator', 'required', 'return', 'set', 'super',
  'switch', 'this', 'type', 'var', 'void', 'while', 'yield', //
};

/// Annotations that answer the question before it is asked.
///
/// `@override` is named by the thing it implements, so a rule about members
/// nothing names would report every one of them and mean nothing by it.
/// `@Deprecated` carries a sentence about who is still calling it and what to
/// call instead — which is the sentence, in the place the analyser reads.
const Set<String> _annotationsThatAnswer = <String>{'@override', '@Deprecated'};

/// Every public member [source] declares, with the doc comment above it.
///
/// The doc is the run of `///` lines immediately above, joined — which is the
/// sentence the reader sees, and the only thing a rule can ask about.
///
/// An annotation's argument list runs over several lines, and the run is
/// followed rather than parsed: any line between an `@` and the declaration
/// belongs to it. A blank line ends the run, because nothing in Dart puts one
/// inside an annotation and something eventually will put one above a member.
List<Member> publicMembersIn(String source) {
  final lines = source.split('\n');
  final found = <Member>[];
  final doc = <String>[];
  var annotating = false;
  var answered = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.startsWith('///')) {
      doc.add(trimmed.substring(3).trim());
      continue;
    }
    if (trimmed.startsWith('@')) {
      annotating = true;
      answered = answered || _annotationsThatAnswer.any(trimmed.startsWith);
      continue;
    }
    final name = _memberForms
        .map((RegExp form) => form.firstMatch(line)?.group(1))
        .firstWhere((String? it) => it != null, orElse: () => null);
    if (name == null) {
      if (annotating && trimmed.isNotEmpty) continue;
      doc.clear();
      annotating = false;
      answered = false;
      continue;
    }
    if (!answered && !name.startsWith('_') && !_notAMemberName.contains(name)) {
      found.add((name: name, line: i + 1, doc: doc.join(' ')));
    }
    doc.clear();
    annotating = false;
    answered = false;
  }
  return found;
}

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
    if (kProtocolNames.contains(match.group(0))) continue;
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

// ------------------------------------------------------------ a world's numbers

/// The numbers that belong to a world or to a substance, by what they are.
///
/// **A world's gravity, its air and its sea are read from the world**, and a
/// substance's density, viscosity and heat from its preset; a consumer that
/// writes one of these as a literal has a world of its own nobody can set.
/// Each pattern is the number with nothing glued to it — `19.81` and `9.812`
/// are other numbers — and only in code: a comment explaining why 9.81 is
/// what it is is the rule being kept.
///
/// `9.8` is ambiguous on its own — a fog ten metres away is `9.8` too — so it
/// counts only on a line that names gravity, which is where it is gravity.
/// The air's density to two or three figures (1.16 to 1.25, a fire's 1.18,
/// a handbook's 1.2) is as ambiguous, and counts only on a line that names a
/// density or declares a value called `air`.
final Map<RegExp, String> kWorldLiterals = <RegExp, String>{
  RegExp(r'(?<![\w.])9\.81(?![\d.])'): 'standard gravity',
  RegExp(r'(?<![\w.])9\.80665(?![\d.])'): 'standard gravity',
  RegExp(r'(?<![\w.])101325(?:\.0)?(?![\d.])'): 'the standard atmosphere',
  RegExp(r'(?<![\w.])101\.325(?![\d.])'): 'the standard atmosphere',
  RegExp(r'(?<![\w.])293\.15(?![\d.])'): 'the air of a room',
  RegExp(r'(?<![\w.])288\.15(?![\d.])'): 'the standard atmosphere',
  RegExp(r'(?<![\w.])1\.204(?![\d.])'): 'the air of a room',
  RegExp(r'(?<![\w.])1\.225(?![\d.])'): 'the standard atmosphere',
  RegExp(r'(?<![\w.])1025\.0(?![\d.])'): 'the sea',
  RegExp(r'(?<![\w.])343\.0(?![\d.])'): 'sound in the air of a room',
};

final RegExp _looseGravity = RegExp(r'(?<![\w.])9\.8(?![\d.])');
final RegExp _namesGravity = RegExp('gravity', caseSensitive: false);
final RegExp _looseAirDensity = RegExp(
  r'(?<![\w.])1\.(?:1[6-9]|2[0-5]?)(?![\d.])',
);
final RegExp _namesAirDensity = RegExp(
  r'density|\b(?:const|final|var|double)\s+(?:double\s+)?_?air\b',
  caseSensitive: false,
);

/// **A gravity written as a default, by any number.** Not only 9.81: a
/// dynamics that fell at 22, a character tuned at 24 and a car at 20 were
/// three worlds in one game, each with a number nobody could set from a
/// level (decision 1 of `tasks/1.0-physics-audit.md`). So a gravity-named
/// value given a number — `this.gravity = 24.0`, `gravity: 20.0`,
/// `runGravity = 24.0` — and a down vector on a line that names gravity —
/// `Vector3(0.0, -22.0, 0.0)` — count, whatever the number. Nought does not:
/// "no gravity" is a switch, not a world.
final RegExp _gravityDefault = RegExp(
  r'\b\w*[Gg]ravity\b\s*(?:=(?![=>])|:)\s*(-?\d+(?:\.\d+)?)(?![\d.\w])',
);
final RegExp _downVector = RegExp(
  r'Vector3\(\s*0(?:\.0)?\s*,\s*-\s*(\d+(?:\.\d+)?)\s*,\s*0(?:\.0)?\s*\)',
);

/// **A buoyancy as an acceleration.** A swimmer lifted at 6 m/s² rises on
/// the Moon, where 6 is more than gravity. A buoyancy is a share of the
/// world's g, or comes from the densities; a number of two or more given
/// to one is an acceleration of its own.
final RegExp _absoluteBuoyancy = RegExp(
  r'\b\w*[Bb]uoyancy\b\s*(?:=(?![=>])|:)\s*(\d+(?:\.\d+)?)(?![\d.\w])',
);

/// **A spark that falls like a stone falls by the world.** A particle's
/// gravity of eight or more downward is a ballistic fall — shrapnel, spray,
/// a thrown droplet — and is `ParticleGravity()`, the world's; a smaller one
/// is a drift that only looks like falling (smoke, embers, dust), which the
/// effect's author may tune freely.
final RegExp _ballisticParticles = RegExp(
  r'ParticleGravity\(\s*-\s*(\d+(?:\.\d+)?)\s*\)',
);

/// Every world's or substance's number [source] writes in code, as the
/// literal, the line it is on and what it is.
List<({String literal, int line, String what})> worldLiteralsIn(String source) {
  final lines = codeOf(source).split('\n');
  bool nonzero(String number) => double.parse(number) != 0.0;
  return <({String literal, int line, String what})>[
    for (
      var i = 0;
      i < lines.length;
      i++
    ) ...<({String literal, int line, String what})>[
      for (final entry in kWorldLiterals.entries)
        for (final match in entry.key.allMatches(lines[i]))
          (literal: match.group(0)!, line: i + 1, what: entry.value),
      if (_namesGravity.hasMatch(lines[i]))
        for (final match in _looseGravity.allMatches(lines[i]))
          (literal: match.group(0)!, line: i + 1, what: 'gravity'),
      if (_namesAirDensity.hasMatch(lines[i]))
        for (final match in _looseAirDensity.allMatches(lines[i]))
          (literal: match.group(0)!, line: i + 1, what: 'the air\'s density'),
      for (final match in _gravityDefault.allMatches(lines[i]))
        if (nonzero(match.group(1)!) &&
            !kWorldLiterals.keys.any(
              (RegExp known) => known.hasMatch(match.group(1)!),
            ) &&
            !_looseGravity.hasMatch(match.group(1)!))
          (literal: match.group(1)!, line: i + 1, what: 'a gravity of its own'),
      if (_namesGravity.hasMatch(lines[i]))
        for (final match in _downVector.allMatches(lines[i]))
          if (nonzero(match.group(1)!) &&
              !_looseGravity.hasMatch(match.group(1)!) &&
              !kWorldLiterals.keys.any(
                (RegExp known) => known.hasMatch(match.group(1)!),
              ) &&
              !_gravityDefault.hasMatch(lines[i]))
            (
              literal: match.group(1)!,
              line: i + 1,
              what: 'a gravity of its own',
            ),
      for (final match in _absoluteBuoyancy.allMatches(lines[i]))
        if (double.parse(match.group(1)!) >= 2.0)
          (
            literal: match.group(1)!,
            line: i + 1,
            what: 'a buoyancy as an acceleration of its own',
          ),
      for (final match in _ballisticParticles.allMatches(lines[i]))
        if (double.parse(match.group(1)!) >= 8.0)
          (
            literal: match.group(1)!,
            line: i + 1,
            what: 'a particle falling by a gravity of its own',
          ),
    ],
  ];
}

// --------------------------------------------- the core's copies of a number

/// What a `#define` in the C core may not be, outside the header generated
/// from the catalogue (`csrc/src/f3d_materials.g.h`).
///
/// **The core reads a substance's number, nature's constant and the standard
/// world from the generated header**, so a `#define` of its own for one is a
/// second copy that drifts — as water's specific heat did, 4186 in the heat
/// model against 4182 everywhere else. Two ways to be one:
///
/// * a name that says it is the world's or water's or air's —
///   `…WATER…`, `…AIR_…`, `…SEAWATER…`, `…STEFAN…`, `…GAS_CONSTANT…`,
///   `…GRAVITY…`, `…ATMOSPHERE…` — whatever its number, since a different
///   number under that name is the worst case;
/// * Stefan–Boltzmann's value under any name.
///
/// A material's own name (`…WOOD…`) with the catalogue's number for it is
/// the third, which needs the catalogue and is [cDefinesCopyingMaterialsIn].
final RegExp _cDefine = RegExp(
  r'^\s*#\s*define\s+(\w+)\s+F3D_R\(\s*([-+0-9.eE]+)\s*\)',
  multiLine: true,
);
final RegExp _worldWord = RegExp(
  r'WATER|(?:^|_)AIR_|SEAWATER|STEFAN|GAS_CONSTANT|GRAVITY|ATMOSPHERE',
);

/// Every `#define` in [source] that copies a world's, water's, air's or
/// nature's number: the name and the line.
List<({String name, int line})> cDefinesCopyingTheWorldIn(String source) {
  final code = codeOf(source);
  return <({String name, int line})>[
    for (final match in _cDefine.allMatches(code))
      if (_worldWord.hasMatch(match.group(1)!) ||
          (double.tryParse(match.group(2)!) ?? 0.0) == 5.670374419e-8)
        (
          name: match.group(1)!,
          line: '\n'.allMatches(code.substring(0, match.start)).length + 1,
        ),
  ];
}

/// Every `#define` in [source] whose name has one of [materials]' names in
/// it (upper snake case, `WOOD`, `OLIVE_OIL`) and whose number is one of
/// that material's in [values]: the name and the line.
List<({String name, int line})> cDefinesCopyingMaterialsIn(
  String source, {
  required Map<String, Set<double>> values,
}) {
  final code = codeOf(source);
  return <({String name, int line})>[
    for (final match in _cDefine.allMatches(code))
      for (final MapEntry(key: material, value: numbers) in values.entries)
        if (RegExp('(?:^|_)$material(?:_|\$)').hasMatch(match.group(1)!) &&
            numbers.contains(double.tryParse(match.group(2)!)))
          (
            name: match.group(1)!,
            line: '\n'.allMatches(code.substring(0, match.start)).length + 1,
          ),
  ];
}

/// The numbers the generated header gives each built-in material, by the
/// material's upper-snake name: `F3D_MAT_WOOD_RADIANT_FRACTION F3D_R(0.3)`
/// is 0.3 under `WOOD`. Read from the header's own text, so the rule needs
/// no Dart of the catalogue's.
Map<String, Set<double>> materialValuesIn(String header, Set<String> names) {
  final found = <String, Set<double>>{};
  for (final match in _cDefine.allMatches(header)) {
    final name = match.group(1)!;
    if (!name.startsWith('F3D_MAT_')) continue;
    final rest = name.substring('F3D_MAT_'.length);
    // The longest material name the define starts with: OLIVE_OIL before OIL.
    final material =
        (names.where((String n) => rest.startsWith('${n}_')).toList()
              ..sort((String a, String b) => b.length.compareTo(a.length)))
            .firstOrNull;
    final value = double.tryParse(match.group(2)!);
    if (material == null || value == null) continue;
    (found[material] ??= <double>{}).add(value);
  }
  return found;
}

/// The built-in materials' upper-snake names in [header]'s
/// `/* f3d.<name>: … */` lines: `f3d.oliveOil` is `OLIVE_OIL`.
Set<String> materialNamesIn(String header) => <String>{
  for (final match in RegExp(r'/\* f3d\.(\w+):').allMatches(header))
    match
        .group(1)!
        .replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (Match m) => '${m[1]}_${m[2]}',
        )
        .toUpperCase(),
};

// ---------------------------------------------------------- a light's number

/// Below this, a light's intensity written as a literal reads as the
/// renderer's pre-1.0 unit (one of which is about 5 790 lux) rather than the
/// lux or candela it has been since 1.0. In lux or candela.
///
/// Fifty is a candle's worth of candela at most and a deep dusk in lux: a
/// light meant to be that dim is rare enough to say so, and every pre-1.0
/// number a scene was lit with, 0.1 to 20, is below it.
const double kSmallestLightIntensity = 50.0;

final RegExp _lightConstructor = RegExp(
  r'\b(?:LightNode|Light3D|ModelLight)(?:\.\w+)?\s*\(',
);
final RegExp _intensityArgument = RegExp(
  r'\bintensity:\s*(\d[\d_]*(?:\.\d+)?(?:[eE]-?\d+)?)(?=\s*[,)\n])',
);
final RegExp _intensitySetter = RegExp(
  r'\.intensity\s*=\s*(\d[\d_]*(?:\.\d+)?(?:[eE]-?\d+)?)\s*;',
);
final RegExp _namesLightUnit = RegExp(
  r'//.*\b(?:lux|candela|cd)\b',
  caseSensitive: false,
);

/// Every light intensity [source] writes as a literal below
/// [kSmallestLightIntensity], with the line it is on.
///
/// **What counts as a light's intensity:** an `intensity:` argument inside a
/// `LightNode`, `Light3D` or `ModelLight` constructor call, and an
/// `.intensity = <number>;` assignment, which in this repository is a light's
/// (a bloom's or a probe's intensity is a settings field, set through a
/// constructor). Nought is a light switched off, and a literal times
/// something (`2.5 * Photometric.legacyUnit`) is a conversion, not a number
/// in the wrong unit; neither counts.
///
/// **A literal whose line, or the line above, has a comment naming lux,
/// candela or cd is annotated** and kept: a light meant to be that dim says in
/// what unit it is that dim.
List<({String literal, int line})> smallLightIntensitiesIn(String source) {
  final raw = source.split('\n');
  final code = codeOf(source);
  bool annotated(int line) =>
      _namesLightUnit.hasMatch(raw[line - 1]) ||
      (line >= 2 && _namesLightUnit.hasMatch(raw[line - 2]));
  int lineAt(int offset) =>
      '\n'.allMatches(code.substring(0, offset)).length + 1;
  bool small(String literal) {
    final value = double.tryParse(literal.replaceAll('_', ''));
    return value != null && value > 0.0 && value < kSmallestLightIntensity;
  }

  final hits = <int, String>{};
  for (final call in _lightConstructor.allMatches(code)) {
    // The call's own parentheses: from the one the match ends on to the one
    // that closes it, so a nested call's `intensity:` is the nested call's.
    var depth = 0;
    var end = call.end - 1;
    for (; end < code.length; end++) {
      final c = code[end];
      if (c == '(') depth++;
      if (c == ')' && --depth == 0) break;
    }
    // With the closing parenthesis, which ends the last argument.
    final span = code.substring(call.end, end < code.length ? end + 1 : end);
    for (final argument in _intensityArgument.allMatches(span)) {
      final literal = argument.group(1)!;
      if (small(literal)) hits[call.end + argument.start] = literal;
    }
  }
  for (final setter in _intensitySetter.allMatches(code)) {
    final literal = setter.group(1)!;
    if (small(literal)) hits[setter.start] = literal;
  }
  return <({String literal, int line})>[
    for (final entry in hits.entries)
      if (!annotated(lineAt(entry.key)))
        (literal: entry.value, line: lineAt(entry.key)),
  ];
}

/// The Dart in [markdown]'s fenced code blocks, with every other line blank,
/// so that a line number in the result is the line in the file.
String dartBlocksOf(String markdown) {
  final out = <String>[];
  var inside = false;
  for (final line in markdown.split('\n')) {
    final fence = line.trimLeft().startsWith('```');
    if (fence) {
      inside = !inside && line.trimLeft().startsWith('```dart');
      out.add('');
      continue;
    }
    out.add(inside ? line : '');
  }
  return out.join('\n');
}

// ------------------------------------------------------------- pubspec depends

/// Every package [pubspec] depends on, run-time and dev alike.
///
/// **Dev dependencies count, and that is the point of reading them.** A plain
/// Dart package is one a program with no Flutter SDK can resolve, and `dart
/// test` resolves the dev list too — so a `flutter_test` under
/// `dev_dependencies` is a package whose own suite cannot be run by the
/// machines it was extracted for. That is where the Flutter SDK comes back in
/// through a door nobody looked at: an import scan reads `lib/`, and this
/// arrives in a pubspec.
///
/// A line scanner rather than a YAML parser: the only shape that matters here
/// is `  name:` two spaces in under a `dependencies:` heading, and a
/// dependency on the SDK is `flutter` or `flutter_test` by name, which is what
/// [dependsOnFlutterSdk] reads out of the result.
Set<String> pubspecDependencies(String pubspec) {
  final found = <String>{};
  var inside = false;
  for (final line in pubspec.split('\n')) {
    if (line.startsWith('dependencies:') ||
        line.startsWith('dev_dependencies:')) {
      inside = true;
      continue;
    }
    // Any other column-zero key ends the section — `environment:`, `topics:`,
    // `flutter:` with the asset block under it.
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      inside = false;
      continue;
    }
    if (!inside) continue;
    final match = RegExp(r'^  ([a-z_][a-z_0-9]*):').firstMatch(line);
    if (match != null) found.add(match.group(1)!);
  }
  return found;
}

/// The packages one section of [pubspec] names: `dependencies` (what the
/// package needs at run time) or `dev_dependencies` (what its tests and
/// tools need), each alone, where [pubspecDependencies] takes both.
Set<String> pubspecSection(String pubspec, String section) {
  final found = <String>{};
  var inside = false;
  for (final line in pubspec.split('\n')) {
    if (line.startsWith('$section:')) {
      inside = true;
      continue;
    }
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      inside = false;
      continue;
    }
    if (!inside) continue;
    final match = RegExp(r'^  ([a-z_][a-z_0-9]*):').firstMatch(line);
    if (match != null) found.add(match.group(1)!);
  }
  return found;
}

/// One step of the publishing order: the packages it names, in the order
/// they are published, and whether the step is published at all (the last
/// one, the repository's own content, is not).
typedef PublishingLayer = ({List<String> names, bool published});

/// The steps of the numbered list in [block], each the packages its item
/// names in code, continuation lines included. An item saying "Not
/// published" is the packages that never go to pub.dev.
List<PublishingLayer> publishingLayers(String block) {
  final layers = <PublishingLayer>[];
  final names = RegExp('`([a-z0-9_]+)`');
  for (final line in block.split('\n')) {
    final starts = RegExp(r'^\s*\d+\.').hasMatch(line);
    if (starts) {
      layers.add((
        names: <String>[],
        published: !line.contains('Not published'),
      ));
    }
    if (layers.isEmpty) continue;
    layers.last.names.addAll(
      names.allMatches(line).map((Match m) => m.group(1)!),
    );
  }
  return layers;
}

/// What is wrong with [layers] as an order to publish [graph] in, one
/// sentence each: the runtime and dev dependencies of every package,
/// siblings only.
///
/// **A package goes in a later step than everything it needs at run time**,
/// because `pub publish` resolves its constraints against pub.dev, and a
/// sibling that is not there yet at `^1.0.0-rc.1` fails it. **A dev
/// dependency comes earlier in the order too**, because pana resolves dev
/// dependencies when it scores the upload; one published later is allowed
/// only with its reason in [devAllowed] (`'<package> -> <dependency>'`),
/// and an entry there that no longer inverts is reported, so the list only
/// holds what is true. Nothing published may depend on a package that is
/// not, even as a dev dependency.
List<String> publishingOrderBreaks(
  List<PublishingLayer> layers,
  Map<String, ({Set<String> runtime, Set<String> dev})> graph,
  Map<String, String> devAllowed,
) {
  final step = <String, int>{};
  final position = <String, int>{};
  final unpublished = <String>{};
  for (final (index, layer) in layers.indexed) {
    for (final name in layer.names) {
      step[name] = index;
      position[name] = position.length;
      if (!layer.published) unpublished.add(name);
    }
  }
  final out = <String>[];
  final inverted = <String>{};
  for (final MapEntry(key: name, value: deps) in graph.entries) {
    final at = step[name];
    if (at == null || unpublished.contains(name)) continue;
    for (final need in deps.runtime.toList()..sort()) {
      final there = step[need];
      if (there == null) continue;
      if (unpublished.contains(need)) {
        out.add('$name depends on $need, which is not published');
      } else if (there >= at) {
        out.add(
          '$name is in step ${at + 1} and needs $need at run time, which is '
          'in step ${there + 1}: it goes after',
        );
      }
    }
    for (final need in deps.dev.toList()..sort()) {
      final there = position[need];
      if (there == null) continue;
      if (unpublished.contains(need)) {
        out.add(
          '$name has a dev dependency on $need, which is not published: pana '
          'resolves dev dependencies against pub.dev',
        );
      } else if (there > position[name]!) {
        final key = '$name -> $need';
        inverted.add(key);
        if (!devAllowed.containsKey(key)) {
          out.add(
            '$name has a dev dependency on $need, published after it: move '
            'it, or say why in `devDependencyPublishedLater`',
          );
        }
      }
    }
  }
  for (final key in devAllowed.keys.toList()..sort()) {
    if (!inverted.contains(key)) {
      out.add(
        '`devDependencyPublishedLater` names $key, which the order no longer '
        'inverts: take it out',
      );
    }
  }
  return out;
}

/// Whether [pubspec] asks for the Flutter SDK itself.
bool dependsOnFlutterSdk(String pubspec) {
  final names = pubspecDependencies(pubspec);
  return names.contains('flutter') || names.contains('flutter_test');
}

/// The platforms [pubspec] declares in its top-level `platforms:` block, or
/// null when it has none.
///
/// **Top level only.** A plugin also lists platforms under `flutter: plugin:`,
/// indented, and that list says where native code is registered rather than
/// where the package runs: `pad_input` reaches the browser's Gamepad API from
/// Dart and has no plugin entry for the web. Reading the nested list would
/// call its `platforms:` declared when it was not.
Set<String>? declaredPlatforms(String pubspec) {
  final block = RegExp(
    r'^platforms:[ \t]*\n((?:[ \t]+[a-z]+:[^\n]*\n?)*)',
    multiLine: true,
  ).firstMatch(pubspec);
  if (block == null) return null;
  return <String>{
    for (final line in RegExp(
      r'^[ \t]+([a-z]+):',
      multiLine: true,
    ).allMatches(block.group(1)!))
      line.group(1)!,
  };
}

/// The names pub.dev accepts under `platforms:`.
const Set<String> knownPlatforms = <String>{
  'android',
  'ios',
  'linux',
  'macos',
  'web',
  'windows',
};

/// The plugins a pubspec's `flutter3d_plugins:` marker names, each as
/// `<import>#<Class>` the way discovery reads it, or null when there is no
/// marker. The marker of before 1.0, `flutter3d: plugin:`, is read the same
/// way, as discovery still reads it; [usesLegacyPluginMarker] says which.
///
/// **The three forms discovery takes**, read without a YAML parser: one
/// entry, a list of entries, or a map from a library to the class or the
/// classes it declares, in flow (`[A, B]`) or block style. Only under the
/// top-level keys: Flutter's own `flutter: plugin:` block names platforms
/// and native classes, and reading it would call every native plugin a
/// flutter3d one.
List<String>? pluginMarkerEntries(String pubspec) {
  final lines = pubspec.split('\n');
  int keyAt(String key) =>
      lines.indexWhere((String l) => RegExp('^$key:\\s*(#.*)?\$').hasMatch(l));
  final current = keyAt('flutter3d_plugins');
  final top = current >= 0 ? current : keyAt('flutter3d');
  if (top < 0) return null;
  for (var i = top + 1; i < lines.length; i++) {
    final line = lines[i];
    if (_blankYaml(line)) continue;
    if (!line.startsWith(' ')) return null;
    final head = RegExp(r'^  plugin:(.*)$').firstMatch(line);
    if (head == null) continue;
    return _markerValue(lines, i, head.group(1)!, '    ');
  }
  return null;
}

/// Whether [pubspec] marks its plugins with the key of before 1.0,
/// `flutter3d: plugin:`, and not with `flutter3d_plugins:` (decision D of
/// `tasks/1.0-arch-review.md`).
bool usesLegacyPluginMarker(String pubspec) =>
    !RegExp(r'^flutter3d_plugins:', multiLine: true).hasMatch(pubspec) &&
    pluginMarkerEntries(pubspec) != null;

bool _blankYaml(String l) => l.trim().isEmpty || l.trimLeft().startsWith('#');

String _cleanYaml(String v) {
  final hash = v.indexOf(' #');
  final bare = (hash < 0 ? v : v.substring(0, hash)).trim();
  return bare.length >= 2 &&
          (bare.startsWith("'") && bare.endsWith("'") ||
              bare.startsWith('"') && bare.endsWith('"'))
      ? bare.substring(1, bare.length - 1)
      : bare;
}

/// A marker's value: [rest] when the key's own line holds it, otherwise the
/// block after line [at], whose entries are indented by [indent].
List<String> _markerValue(
  List<String> lines,
  int at,
  String rest,
  String indent,
) {
  final inline = _cleanYaml(rest);
  if (inline.isNotEmpty) return <String>[inline];
  final out = <String>[];
  String? library;
  final item = RegExp('^$indent- (.+)\$');
  final key = RegExp('^$indent(\\S+):(?:\\s+(.*))?\$');
  final nested = RegExp('^$indent  - (.+)\$');
  for (var j = at + 1; j < lines.length; j++) {
    final l = lines[j];
    if (_blankYaml(l)) continue;
    if (!l.startsWith(indent)) break;
    final isItem = item.firstMatch(l);
    final isKey = key.firstMatch(l);
    final isNested = nested.firstMatch(l);
    if (isItem != null) {
      out.add(_cleanYaml(isItem.group(1)!));
    } else if (isKey != null) {
      library = _cleanYaml(isKey.group(1)!);
      final value = _cleanYaml(isKey.group(2) ?? '');
      if (value.startsWith('[') && value.endsWith(']')) {
        for (final c in value.substring(1, value.length - 1).split(',')) {
          if (_cleanYaml(c).isNotEmpty) out.add('$library#${_cleanYaml(c)}');
        }
      } else if (value.isNotEmpty) {
        out.add('$library#$value');
      }
    } else if (isNested != null && library != null) {
      out.add('$library#${_cleanYaml(isNested.group(1)!)}');
    }
  }
  return out;
}

/// Whether [source] declares a class that implements `GraphicsDevice`, which
/// is what makes a package a backend. The declaration may span lines, as
/// `CpuDevice`'s `with` clause makes it.
bool implementsGraphicsDevice(String source) => RegExp(
  r'^(?:[a-z]+ )*class \w+[^{;]*?\bimplements\b[^{;]*?\bGraphicsDevice\b(?!\w)',
  multiLine: true,
).hasMatch(source);

/// The rows of a Markdown table whose first cell is a package name in code,
/// as `package → the set its second cell lists`, comma separated.
Map<String, Set<String>> packagePlatformRows(String markdown) =>
    <String, Set<String>>{
      for (final row in RegExp(
        r'^\| `([a-z_0-9]+)` \| ([a-z, ]*) \|[ \t]*$',
        multiLine: true,
      ).allMatches(markdown))
        row.group(1)!: <String>{
          for (final name in row.group(2)!.split(','))
            if (name.trim().isNotEmpty) name.trim(),
        },
    };

// ------------------------------------------------------------------- reaching

/// Whether [source] imports or exports something naming [what].
bool reaches(String source, String what) =>
    source.split('\n').any((String line) {
      final trimmed = line.trim();
      return (trimmed.startsWith('import ') || trimmed.startsWith('export ')) &&
          trimmed.contains(what);
    });

/// The packages whose `lib/src/` [source] imports or exports, other than
/// [own]: a reach past another package's public libraries, which no
/// version constraint can make safe, since `src/` is not in its API.
Set<String> foreignSrcImports(String source, String own) => <String>{
  for (final match in RegExp(
    r'''^\s*(?:import|export)\s+['"]package:(\w+)/src/''',
    multiLine: true,
  ).allMatches(source))
    if (match.group(1) != own) match.group(1)!,
};

// ---------------------------------------------------- the published boundary

/// A top-level `enum Name` declaration, by name.
final RegExp enumDeclaration = RegExp(r'^enum (\w+)', multiLine: true);

/// Every top-level enum [source] declares.
///
/// **A `sealed`/`final class` never matches, and that is the point rather
/// than an oversight.** `qa-06`'s own alternative to an enum a published
/// package cannot close — `LightingModel`'s own shape, a `final class` with
/// `static const` instances, or a `sealed`/`abstract base class` hierarchy —
/// is closed by something other than an enum's own fixed value list, so a
/// scan built on this regex has nothing in either shape to find. The rule
/// this feeds never has to special-case "unless it is sealed": it is simply
/// never asked about one.
List<String> enumDeclarationsIn(String source) => <String>[
  for (final match in enumDeclaration.allMatches(source)) match.group(1)!,
];

/// [source]'s own enum declarations that [exempt] does not name.
///
/// The published-boundary rule's whole question in one function: every name
/// in [exempt] is a `boundaryEnumExempt` entry — a reviewed, one-sentence
/// reason a fourth value would be machinery rather than a game's own content
/// — and everything else [enumDeclarationsIn] finds is a promise nobody has
/// looked at yet.
List<String> unexemptedEnumsIn(String source, Set<String> exempt) => <String>[
  for (final name in enumDeclarationsIn(source))
    if (!exempt.contains(name)) name,
];

/// The subcommands (`== convert ==`) and flags (`--dry-run`) a CLI surface
/// snapshot names, as `convert` and `convert --dry-run`.
Set<String> cliSurfaceWords(String surface) {
  final words = <String>{};
  var command = 'flutter3d';
  for (final line in surface.split('\n')) {
    final heading = RegExp(r'^== (\S+) ==$').firstMatch(line);
    if (heading != null) {
      command = heading[1]!;
      words.add(command);
      continue;
    }
    for (final flag in RegExp(
      r'(?<![\w-])--[a-z][a-z0-9-]*',
    ).allMatches(line)) {
      words.add('$command ${flag[0]}');
    }
  }
  return words;
}

/// A format as its `FormatSpec` declaration in the source says it: the id,
/// the version it writes (resolved when it names a constant of the same
/// file), the oldest it reads, the fixture pattern from the package root,
/// and which constant the version came from, if any.
typedef DeclaredFormat = ({
  String id,
  int? version,
  String? versionConstant,
  int since,
  String? fixture,
});

/// Every `FormatSpec(...)` [source] declares: the registry as the code says
/// it, read without running anything.
///
/// **What the format-fixture rule reads**, rather than guessing a format from
/// the name of an `int` constant. A format is what declares itself one, with
/// its id and its fixture beside the reader; the name pattern missed
/// `FrameCapture.fileVersion` and every format whose constant was not
/// spelled `formatVersion`.
List<DeclaredFormat> formatSpecsIn(String source) {
  final code = codeOf(source);
  final constants = <String, int>{
    for (final m in RegExp(
      r'\bconst\s+int\s+(\w+)\s*=\s*(\d+)\s*;',
    ).allMatches(code))
      m[1]!: int.parse(m[2]!),
  };
  final strings = <String, String>{
    for (final m in RegExp(
      r'''\bconst\s+String\s+(\w+)\s*=\s*['"]([^'"]*)['"]\s*;''',
    ).allMatches(code))
      m[1]!: m[2]!,
  };
  final found = <DeclaredFormat>[];
  for (final start in RegExp(r'\bFormatSpec\s*\(').allMatches(code)) {
    // The argument list, to its closing parenthesis.
    var depth = 0;
    var end = start.end - 1;
    for (; end < code.length; end++) {
      final c = code[end];
      if (c == '(') depth++;
      if (c == ')' && --depth == 0) break;
    }
    final args = code.substring(start.end, end);
    String? named(String name) =>
        RegExp('\\b$name\\s*:\\s*([^,\\n)]+)').firstMatch(args)?[1]?.trim();
    String? text(String name) => switch (named(name)) {
      final String v when v.length >= 2 && "'\"".contains(v[0]) => v.substring(
        1,
        v.length - 1,
      ),
      _ => null,
    };
    // An id written as a constant of the same file is resolved; one this
    // cannot resolve is still a format, named by its expression.
    final id =
        text('id') ??
        switch (named('id')) {
          final String ref => strings[ref.split('.').last] ?? ref,
          null => null,
        };
    if (id == null) continue;
    final versionText = named('version');
    final literal = int.tryParse(versionText ?? '');
    final constant = literal == null && versionText != null
        ? versionText.split('.').last
        : null;
    found.add((
      id: id,
      version: literal ?? constants[constant],
      versionConstant: constant,
      since: int.tryParse(named('since') ?? '') ?? 1,
      fixture: text('fixture'),
    ));
  }
  return found;
}

/// An `int` constant that numbers a file format's version: `formatVersion`,
/// `sectionVersion`, `fileVersion`, or a top-level `k…Version`. The net
/// under [formatSpecsIn]: a constant like this that no `FormatSpec` names
/// and no table lists is a format nobody declared.
final RegExp _formatVersionConstant = RegExp(
  r'\bconst\s+int\s+(formatVersion|sectionVersion|fileVersion|'
  r'(?![a-z]*Abi|abi|api|engine|genre|base|\w*Schema)[a-z]\w*[a-z0-9]Version)\s*=\s*'
  r'(\d+)\s*;',
);

/// Every format version constant [source] declares, by name, with its value.
///
/// Read from the code alone, so a comment that quotes the old number while
/// explaining a bump is not taken for the constant.
Map<String, int> formatVersionsIn(String source) => <String, int>{
  for (final match in _formatVersionConstant.allMatches(codeOf(source)))
    match.group(1)!: int.parse(match.group(2)!),
};

/// A version read from a file, compared for equality with the version this
/// build writes: `version != formatVersion`, `said != f3dVersion`. Since
/// 1.0 the constants are lowerCamelCase (`f3dVersion`, was `kF3dVersion`),
/// so the names that are not a file's version are left out by name: an ABI
/// number, an API or a genre version compared for compatibility, the
/// engine's own simulation version and a schema's.
final RegExp _exactVersionGate = RegExp(
  r'\b\w+\s*!=\s*(?:\w+\.)?(formatVersion|sectionVersion|'
  r'(?![a-z]*Abi|abi|api|engine|genre|base|\w*Schema)[a-z]\w*[a-z0-9]Version)\b',
);

/// The 1-based lines of [source] that gate a read on the exact version —
/// decision 8 of `tasks/1.0-stability.md` reads every older version, so an
/// equality there refuses every file the previous release wrote.
List<int> exactVersionGatesIn(String source) => <int>[
  for (final (index, line) in codeOf(source).split('\n').indexed)
    if (_exactVersionGate.hasMatch(line)) index + 1,
];

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
  fires(
    'genre words',
    genreWordsIn('static const int oneWay = 1 << 6;').isNotEmpty,
    'oneWay',
  );
  fires('genre words', genreWordsIn('int ammo = 0;').isNotEmpty, 'ammo');
  fires(
    'genre words',
    genreWordsIn('double get lapTime => 0.0;').isNotEmpty,
    'lapTime',
  );
  fires(
    'genre words',
    genreWordsIn('bool stompedThisStep = false;').isNotEmpty,
    'stompedThisStep (inflected)',
  );
  fires('genre words', genreWordsIn('int coins = 0;').isNotEmpty, 'coins');

  quiet(
    'genre words',
    genreWordsIn('/// A monster is not our business.').isEmpty,
    'a doc comment',
    'prose explaining the rule must not break it',
  );
  quiet(
    'genre words',
    genreWordsIn('// ammo, weapons: all elsewhere.').isEmpty,
    'a line comment',
    'prose explaining the rule must not break it',
  );
  quiet(
    'genre words',
    genreWordsIn("const swapService = 'reloadSources';").isEmpty,
    'a protocol method name',
    'a name another program chose is called by its name',
  );
  fires(
    'genre words',
    genreWordsIn('Future<void> reloadAll() async {}').isNotEmpty,
    'reloadAll (one of ours)',
  );
  quiet(
    'genre words',
    genreWordsIn('/* a boss with a gun */ int x = 0;').isEmpty,
    'a block comment',
    'prose explaining the rule must not break it',
  );

  // **The words a modeller is made of, and the six it must spell differently.**
  // A tool for editing meshes writes `dashedLine`, `reload`, `spike` and
  // `boss` without meaning a platformer, a weapon, a hazard or a monster — and
  // every one of those fires, correctly, because the scan reads words and not
  // intent. CONTRIBUTING.md carries the replacements; these are what keep the
  // table and the detector from drifting apart.
  fires(
    'genre words',
    genreWordsIn('void dashedLine() {}').isNotEmpty,
    'dashed',
  );
  fires('genre words', genreWordsIn('void reload() {}').isNotEmpty, 'reload');
  fires('genre words', genreWordsIn('int spikeCount = 0;').isNotEmpty, 'spike');
  fires('genre words', genreWordsIn('Node? boss;').isNotEmpty, 'boss');
  for (final replacement in <String>[
    'void dottedLine() {}',
    'void reopen() {}',
    'int peakCount = 0;',
    'Node? owner;',
  ]) {
    quiet(
      'genre words',
      genreWordsIn(replacement).isEmpty,
      replacement,
      'the word CONTRIBUTING.md sends a writer to must itself be clean',
    );
  }

  // The vocabulary of the modeller that is *not* a genre's, checked because a
  // scan that fired on `bevelWidth` would be switched off by the second file.
  for (final innocent in <String>[
    'double bevelWidth = 0.02;',
    'void edgeLoop() {}',
    'int faceCount = 0;',
    'Brush brush = Brush.smooth;',
    'int boneIndex = 0;',
    'bool manifold = true;',
  ]) {
    quiet(
      'genre words',
      genreWordsIn(innocent).isEmpty,
      innocent,
      'a mesh has faces, loops, bevels, bones and brushes, and none of them '
          'is a genre',
    );
  }

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
    quiet(
      'genre words',
      genreWordsIn(innocent).isEmpty,
      innocent,
      'a word that merely contains a forbidden one is not that word',
    );
  }

  // And the camel hump *is* a boundary, which is the other half of the claim.
  fires(
    'genre words',
    genreWordsIn('int currentLap = 0;').isNotEmpty,
    'currentLap',
  );
  fires('genre words', genreWordsIn('void stomp() {}').isNotEmpty, 'stomp');

  // Shared mutables.
  fires(
    'shared mutables',
    sharedMutablesIn(
      'static final Vector3 up = Vector3(0.0, 1.0, 0.0);',
    ).isNotEmpty,
    'a static final Vector3',
  );
  fires(
    'shared mutables',
    sharedMutablesIn(
      'static final Matrix4 identity = Matrix4.zero();',
    ).isNotEmpty,
    'a static final Matrix4',
  );
  quiet(
    'shared mutables',
    sharedMutablesIn(
      'static Vector3 get up => Vector3(0.0, 1.0, 0.0);',
    ).isEmpty,
    'a getter',
    'the fix must not be reported as the fault',
  );
  quiet(
    'shared mutables',
    sharedMutablesIn('final Vector3 position = Vector3.zero();').isEmpty,
    'an instance field',
    'it is not shared with anybody',
  );
  quiet(
    'shared mutables',
    sharedMutablesIn('static const double gravity = -9.8;').isEmpty,
    'a const double',
    'a number is not a value anybody scales',
  );
  quiet(
    'shared mutables',
    sharedMutablesIn('static final RegExp _key = RegExp(r"a");').isEmpty,
    'a compiled pattern',
    'it is not a value anybody scales',
  );

  // A repeatable step.
  fires(
    'repeatable step',
    unrepeatableIn('final r = Random();') != null,
    'an unseeded Random',
  );
  fires(
    'repeatable step',
    unrepeatableIn('final t = DateTime.now();') != null,
    'DateTime.now()',
  );
  fires(
    'repeatable step',
    unrepeatableIn('final w = Stopwatch()..start();') != null,
    'a Stopwatch',
  );
  quiet(
    'repeatable step',
    unrepeatableIn('final r = Random(7);') == null,
    'a seeded Random',
    'a seed is written down and comes back the same',
  );
  quiet(
    'repeatable step',
    unrepeatableIn('final r = GameRandom(1);') == null,
    'GameRandom(1)',
    'the seeded generator is the fix, not the fault',
  );
  quiet(
    'repeatable step',
    unrepeatableIn('// Random() would be wrong here.') == null,
    'a comment',
    'prose explaining the rule must not break it',
  );

  // A world's numbers. Mutation: drop the `(?![\d.])` from the 9.81 pattern
  // and `9.812` fires; drop the gravity-on-the-line test and the fog fires.
  fires(
    'world literals',
    worldLiteralsIn('final g = 9.81;').single.literal == '9.81',
    '9.81',
  );
  fires(
    'world literals',
    worldLiteralsIn('Vector3(0.0, -9.81, 0.0)').isNotEmpty,
    'a gravity vector',
  );
  fires(
    'world literals',
    worldLiteralsIn('const double p = 101325.0;').isNotEmpty,
    'the standard atmosphere',
  );
  fires(
    'world literals',
    worldLiteralsIn('water(temperature: 293.15)').isNotEmpty,
    'a room\'s air',
  );
  fires(
    'world literals',
    worldLiteralsIn('const ParticleGravity(-9.8)').isNotEmpty,
    '9.8 where gravity is named',
  );
  fires(
    'world literals',
    worldLiteralsIn('final lift = 1025.0 * g;').isNotEmpty,
    'the sea',
  );
  fires(
    'world literals',
    worldLiteralsIn('const double _airDensity = 1.18;').isNotEmpty,
    'a density of air by two figures',
  );
  fires(
    'world literals',
    worldLiteralsIn('  const air = 1.2;').isNotEmpty,
    'a value called air',
  );
  quiet(
    'world literals',
    worldLiteralsIn('air * 1.2 + lift').isEmpty,
    '1.2 beside the air that is not a density',
    'a wind scaled by a fifth is not the air\'s density',
  );
  quiet(
    'world literals',
    worldLiteralsIn('..distance = 9.8').isEmpty,
    '9.8 on a line that does not name gravity',
    'a fog ten metres off is not the Earth',
  );
  quiet(
    'world literals',
    worldLiteralsIn('final x = 19.81 + 9.812 + 1.2045;').isEmpty,
    'numbers that merely contain one',
    'a number with digits glued to it is a different number',
  );
  quiet(
    'world literals',
    worldLiteralsIn(
      '/// 9.81 m/s², as the core has it.\nfinal g = w.g;',
    ).isEmpty,
    'a doc comment',
    'prose explaining the rule must not break it',
  );
  quiet(
    'world literals',
    worldLiteralsIn('const g = standardGravity;').isEmpty,
    'the constant by name',
    'the fix must not be reported as the fault',
  );

  // A gravity of a game's own, by any number. Mutation: drop the `\w*`
  // before `[Gg]ravity` and `runGravity = 24.0` passes; drop the nonzero
  // test and the arcade's weightless bots fire.
  fires(
    'world literals',
    worldLiteralsIn('    this.gravity = 24.0,').single.literal == '24.0',
    'a gravity default',
  );
  fires(
    'world literals',
    worldLiteralsIn('  static const double runGravity = 24.0;').isNotEmpty,
    'a gravity-named constant',
  );
  fires(
    'world literals',
    worldLiteralsIn("    gravity: 20.0,").isNotEmpty,
    'a gravity argument',
  );
  fires(
    'world literals',
    worldLiteralsIn(
      ': gravity = gravity ?? Vector3(0.0, -22.0, 0.0) {',
    ).isNotEmpty,
    'a down vector where gravity is named',
  );
  fires(
    'world literals',
    worldLiteralsIn('    this.buoyancy = 6.0,').isNotEmpty,
    'a buoyancy as an acceleration',
  );
  fires(
    'world literals',
    worldLiteralsIn('      const ParticleGravity(-14.0),').isNotEmpty,
    'a ballistic particle fall',
  );
  quiet(
    'world literals',
    worldLiteralsIn('    gravity: 0.0,').isEmpty,
    'a gravity of nought',
    'no gravity is a switch, not a world',
  );
  quiet(
    'world literals',
    worldLiteralsIn('if (gravity == 24.0) return;').isEmpty,
    'a comparison',
    'reading a number is not writing a default',
  );
  quiet(
    'world literals',
    worldLiteralsIn('final up = Vector3(0.0, -1.0, 0.0);').isEmpty,
    'a down vector where gravity is not named',
    'a direction is not a gravity',
  );
  quiet(
    'world literals',
    worldLiteralsIn('    this.buoyancyShare = 0.25,').isEmpty,
    'a buoyancy as a share of g',
    'the fix must not be reported as the fault',
  );
  quiet(
    'world literals',
    worldLiteralsIn('      const ParticleGravity(-3.0),').isEmpty,
    'a drift that only looks like falling',
    'smoke and embers are the effect author\'s to tune',
  );

  // The core's copies. Mutation: drop `WATER` from the world words and
  // F3D_WATER_HEAT passes; drop the σ value test and a renamed σ passes.
  fires(
    'core copies',
    cDefinesCopyingTheWorldIn(
          '#define F3D_WATER_HEAT F3D_R(4186.0)',
        ).single.name ==
        'F3D_WATER_HEAT',
    'water under its own name',
  );
  fires(
    'core copies',
    cDefinesCopyingTheWorldIn('#define SIGMA F3D_R(5.670374419e-8)').isNotEmpty,
    'σ under another name',
  );
  fires(
    'core copies',
    cDefinesCopyingTheWorldIn('#define F3D_AIR_HEAT F3D_R(1005.0)').isNotEmpty,
    'the air under its own name',
  );
  quiet(
    'core copies',
    cDefinesCopyingTheWorldIn(
      '/* #define F3D_WATER_HEAT F3D_R(4186.0) */\n'
      '#define F3D_SAT_T F3D_R(373.15)\n'
      '#define F3D_HAIR_SPRAY F3D_R(2.0)',
    ).isEmpty,
    'a comment, a saturation table and a word that only contains AIR',
    'prose and the 100 °C table are not copies of the catalogue',
  );
  fires(
    'core copies',
    cDefinesCopyingMaterialsIn(
      '#define F3D_WOOD_RADIANT F3D_R(0.30)',
      values: <String, Set<double>>{
        'WOOD': <double>{0.3},
      },
    ).isNotEmpty,
    'a material\'s number under its name',
  );
  quiet(
    'core copies',
    cDefinesCopyingMaterialsIn(
      '#define F3D_SPREAD_MINIMUM_WOOD F3D_R(393.15)\n'
      '#define F3D_PLYWOOD F3D_R(0.3)',
      values: <String, Set<double>>{
        'WOOD': <double>{0.3},
      },
    ).isEmpty,
    'a fire-model number of wood\'s, and WOOD inside another word',
    'what the catalogue does not hold is the fire model\'s own',
  );
  fires(
    'core copies',
    materialValuesIn(
      '/* f3d.oliveOil: olive oil, at 293.15 K. */\n'
      '#define F3D_MAT_OLIVE_OIL_DENSITY F3D_R(911.0)',
      materialNamesIn('/* f3d.oliveOil: olive oil, at 293.15 K. */'),
    )['OLIVE_OIL']!.contains(911.0),
    'the header read back by material',
  );

  // A light's number. The first is the starter project that was black: a
  // point light of 16, which since 1.0 is 16 candela.
  fires(
    'light intensities',
    smallLightIntensitiesIn(
          'Light3D.point(\n  position: p,\n  intensity: 16.0,\n  range: 20.0,\n)',
        ).single.line ==
        3,
    'Light3D.point(intensity: 16.0)',
  );
  fires(
    'light intensities',
    smallLightIntensitiesIn(
      "LightNode(name: 'sun', intensity: 2.5)",
    ).isNotEmpty,
    "LightNode(intensity: 2.5)",
  );
  fires(
    'light intensities',
    smallLightIntensitiesIn('stage.sun\n  ..intensity = 3.0;').isNotEmpty,
    '..intensity = 3.0;',
  );
  quiet(
    'light intensities',
    smallLightIntensitiesIn(
      'LightNode(intensity: 2.5 * Photometric.legacyUnit)\n'
      'LightNode(intensity: 17000.0)\nLightNode(intensity: 0.0)',
    ).isEmpty,
    'a conversion, a light in lux and a light off',
    'none of them is a number in the old unit',
  );
  quiet(
    'light intensities',
    smallLightIntensitiesIn(
      'LightNode(\n  // Candela: a candle.\n  intensity: 1.0,\n)\n'
      'BloomSettings(intensity: 0.06)',
    ).isEmpty,
    'an annotated candle and a bloom',
    'a light that says its unit is kept, and a bloom is not a light',
  );

  // Prose. The wrap is the whole reason this exists — the claim that went
  // uncounted for eight recordings was written across two lines — so the wrap
  // is the first thing proved. Mutation: join the lines with '\n' instead of
  // ' ' and this is the check that goes red.
  //
  // Counting files rather than scenes on purpose: a proof written in the
  // vocabulary of a counting rule would be a claim about that count, sitting in
  // a file that rule reads.
  fires(
    'prose',
    proseOf(
      '/// the loader read thirty-one\n/// files.',
    ).contains('thirty-one files'),
    'a claim wrapped across two doc-comment lines',
  );
  fires(
    'prose',
    proseOf(
      '// eleven of them, and\n// no more than that.',
    ).contains('eleven of them, and no more than that.'),
    'a claim wrapped across two line comments',
  );
  quiet(
    'prose',
    !proseOf(
      '// ends in six\nfinal x = 1;\n// files begin here',
    ).contains('six files'),
    'two comments with code between them',
    'the last word of one and the first of the next are not a phrase',
  );
  quiet(
    'prose',
    proseOf("final name = 'thirty files';").isEmpty,
    'a string literal',
    'code is not prose; that is what codeOf is for',
  );

  // Who a member is for.
  fires(
    'who it is for',
    !saysWhoReachesForIt('Index of the level currently visible.'),
    'a doc comment that restates the member name',
  );
  fires('who it is for', !saysWhoReachesForIt(''), 'no doc comment at all');
  quiet(
    'who it is for',
    saysWhoReachesForIt(
      'Read by whoever wants to know which surface the tyres are on.',
    ),
    'a sentence naming whoever reads it',
    'the sentence the rule asks for must satisfy it',
  );
  quiet(
    'who it is for',
    saysWhoReachesForIt('Kept so a caller can say which sounds are missing.'),
    'a sentence naming a caller',
    'the sentence the rule asks for must satisfy it',
  );

  // Public members. The three forms that were actually in the found set, and
  // the two ways of not being a member at all.
  //
  // Invented names, and for the same reason the prose proofs count files: the
  // rule these feed counts how often an identifier is written in the
  // repository, so a proof naming a real member would be one of its references.
  fires(
    'public members',
    publicMembersIn('class A {\n  int get sproutCount => _n;\n}').length == 1,
    'a getter',
  );
  fires(
    'public members',
    publicMembersIn('class A {\n  void resetTally() => _d = 0;\n}').length == 1,
    'a method',
  );
  fires(
    'public members',
    publicMembersIn(
      'class A {\n  /// Says who.\n  final int width = 1;\n}',
    ).single.doc.contains('Says who'),
    'the doc comment above a field',
  );
  quiet(
    'public members',
    publicMembersIn('class A {\n  int get _hidden => 1;\n}').isEmpty,
    'a private getter',
    'a private member is nobody outside this repository\'s business',
  );
  quiet(
    'public members',
    publicMembersIn(
      'class A {\n  @override\n  int get length => 1;\n}',
    ).isEmpty,
    'an @override',
    'the thing it implements is what names it',
  );
  quiet(
    'public members',
    publicMembersIn(
      'class A {\n  @Deprecated(\n    "Ask the graph instead.",\n  )\n'
      '  bool get old => true;\n}',
    ).isEmpty,
    'a @Deprecated whose message runs over several lines',
    'the annotation already says who is still calling it and what instead',
  );
  quiet(
    'public members',
    publicMembersIn('int topLevel() => 1;').isEmpty,
    'a top-level function',
    'a member is inside something',
  );

  // Reaching.
  fires(
    'reaches',
    reaches("import 'package:flutter_gpu/gpu.dart';", 'flutter_gpu'),
    'an import',
  );
  fires(
    'reaches',
    reaches("export 'package:flutter_gpu/gpu.dart';", 'flutter_gpu'),
    'an export',
  );
  quiet(
    'reaches',
    !reaches('/// See flutter_gpu for the details.', 'flutter_gpu'),
    'a doc comment naming it',
    'a mention is not an import',
  );

  // Another package's `src/`. The four backends and the renderer reached the
  // shaders' tables this way until `internal.dart` published them.
  fires(
    'foreign src',
    foreignSrcImports(
      "import 'package:flutter3d_shaders/src/stage_bindings.dart';\n",
      'flutter3d_cpu',
    ).contains('flutter3d_shaders'),
    "an import of another package's src/",
  );
  fires(
    'foreign src',
    foreignSrcImports(
      "export 'package:flutter3d_cpu/src/cpu_shaders_builtin.dart'\n"
          '    show builtinCpuShaders;\n',
      'flutter3d_app',
    ).contains('flutter3d_cpu'),
    "an export of another package's src/, over two lines",
  );
  quiet(
    'foreign src',
    foreignSrcImports(
      "import 'package:flutter3d_cpu/src/cpu_device.dart';\n",
      'flutter3d_cpu',
    ).isEmpty,
    "a package's own src/ through its package URI",
    'a package may arrange its own files however it likes',
  );
  quiet(
    'foreign src',
    foreignSrcImports(
      "import 'package:flutter3d_shaders/internal.dart';\n"
          '// see package:flutter3d_shaders/src/typed_blocks.dart\n',
      'flutter3d_core',
    ).isEmpty,
    'a published library, and a src/ path in a comment',
    'a comment imports nothing',
  );

  // The published-enum boundary. `qa-06`'s own row: a skeleton with an enum,
  // and a skeleton with the `LightingModel` alternative, both prove the rule
  // out on fixtures nobody has ever added to `boundaryEnumExempt` by hand.
  fires(
    'boundary enums',
    unexemptedEnumsIn('enum Foo { a, b }', const <String>{}).contains('Foo'),
    'a top-level enum with no exemption',
  );
  quiet(
    'boundary enums',
    unexemptedEnumsIn('enum Foo { a, b }', const <String>{'Foo'}).isEmpty,
    'a top-level enum a boundaryEnumExempt entry already names',
    'a reviewed, one-sentence reason is what turns a promise into a '
        'documented exception',
  );
  quiet(
    'boundary enums',
    unexemptedEnumsIn(
      'final class LightingModel {\n'
      '  const LightingModel._(this.name);\n'
      '  final String name;\n'
      '  static const LightingModel physical = LightingModel._("physical");\n'
      '}',
      const <String>{},
    ).isEmpty,
    'a final class with const instances — the enum alternative this rule '
        'itself points a caller at',
    'the fix must not be reported as the fault',
  );
  quiet(
    'boundary enums',
    unexemptedEnumsIn(
      'sealed class Shape {}\n'
      'final class Circle extends Shape {}\n'
      'final class Square extends Shape {}\n',
      const <String>{},
    ).isEmpty,
    'a sealed class hierarchy',
    'closed by inheritance rather than by an enum\'s own value list is '
        'still closed, and is not what this rule is about',
  );

  // What a pubspec depends on. The shapes are the two that actually occur: a
  // sibling with a caret, and the SDK spelled over two lines.
  const flatSpec =
      'name: flutter3d_geometry\n'
      'environment:\n'
      '  sdk: ^3.12.2\n'
      '\n'
      'dependencies:\n'
      '  vector_math: ^2.2.0\n'
      '\n'
      'dev_dependencies:\n'
      '  test: ^1.25.0\n';
  const sdkSpec =
      'name: flutter3d\n'
      'dependencies:\n'
      '  flutter:\n'
      '    sdk: flutter\n'
      '  flutter3d_hardware: ^0.6.0\n';
  const devSdkSpec =
      'name: flutter3d_model_core\n'
      'dependencies:\n'
      '  flutter3d_formats: ^0.6.0\n'
      '\n'
      'dev_dependencies:\n'
      '  flutter_test:\n'
      '    sdk: flutter\n';

  fires(
    'pubspec depends',
    pubspecDependencies(sdkSpec).contains('flutter3d_hardware'),
    'a sibling under dependencies',
  );
  fires(
    'pubspec depends',
    pubspecDependencies(flatSpec).contains('test'),
    'a package under dev_dependencies',
  );
  fires('flutter SDK', dependsOnFlutterSdk(sdkSpec), 'flutter: sdk');
  fires(
    'flutter SDK',
    dependsOnFlutterSdk(devSdkSpec),
    'flutter_test: sdk, which is the door a run-time-only scan leaves open',
  );
  quiet(
    'flutter SDK',
    !dependsOnFlutterSdk(flatSpec),
    'a pubspec naming neither',
    'a plain Dart package must pass its own rule',
  );
  quiet(
    'pubspec depends',
    !pubspecDependencies(
      'name: flutter3d_samples\n'
      'flutter:\n'
      '  assets:\n'
      '    - assets/models/\n',
    ).contains('assets'),
    'the `flutter:` asset block',
    'an asset directory is not a dependency, and reading it as one would '
        'call every package with assets a Flutter package',
  );

  // Plugin markers. The trap is Flutter's own `flutter: plugin:` block, one
  // letter and a digit away. Mutation: drop the `3d` from the key the
  // reader looks for, and every native plugin's platforms read as classes.
  fires(
    'plugin markers',
    (pluginMarkerEntries(
                  'name: post\n'
                  'flutter3d:\n'
                  '  plugin:\n'
                  '    light.dart: [Bloom, Flare]\n'
                  '    package:post/fog.dart: Fog\n'
                  '    style.dart:\n'
                  '      - Toon\n'
                  '\n'
                  'dependencies:\n',
                ) ??
                const <String>[])
            .join(' ') ==
        'light.dart#Bloom light.dart#Flare package:post/fog.dart#Fog '
            'style.dart#Toon',
    'a marker per library, in flow, scalar and block style',
  );
  fires(
    'plugin markers',
    (pluginMarkerEntries(
                  'flutter3d:\n'
                  '  plugin:\n'
                  '    - trails.dart#Trails\n'
                  '    - trails.dart#Wake\n',
                ) ??
                const <String>[])
            .length ==
        2,
    'a list of entries',
  );
  // The key since 1.0. Mutation: look only for `flutter3d:` and the marker
  // reads as nothing.
  fires(
    'plugin markers',
    (pluginMarkerEntries(
                  'name: post\n'
                  'flutter3d_plugins:\n'
                  '  plugin:\n'
                  '    light.dart: [Bloom, Flare]\n'
                  '    style.dart:\n'
                  '      - Toon\n'
                  'dependencies:\n',
                ) ??
                const <String>[])
            .join(' ') ==
        'light.dart#Bloom light.dart#Flare style.dart#Toon',
    'the flutter3d_plugins: key, in flow and block style',
  );
  fires(
    'plugin markers',
    usesLegacyPluginMarker('flutter3d:\n  plugin: trails.dart#Trails\n'),
    'the key of before 1.0',
  );
  quiet(
    'plugin markers',
    !usesLegacyPluginMarker(
      'flutter3d_plugins:\n  plugin: trails.dart#Trails\n',
    ),
    'the key since 1.0',
    'only the old key is the one to move',
  );
  quiet(
    'plugin markers',
    pluginMarkerEntries(
          'name: pad_input\n'
          'flutter:\n'
          '  plugin:\n'
          '    platforms:\n'
          '      android:\n'
          '        pluginClass: GamepadPlugin\n',
        ) ==
        null,
    'Flutter\'s own `flutter: plugin:` block',
    'it registers native code; discovery never reads it',
  );

  // The publishing order. Mutation: compare steps with `>` instead of `>=`
  // and a runtime dependency published beside its dependent passes; drop the
  // allowance lookup and every documented dev inversion fails.
  final order = publishingLayers(
    '1. L0: `a`, `b`\n'
    '2. L1: `c`,\n'
    '   `d`\n'
    '3. Not published: `e`\n',
  );
  fires(
    'publishing order',
    order.length == 3 &&
        order[1].names.join(' ') == 'c d' &&
        !order[2].published,
    'steps, a wrapped step, and the unpublished one',
  );
  fires(
    'publishing order',
    publishingOrderBreaks(
      order,
      <String, ({Set<String> runtime, Set<String> dev})>{
        'b': (runtime: <String>{'a'}, dev: <String>{}),
      },
      const <String, String>{},
    ).isNotEmpty,
    'a runtime dependency in the same step',
  );
  quiet(
    'publishing order',
    publishingOrderBreaks(
      order,
      <String, ({Set<String> runtime, Set<String> dev})>{
        'c': (runtime: <String>{'a'}, dev: <String>{'b'}),
      },
      const <String, String>{},
    ).isEmpty,
    'runtime and dev dependencies published earlier',
    'that is the order working',
  );
  fires(
    'publishing order',
    publishingOrderBreaks(
      order,
      <String, ({Set<String> runtime, Set<String> dev})>{
        'a': (runtime: <String>{}, dev: <String>{'d'}),
      },
      const <String, String>{},
    ).isNotEmpty,
    'a dev dependency published later, with no reason',
  );
  quiet(
    'publishing order',
    publishingOrderBreaks(
      order,
      <String, ({Set<String> runtime, Set<String> dev})>{
        'a': (runtime: <String>{}, dev: <String>{'d'}),
      },
      const <String, String>{'a -> d': 'a test'},
    ).isEmpty,
    'a dev dependency published later, with its reason',
    'a documented inversion is allowed',
  );
  fires(
    'publishing order',
    publishingOrderBreaks(
      order,
      <String, ({Set<String> runtime, Set<String> dev})>{
        'c': (runtime: <String>{}, dev: <String>{'e'}),
      },
      const <String, String>{},
    ).isNotEmpty,
    'a dev dependency on a package that is not published',
  );
  fires(
    'publishing order',
    publishingOrderBreaks(
      order,
      <String, ({Set<String> runtime, Set<String> dev})>{
        'd': (runtime: <String>{}, dev: <String>{'a'}),
      },
      const <String, String>{'d -> a': 'stale'},
    ).isNotEmpty,
    'an allowance that no longer inverts',
  );

  // Platforms. The trap is the plugin's own list, nested under `flutter:`:
  // it names where native code registers, not where the package runs.
  // Mutation: drop the `^` anchor and the plugin's list counts as declared.
  const declaredSpec =
      'name: flutter3d_geometry\n'
      'platforms:\n'
      '  linux:\n'
      '  web:\n'
      '\n'
      'dependencies:\n'
      '  vector_math: ^2.2.0\n';
  const pluginSpec =
      'name: pad_input\n'
      'dependencies:\n'
      '  flutter:\n'
      '    sdk: flutter\n'
      'flutter:\n'
      '  plugin:\n'
      '    platforms:\n'
      '      android:\n'
      '        pluginClass: GamepadPlugin\n';
  fires(
    'platforms',
    declaredPlatforms(declaredSpec)?.containsAll(<String>{'linux', 'web'}) ??
        false,
    'a top-level platforms block',
  );
  quiet(
    'platforms',
    declaredPlatforms(declaredSpec)?.length == 2,
    'the line after the block',
    'the block ends at the first line that is not indented',
  );
  quiet(
    'platforms',
    declaredPlatforms(pluginSpec) == null,
    'a plugin\'s platforms under flutter: plugin:',
    'where native code registers is not where the package runs',
  );
  fires(
    'backend',
    implementsGraphicsDevice(
      'final class CpuDevice\n'
      '    with DeviceCapabilityForwarders\n'
      '    implements GraphicsDevice {\n',
    ),
    'a device declared over three lines',
  );
  quiet(
    'backend',
    !implementsGraphicsDevice(
      'final class Probe implements GraphicsDeviceFactory {}\n',
    ),
    'a longer name that starts the same',
    'a factory of devices is not a device',
  );
  quiet(
    'backend',
    !implementsGraphicsDevice(
      'final class Frame implements Pass {\n'
      '  final GraphicsDevice device;\n',
    ),
    'a field of the type inside another class',
    'holding a device is not being one',
  );
  final rows = packagePlatformRows(
    '| Package | Platforms |\n'
    '|---|---|\n'
    '| `flutter3d_webgl` | web |\n'
    '| `pointer_lock` | linux, macos, web, windows |\n',
  );
  fires(
    'support table',
    rows['pointer_lock']?.length == 4 &&
        (rows['flutter3d_webgl']?.join(',') ?? '') == 'web',
    'two rows of a package table',
  );
  quiet(
    'support table',
    !rows.containsKey('Package'),
    'the header row',
    'a header is not a package',
  );

  // The public API: the semver classifier, the CHANGELOG label and the
  // deprecation format. Their fixtures live beside them in `api.dart`,
  // because each is a table of cases the classifier's own rules are read
  // against.
  for (final (what, detail) in proveApiDetectorsWork()) {
    broken.add(Finding(what, detail));
  }

  // The tools for agents and the VM service: the same verdicts over the
  // `.mcp` and `.vm` snapshots, with their fixtures beside them in
  // `schema.dart`.
  for (final (what, detail) in proveSchemaDetectorsWork()) {
    broken.add(Finding(what, detail));
  }

  // The migration table: its reader without a YAML parser, and which breaks
  // its entries cover — with the classifier's three non-breaks to a caller
  // (an inherited member, a re-exported move, a constructor every call
  // still fits), fixtures beside them in `migration.dart`.
  for (final (what, detail) in proveNamingDetectorsWork()) {
    broken.add(Finding(what, detail));
  }
  for (final (what, detail) in proveMigrationDetectorsWork()) {
    broken.add(Finding(what, detail));
  }

  // Format versions: the constant a reader is held to, and the gate that
  // refuses every older file. The traps are the comment that quotes an old
  // number and a version that is not a format's — an object's edit counter
  // compared with the one a cache was baked at.
  final versions = formatVersionsIn(
    '  static const int formatVersion = 3;\n'
    'const int f3dVersion = 1;\n'
    '/// was `const int fmatVersion = 0;` before the bump\n',
  );
  fires(
    'format versions',
    versions['formatVersion'] == 3 && versions['f3dVersion'] == 1,
    'a static formatVersion and a top-level f3dVersion',
  );
  quiet(
    'format versions',
    !versions.containsKey('fmatVersion'),
    'a doc comment quoting an old constant',
    'prose about a bump must not be read as the constant',
  );
  final specs = formatSpecsIn(
    '  static const int formatVersion = 3;\n'
    '  static const FormatSpec spec = FormatSpec(\n'
    "    id: 'f3d.level',\n"
    '    version: Level.formatVersion,\n'
    "    fixture: 'test/fixtures/v<N>/first.level.json',\n"
    '    migrations: <FormatMigration>[_a, _b],\n'
    '  );\n'
    "  // FormatSpec(id: 'f3d.old', version: 9)\n"
    "const FormatSpec other = FormatSpec(id: 'x.y', version: 2, since: 2);\n",
  );
  fires(
    'declared formats',
    specs.length == 2 &&
        specs.first.id == 'f3d.level' &&
        specs.first.version == 3 &&
        specs.first.versionConstant == 'formatVersion' &&
        specs.first.fixture == 'test/fixtures/v<N>/first.level.json' &&
        specs.last.version == 2 &&
        specs.last.since == 2 &&
        specs.last.fixture == null,
    'a spec naming its constant, and one with a literal version',
  );
  final cli = cliSurfaceWords(
    '== flutter3d ==\nUsage: flutter3d <command>\n'
    '== convert ==\n  --dry-run   write nothing\n  -o, --output <dir>\n'
    '  see dart run flutter3d_build:convert\n',
  );
  fires(
    'cli surface',
    cli.containsAll(<String>[
          'convert',
          'convert --dry-run',
          'convert --output',
        ]) &&
        !cli.contains('convert --build'),
    'a subcommand and its flags, not a package name with a dash',
  );
  quiet(
    'format versions',
    formatVersionsIn('const int abiVersion = 36;').isEmpty,
    'the C core\'s ABI number',
    'an ABI is matched exactly by design, and is not a file a reader opens',
  );
  fires(
    'exact version gates',
    exactVersionGatesIn(
      'final v = 1;\n    if (version != formatVersion) {\n',
    ).contains(2),
    'version != formatVersion',
  );
  fires(
    'exact version gates',
    exactVersionGatesIn(
      'if (said != ShaderBundle.sectionVersion) {}',
    ).isNotEmpty,
    'a qualified constant',
  );
  quiet(
    'exact version gates',
    exactVersionGatesIn('if (object.version != baseVersion) {}').isEmpty,
    'an edit counter against a cache stamp',
    'not every version is a file format\'s',
  );
  quiet(
    'exact version gates',
    exactVersionGatesIn('// once: version != formatVersion').isEmpty,
    'a comment recalling the old gate',
    'prose explaining the rule must not break it',
  );

  fires(
    'a temporary mute',
    temporaryMutesIn(
      '// $temporaryMuteMarker: in a meeting\nsoloud.setGlobalVolume(0);',
    ).contains(1),
    'the marker in a line comment',
  );
  fires(
    'a temporary mute',
    temporaryMutesIn('volume = 0; # $temporaryMuteMarker').isNotEmpty,
    'the marker in a shell comment',
  );
  quiet(
    'a temporary mute',
    temporaryMutesIn('// a temporary silence while testing').isEmpty,
    'prose about silence',
    'only the marker is the promise to revert',
  );

  fires(
    'an enum ordinal in a file',
    enumOrdinalsIn(
      'view.setUint32(o, material.alphaMode.index, Endian.little);',
    ).contains(1),
    'an enum written by its ordinal',
  );
  fires(
    'an enum ordinal in a file',
    enumOrdinalsIn(
      'final a = 1;\npath: AnimationPath.values[pathIndex],',
    ).contains(2),
    'an enum read back by its ordinal',
  );
  quiet(
    'an enum ordinal in a file',
    enumOrdinalsIn(
      '// once: material.alphaMode.index\n'
      '/// [TextureWrap.values] in order\n'
      'record.setUint32(28, track.values.length, Endian.little);',
    ).isEmpty,
    'a comment recalling the ordinal and a list named values',
    'prose explaining the rule, and a length, are not an ordinal',
  );

  // The layers. A made-up tree: a foundation, a contract over it, a core
  // over that, and a shell that may not have the core's sibling.
  const toyLayers = <String, int>{'f': 0, 'c': 1, 'r': 2, 's': 2, 'x': 3};
  const toyForbidden = <String, Map<String, String>>{
    'x': <String, String>{'s': 'the shell names no simulation'},
  };
  List<(String, String?, String)> layered(Map<String, Set<String>> deps) =>
      layerProblems(deps, layers: toyLayers, forbidden: toyForbidden);
  fires(
    'the layers',
    layered(<String, Set<String>>{
      'f': <String>{'c'},
      'c': <String>{},
    }).any(((String, String?, String) p) => p.$1 == 'f' && p.$2 == 'c'),
    'the foundation depending on the contract above it',
  );
  fires(
    'the layers',
    layered(<String, Set<String>>{
      'r': <String>{'s'},
      's': <String>{},
    }).any(((String, String?, String) p) => p.$1 == 'r' && p.$2 == 's'),
    'a package depending on its own layer',
  );
  fires(
    'the layers',
    layered(<String, Set<String>>{
      'x': <String>{'s'},
      's': <String>{},
    }).any(((String, String?, String) p) => p.$1 == 'x' && p.$2 == 's'),
    'a dependency the map forbids though the layers allow it',
  );
  fires(
    'the layers',
    layered(<String, Set<String>>{
      'new': <String>{},
    }).any(((String, String?, String) p) => p.$1 == 'new' && p.$2 == null),
    'a package with no layer',
  );
  quiet(
    'the layers',
    layered(<String, Set<String>>{
      'x': <String>{'r', 'f', 'vector_math'},
      'r': <String>{'c'},
      'c': <String>{'f'},
      'f': <String>{},
    }).isEmpty,
    'every dependency in a layer below, and one from pub.dev',
    'a dependency downwards is the rule, and pub.dev is not a layer',
  );

  // The runtime is not a tool (rule 7): a game on an editor is found, the
  // same tool under a tool, and a runtime package on the simulation, are not.
  List<(String, String)> runtimeOnTools(Map<String, Set<String>> deps) =>
      runtimeToolDependencies(
        deps,
        runtime: isRuntimePackage,
        tools: runtimeMayNotDependOn.keys.toSet(),
      );
  fires(
    'the runtime is not a tool',
    runtimeOnTools(<String, Set<String>>{
      'flutter3d_app': <String>{'flutter3d_editor_core', 'flutter3d_sim'},
    }).contains(('flutter3d_app', 'flutter3d_editor_core')),
    'the application depending on the editor\'s core',
  );
  fires(
    'the runtime is not a tool',
    runtimeOnTools(<String, Set<String>>{
      'flutter3d_game_ui': <String>{'flutter3d_mcp'},
    }).isNotEmpty,
    'a game package (by its prefix) depending on the agent servers',
  );
  quiet(
    'the runtime is not a tool',
    runtimeOnTools(<String, Set<String>>{
      'flutter3d_mcp': <String>{'flutter3d_editor_core'},
      'flutter3d_game': <String>{'flutter3d_sim', 'flutter3d_app'},
    }).isEmpty,
    'a tool on a tool, and a game on the runtime under it',
    'only the runtime is held to it, and only against the tools',
  );

  // The simulation draws nothing (rule 6): an import of the core is found,
  // one of the native physics or of a package whose name only starts like
  // a forbidden one is not.
  fires(
    'the simulation stack',
    simulationImportProblems(
      <String, List<String>>{
        'lib/src/step.dart': <String>[
          'package:flutter3d_core/flutter3d_core.dart',
        ],
      },
      forbidden: const <String>{'flutter3d_core'},
    ).any(((String, String) p) => p.$2 == 'flutter3d_core'),
    "import 'package:flutter3d_core/flutter3d_core.dart' in a step",
  );
  quiet(
    'the simulation stack',
    simulationImportProblems(
      <String, List<String>>{
        'lib/src/step.dart': <String>[
          'package:flutter3d_physics_native/flutter3d_physics_native.dart',
          'package:flutter3d_core_extras/x.dart',
          'dart:math',
        ],
      },
      forbidden: const <String>{'flutter3d_core'},
    ).isEmpty,
    'the native physics, a package named like the core, and dart:math',
    'only the forbidden packages themselves are refused',
  );

  // The plugin contract's reach. `Lost` is named by nobody; `Handed` by a
  // root's member, `Thrown` by its supertype, `Kept` by a re-export.
  const contract = <String, ({String header, List<String> members})>{
    'Root': (
      header: 'abstract base class Root',
      members: <String>['Handed get handed'],
    ),
    'Handed': (header: 'final class Handed', members: <String>[]),
    'Thrown': (header: 'final class Thrown extends Kept', members: <String>[]),
    'Lost': (header: 'final class Lost', members: <String>['Root get root']),
    'helper': (header: 'int helper()', members: <String>[]),
  };
  final lost = unreachableContractTypes(
    contract,
    roots: const <String>{'Root'},
    reexported: const <String>{'Kept'},
  );
  fires(
    'the plugin contract',
    lost.contains('Lost'),
    'a type that names a root but that no root names',
  );
  quiet(
    'the plugin contract',
    !lost.contains('Handed') &&
        !lost.contains('Thrown') &&
        !lost.contains('helper'),
    'a type a root hands out, a subtype of a re-exported one, a function',
    'reached through a signature or a supertype is the contract, and a '
        'function is not a type',
  );
  fires(
    'the plugin contract',
    phasesNamedForAPackage(
      declaredLoopPhases(
        "static const LoopPhase elements = LoopPhase.step('elements');",
      ),
      const <String>['flutter3d_elements'],
    ).contains('elements'),
    "LoopPhase.step('elements') beside flutter3d_elements",
  );
  quiet(
    'the plugin contract',
    phasesNamedForAPackage(
      declaredLoopPhases(
        "static const LoopPhase fields = LoopPhase.step('fields');\n"
        "static const LoopPhase ui = LoopPhase.frame( 'ui' );",
      ),
      const <String>['flutter3d_elements', 'flutter3d_game_ui'],
    ).isEmpty,
    'a phase named for what runs in it, and one a package name only ends with',
    'only a package called flutter3d_<phase> claims a phase',
  );

  // One home per public name. `Brush` declared by two packages is the
  // finding; a name one package declares in two libraries, a name another
  // package only re-exports, and a name the allowlist names are not.
  final homes = publicNameHomes(const <String, String>{
    'mesh':
        'library package:mesh/mesh.dart\n\nclass Brush\n  const Brush()\n\n'
        'library package:mesh/sculpt.dart\n\nclass Brush\n  const Brush()\n',
    'sim':
        'library package:sim/sim.dart\n\nfinal class Brush\n\n'
        'final class Level\n\n'
        'export package:mesh/mesh.dart show Brush\n',
    'game':
        'library package:game/game.dart\n\nfinal class Level\n\n'
        'export package:sim/sim.dart show Level\n',
  });
  fires(
    'one home per public name',
    namesWithTwoHomes(
      homes,
      allowed: const <String, String>{},
    ).any(((String, List<String>) d) => d.$1 == 'Brush'),
    'Brush declared by mesh and by sim',
  );
  quiet(
    'one home per public name',
    homes['Brush']!.length == 2 &&
        namesWithTwoHomes(
          homes,
          allowed: const <String, String>{'Level': 'two games never meet'},
        ).every(((String, List<String>) d) => d.$1 == 'Brush'),
    'Brush in two libraries of mesh and re-exported by sim; Level allowed',
    'two libraries of one package are one home, a re-export is not a '
        'declaration, and an allowed name is allowed',
  );

  // The restricted libraries. A game reaching a backend's `testing.dart`
  // from its `lib/` is the finding; a doc comment showing the import, a
  // package's own, and an allowed user are not.
  fires(
    'restricted libraries',
    restrictedLibraryProblems(<String, Set<String>>{
      'game': restrictedLibrariesIn(
        "import 'package:cpu/testing.dart';\n"
        "import 'package:cpu/cpu.dart';",
      ),
    }, allowed: const <String, Map<String, String>>{}).any(
      ((String, String, String) p) => p.$2 == 'package:cpu/testing.dart',
    ),
    "game's lib importing package:cpu/testing.dart",
  );
  quiet(
    'restricted libraries',
    restrictedLibraryProblems(
      <String, Set<String>>{
        'game': restrictedLibrariesIn(
          "/// import 'package:cpu/testing.dart';\n"
          "  export 'package:shaders/internal.dart' show x;",
        ),
        'cpu': restrictedLibrariesIn("import 'package:cpu/builtin.dart';"),
      },
      allowed: const <String, Map<String, String>>{
        'package:shaders/internal.dart': <String, String>{'game': 'a test'},
      },
    ).isEmpty,
    'an import in a doc comment, an allowed export, a package\'s own',
    'prose is not a directive, an allowed user is allowed, and a package '
        'reaches its own libraries',
  );

  // Re-exports (rule 3). The simulation handing on the physics is the
  // finding, and so is an allowed facade admitting a whole library; a
  // package's own library, pub.dev's, a doc comment and an allowed named
  // re-export are not.
  List<(String, String, String)> reexported(String package, String source) =>
      reexportProblems(
        <String, Map<String, List<({String uri, bool named})>>>{
          package: <String, List<({String uri, bool named})>>{
            'lib/$package.dart': packageExportsIn(source),
          },
        },
        repository: const <String>{'sim', 'physics', 'game', 'shell'},
        allowed: const <String, String>{
          'game -> shell': 'the facade',
          'game -> sim': 'the facade, by name',
        },
        whole: const <String, String>{'game -> shell': 'a list itself'},
      );
  fires(
    're-exports',
    reexported(
      'sim',
      "export 'package:physics/physics.dart'\n    show CollisionWorld;",
    ).isNotEmpty,
    "export 'package:physics/physics.dart' show CollisionWorld from sim",
  );
  fires(
    're-exports',
    reexported('game', "export 'package:sim/sim.dart';").isNotEmpty,
    'an allowed facade re-exporting a whole library it should name',
  );
  quiet(
    're-exports',
    reexported(
      'game',
      "/// export 'package:physics/physics.dart';\n"
          "export 'package:game/src/run.dart';\n"
          "export 'package:vector_math/vector_math.dart';\n"
          "export 'package:shell/shell.dart';\n"
          "export 'package:sim/sim.dart'\n    show Level;",
    ).isEmpty,
    'a doc comment, its own, pub.dev, an allowed whole and named one',
    'only another package of the repository, not on the list, is refused',
  );

  // A dependency held only to re-export it (rule 2): the shell depending on
  // the simulation for an export is the finding; one it imports, and an
  // allowed facade's, are not.
  final handOn = reexportOnlyDependencies(
    const <String, Set<String>>{
      'shell': <String>{'sim', 'core'},
      'game': <String>{'shell'},
    },
    imported: const <String, Set<String>>{
      'shell': <String>{'core'},
      'game': <String>{},
    },
    exported: const <String, Set<String>>{
      'shell': <String>{'sim', 'core'},
      'game': <String>{'shell'},
    },
    allowed: const <String, String>{'game -> shell': 'the facade'},
  );
  fires(
    'dependencies held to re-export',
    handOn.contains(('shell', 'sim')),
    'a dependency the shell only exports',
  );
  quiet(
    'dependencies held to re-export',
    handOn.length == 1,
    'a dependency also imported, and an allowed facade\'s',
    'a dependency the code uses is used, and the list is the exception',
  );

  // Declare what you name (rule 4). A type named in code through a package
  // the pubspec does not name is the finding; one in a comment or a
  // string, one the package declares, one a dependency declares or a
  // facade carries, and one the SDK has too are not.
  final scanned = typeNamesIn(
    "import 'package:sim/sim.dart';\n"
    '/// [Comment] is prose.\n'
    "final label = 'Quoted';\n"
    'final world = CollisionWorld();\n'
    'Level level = Level();\n'
    'Match? m;\n'
    'class Own {}\n',
  );
  fires(
    'declare what you name',
    scanned.named.contains('CollisionWorld') &&
        scanned.declared.contains('Own'),
    'a constructor call and a class declaration found by the scan',
  );
  quiet(
    'declare what you name',
    !scanned.named.contains('Comment') && !scanned.named.contains('Quoted'),
    'a name in a doc comment and one in a string',
    'only code names a type',
  );
  List<(String, String, String, String)> undeclared(Set<String> deps) =>
      undeclaredNames(
        <String, Map<String, Set<String>>>{
          'app': <String, Set<String>>{'lib/main.dart': scanned.named},
        },
        declared: <String, Set<String>>{'app': scanned.declared},
        homes: const <String, String>{
          'CollisionWorld': 'physics',
          'Level': 'sim',
          'Match': 'strategy',
          'Own': 'other',
        },
        dependencies: <String, Set<String>>{'app': deps},
        carried: const <String, Set<String>>{
          'game': <String>{'CollisionWorld', 'Level'},
        },
        sdk: const <String, String>{'Match': 'dart:core'},
      );
  fires(
    'declare what you name',
    undeclared(const <String>{
      'sim',
    }).any(((String, String, String, String) u) => u.$3 == 'CollisionWorld'),
    'CollisionWorld named by an application that depends on sim alone',
  );
  quiet(
    'declare what you name',
    undeclared(const <String>{'sim', 'physics'}).isEmpty &&
        undeclared(const <String>{'game'}).isEmpty,
    'the physics declared, or the facade that carries it',
    'a dependency or an allowed facade is the declaration; the SDK\'s name '
        'and the package\'s own are not asked about',
  );

  return broken;
}

/// The 1-based lines of [source] that write or read a Dart enum by its
/// ordinal: `.index`, or `values[` indexed by a number from a file.
///
/// **A file outlives the enum's order.** `.f3d` wrote `alphaMode.index`,
/// `wrapS.index` and a track's `path.index`, and read them back with
/// `values[i]`; inserting a case anywhere but the end, in any major, would
/// have changed what every existing file meant, and nothing would have said
/// so. A format's code goes through an explicit table instead
/// (`f3d_wire.dart`), whose writer is an exhaustive `switch`. Comment lines
/// are not code and are skipped.
List<int> enumOrdinalsIn(String source) {
  final ordinal = RegExp(r'\.index\b|\bvalues\[');
  final lines = source.split('\n');
  return <int>[
    for (var i = 0; i < lines.length; i++)
      if (ordinal.hasMatch(_codeOf(lines[i]))) i + 1,
  ];
}

/// [line] up to a `//` comment, or empty for a comment line.
String _codeOf(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('//')) return '';
  final comment = line.indexOf(' //');
  return comment < 0 ? line : line.substring(0, comment);
}

/// The word a quick local mute is marked with, spelled in two pieces so this
/// file, which looks for it, never holds it.
const String temporaryMuteMarker =
    'TEMP'
    'SILENT';

/// The 1-based lines of [source] that carry [temporaryMuteMarker].
///
/// **A whole game shipped silent from one of these once.** A line muting
/// the audio engine was written for a meeting, marked to be reverted before
/// committing, and stayed through a wave of commits, because nothing but a
/// person's memory looked for the mark. Any tracked source, in any language,
/// that carries it fails.
List<int> temporaryMutesIn(String source) {
  final lines = source.split('\n');
  return <int>[
    for (var i = 0; i < lines.length; i++)
      if (lines[i].contains(temporaryMuteMarker)) i + 1,
  ];
}
