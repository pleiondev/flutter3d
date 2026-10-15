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

import 'dart:convert';

import 'api.dart';
import 'boundaries.dart';
import 'hal.dart';
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

// ------------------------------------------------------------ a vector's owner

/// The mutable value types a vector rule reads: the ones [_sharedMutable]
/// reads, for the same reason.
const String _vectorType = r'(?:Vector[234]|Matrix[234]|Quaternion|Aabb[23])';

final RegExp _typeDeclaration = RegExp(
  r'(?:^|\n)[ \t]*(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
  r'(class|mixin|enum|extension\s+type|extension)\b\s*'
  r'(?!on\b)([A-Za-z_$][\w$]*)?',
);

/// A getter (its name in group 1) or an `…Of` query (group 2) answering a
/// vector, and how its body starts (group 3).
final RegExp _vectorGetter = RegExp(
  '(?<![\\w\$.])(?:static\\s+)?$_vectorType\\??\\s+'
  r'(?:get\s+([A-Za-z$][\w$]*)|([A-Za-z$][\w$]*Of)\s*\([^()]*\))'
  r'\s*(=>|\{)',
);

/// An expression that names a vector somebody already holds: a field, a
/// field's field, an element of a list it keeps. A call, an operator or a
/// constructor makes a new one.
final RegExp _heldVector = RegExp(
  r'^(?:this\.)?[A-Za-z_$][\w$]*(?:\[[^\[\]]*\]|[!?]?\.[A-Za-z_$][\w$]*)*!?$',
);

final RegExp _cachedVector = RegExp(r'^[A-Za-z_$][\w$.]*\s*\?\?=');

/// The index of the bracket that closes the one at [open], or the end.
int _matching(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '{' || c == '(' || c == '[') depth++;
    if (c == '}' || c == ')' || c == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return code.length - 1;
}

/// The index of the `;` that ends the statement from [from], or the end.
int _statementEnd(String code, int from) {
  var depth = 0;
  for (var i = from; i < code.length; i++) {
    final c = code[i];
    if (c == '{' || c == '(' || c == '[') depth++;
    if (c == '}' || c == ')' || c == ']') depth--;
    if (c == ';' && depth <= 0) return i;
  }
  return code.length;
}

/// Each class, mixin, enum and extension in [code], by name (empty for an
/// unnamed extension), with the braces of its body.
List<({String type, int open, int close})> _typeBodiesIn(String code) =>
    <({String type, int open, int close})>[
      for (final m in _typeDeclaration.allMatches(code))
        if (code.indexOf('{', m.end) case final open when open >= 0)
          (type: m.group(2) ?? '', open: open, close: _matching(code, open)),
    ];

/// Whether a type named [type] is one a caller outside its library can
/// reach: not private, and not an unnamed extension, which is visible only
/// where it is declared.
bool _reachable(String type) => type.isNotEmpty && !type.startsWith('_');

/// Every public getter and `…Of` query in [source] that hands out a vector
/// somebody holds, as `Type.getter` with its line.
///
/// **A getter answers a copy the caller owns** (docs/CONTRACTS.md, "Space").
/// `PhotoCamera.eye => _eye` handed out the camera's own vector, so a caller
/// that scaled what it was given moved the camera through its collision,
/// while `PhotoCamera.target` beside it answered a new one: one class, two
/// answers, and neither doc said which. A public `final` field is the
/// owner's live state and says so by being one; a getter is not a field.
///
/// What counts as handing one out: an expression body, or a `return`, that
/// is a bare name, a chain of names or an element of a list (`_eye`,
/// `collider.position`, `_foci[_at]`), or a `??=` cache. A call, a `clone()`,
/// an operator or a vector the body declared itself is a new one. A chain
/// ending in another getter that already copies reads the same as one ending
/// in a field, so `liveVectorGetterAllowed` names those with the getter they
/// end in.
List<({String subject, int line})> liveVectorGettersIn(String source) {
  final code = codeOf(source);
  final types = _typeBodiesIn(code);
  int lineAt(int offset) =>
      '\n'.allMatches(code.substring(0, offset)).length + 1;
  final out = <({String subject, int line})>[];
  for (final m in _vectorGetter.allMatches(code)) {
    final inner = types
        .where(
          (({String type, int open, int close}) t) =>
              t.open < m.start && m.start < t.close,
        )
        .fold<({String type, int open, int close})?>(
          null,
          (({String type, int open, int close})? best, t) =>
              best == null || t.open > best.open ? t : best,
        );
    final type = inner?.type;
    if (type != null && !_reachable(type)) continue;
    final arrow = m.group(3) == '=>';
    final name = m.group(1) ?? m.group(2)!;
    final body = arrow
        ? ''
        : code.substring(m.end - 1, _matching(code, m.end - 1) + 1);
    final answers = arrow
        ? <String>[code.substring(m.end, _statementEnd(code, m.end)).trim()]
        : <String>[
            for (final r in RegExp(r'\breturn\b').allMatches(body))
              body.substring(r.end, _statementEnd(body, r.end)).trim(),
          ];
    bool declaredHere(String name) => RegExp(
      '(?:final|var|late|$_vectorType\\??)\\s+${RegExp.escape(name)}\\s*[=;]',
    ).hasMatch(body);
    final held = answers.any(
      (String e) =>
          (_heldVector.hasMatch(e) &&
              e != 'null' &&
              e != 'this' &&
              !declaredHere(e)) ||
          _cachedVector.hasMatch(e),
    );
    if (held) {
      out.add((
        subject: type == null ? name : '$type.$name',
        line: lineAt(m.start),
      ));
    }
  }
  return out;
}

final RegExp _vectorField = RegExp(
  '(?:^|[;{}\\n])\\s*(?:@\\w+\\s+)*(?:static\\s+)?(?:late\\s+)?(?:final\\s+)?'
  '$_vectorType\\??\\s+([A-Za-z_\$][\\w\$]*)\\s*[;=,]',
);

final RegExp _memberHead = RegExp(
  r'(?:\bset\s+)?([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)\s*\(',
);

final RegExp _vectorParameter = RegExp(
  '(?:^|[,({\\[\\s])$_vectorType\\??\\s+([A-Za-z_\$][\\w\$]*)',
);

final RegExp _bareAssignment = RegExp(
  r'(?:^|[;,{}\s:])(?:this\.)?([A-Za-z_$][\w$]*)\s*=\s*([A-Za-z_$][\w$]*)'
  r'\s*(?=[;,}]|$)',
);

const Set<String> _notAMember = <String>{
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'return',
  'assert',
  'super',
  'this',
  'await',
  'throw',
};

/// Every public member in [source] that keeps a vector it was passed, as
/// `Type.member(parameter)` with its line.
///
/// **A vector parameter is read and never kept** (docs/CONTRACTS.md,
/// "Space"): the callee copies, `_target.setFrom(target)` into a field it
/// owns or `target.clone()`. A member that stores the caller's vector
/// itself shares it, and the caller who reuses a scratch vector for the
/// next call moves this one too.
///
/// What counts: in a public method, setter or constructor of a public type,
/// an assignment `field = parameter` (in its body or its initializer list)
/// where the parameter is a vector and the field is one of the type's own
/// vector fields. An initializing formal (`this.position`) is not read: it
/// is how a value type is declared, and a value type takes ownership of the
/// vectors its constructor is given, the caller not mutating them after
/// (CONTRACTS "Who owns a vector", which [vectorOwnershipGapsIn] holds).
/// The doc comment directly above [line] (1-based) of [source], its `///`
/// markers off and its wrap undone, past any annotation between them; empty
/// when the member has none.
String docAboveLine(String source, int line) {
  final lines = source.split('\n');
  final doc = <String>[];
  for (var i = line - 2; i >= 0; i--) {
    final text = lines[i].trim();
    if (text.startsWith('@')) continue;
    if (!text.startsWith('///')) break;
    doc.insert(0, text.substring(3).trim());
  }
  return doc.join(' ').trim();
}

/// The words a getter that answers its object's own cache says in its doc,
/// and the reason its `liveVectorGetterAllowed` entry starts with.
const String liveCacheWords =
    'live: the object\'s own cache, read-only by contract';

/// What is wrong with a `liveVectorGetterAllowed` [reason] for a getter
/// documented by [doc], or null when nothing is.
///
/// **Two kinds of entry, and each says which it is.** A chain that ends in
/// a getter that copies names that getter (`… answers a copy`, `… builds a
/// new vector`). A live answer that cannot be a field, because it is
/// refreshed when it is read or belongs to an object that can be swapped,
/// starts `live: <whose>, read-only by contract;` ([liveCacheWords] for the
/// object's own cache) and gives the reason after the semicolon, and the
/// getter's own doc carries the clause before it, so a reader of the API is
/// told the answer is live and not theirs to write.
String? liveGetterReasonProblem(String reason, String doc) {
  final chain =
      reason.contains('answers a copy') ||
      reason.contains('builds a new vector');
  final live = RegExp(
    r'^live: [^;]+, read-only by contract;',
  ).firstMatch(reason)?.group(0);
  if (!chain && live == null) {
    return 'is excused for a reason of neither kind: name the getter its '
        'chain ends in (`… answers a copy`), or start with '
        '"$liveCacheWords;" and say why it cannot be a field';
  }
  if (live != null) {
    final clause = live.substring(0, live.length - 1);
    if (!doc.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').contains(clause)) {
      return 'answers a live vector and its doc does not say "$clause"';
    }
  }
  return null;
}

/// The cases of "Who owns a vector" (docs/CONTRACTS.md, "Space") that
/// [section] does not state, by the words each is stated in, and the gap it
/// may no longer claim.
///
/// **The fourth case is the contract's alone.** The rule reads fields,
/// getters and parameters, and leaves an initializing formal be: a value
/// type takes ownership of what its constructor is given. Nothing in code
/// shows that, so the section must say it, and must not call it a gap
/// ("does not copy yet").
List<String> vectorOwnershipGapsIn(String section) => <String>[
  for (final (words, name) in const <(String, String)>[
    ('public `final` field is the owner\'s live state', 'a field is live'),
    ('answer a copy the caller owns', 'a getter answers a copy'),
    ('read, never kept', 'a parameter is not kept'),
    (
      'takes ownership of the vectors its constructor',
      'a value type owns what its constructor is given',
    ),
  ])
    if (!section.replaceAll(RegExp(r'\s+'), ' ').contains(words)) name,
  if (RegExp(r'cop(y|ies) yet', caseSensitive: false).hasMatch(section))
    'a constructor that does not copy is called a gap',
];

List<({String subject, int line})> keptVectorParametersIn(String source) {
  final code = codeOf(source);
  int lineAt(int offset) =>
      '\n'.allMatches(code.substring(0, offset)).length + 1;
  final out = <({String subject, int line})>[];
  for (final t in _typeBodiesIn(code)) {
    if (!_reachable(t.type)) continue;
    final span = code.substring(t.open, t.close + 1);
    final depth = List<int>.filled(span.length + 1, 0);
    var level = 0;
    for (var i = 0; i < span.length; i++) {
      depth[i] = level;
      if (span[i] == '{') level++;
      if (span[i] == '}') level--;
    }
    final fields = <String>{
      for (final f in _vectorField.allMatches(span))
        if (depth[f.end - 1] == 1) f.group(1)!,
    };
    if (fields.isEmpty) continue;
    for (final m in _memberHead.allMatches(span)) {
      if (depth[m.start] != 1) continue;
      final name = m.group(1)!;
      final last = name.split('.').last;
      if (last.startsWith('_') || _notAMember.contains(name)) continue;
      final open = m.end - 1;
      final close = _matching(span, open);
      final vectors = <String>{
        for (final p in _vectorParameter.allMatches(
          span.substring(open + 1, close),
        ))
          p.group(1)!,
      };
      if (vectors.isEmpty) continue;
      final lead = RegExp(
        r'^\s*(?:async\s*)?(=>|\{|:)',
      ).firstMatch(span.substring(close + 1));
      if (lead == null) continue;
      final start = close + 1 + lead.end;
      final body = switch (lead.group(1)) {
        '=>' => span.substring(start, _statementEnd(span, start)),
        '{' => span.substring(start - 1, _matching(span, start - 1) + 1),
        _ => () {
          final stop = RegExp(r'\{|;|=>').firstMatch(span.substring(start));
          final at = stop == null ? span.length : start + stop.start;
          final tail = stop?.group(0) == '{'
              ? span.substring(at, _matching(span, at) + 1)
              : '';
          return '${span.substring(start, at)},$tail';
        }(),
      };
      for (final a in _bareAssignment.allMatches(body)) {
        if (fields.contains(a.group(1)) && vectors.contains(a.group(2))) {
          final constructor = name == t.type || name.startsWith('${t.type}.');
          out.add((
            subject: constructor
                ? '$name(${a.group(2)})'
                : '${t.type}.$last(${a.group(2)})',
            line: lineAt(t.open + m.start),
          ));
        }
      }
    }
  }
  return out;
}

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
  r'\b(?:LightNode|Light3D|ModelLight|LevelLight)(?:\.\w+)?\s*\(',
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
/// `LightNode`, `Light3D`, `ModelLight` or `LevelLight` constructor call, and
/// an `.intensity = <number>;` assignment, which in this repository is a light's
/// (a bloom's or a probe's intensity is a settings field, set through a
/// constructor). Nought is a light switched off, and a literal times
/// something (`2.5 * LightNode.defaultIntensity`) is a conversion, not a number
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

/// The level version from which a document's lights are written in lux and
/// candela: 4 → 5 multiplied every older one by the renderer's old unit.
const int levelVersionInLux = 5;

final RegExp _levelVersion = RegExp(r'^\s*"version":\s*(\d+)', multiLine: true);
final RegExp _jsonIntensity = RegExp(
  r'"intensity":\s*(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)',
);

/// Every light in the level document [json] whose intensity is below
/// [kSmallestLightIntensity], with its 1-based line: a light written in the
/// pre-1.0 unit into a document that has been in lux and candela since
/// [levelVersionInLux]. A document older than that is lifted on reading, so
/// its small numbers are the old unit on purpose and none counts.
///
/// A line scanner: the lights are the `"intensity"` keys after the
/// `"lights"` key and before the next top-level key, which is every level
/// the repository writes (two-space indentation, one key per line).
List<({String literal, int line})> smallLevelLightIntensitiesIn(String json) {
  final version = _levelVersion.firstMatch(json);
  if (version == null || int.parse(version.group(1)!) < levelVersionInLux) {
    return const <({String literal, int line})>[];
  }
  final found = <({String literal, int line})>[];
  var inLights = false;
  for (final (index, line) in json.split('\n').indexed) {
    if (line.startsWith('  "')) inLights = line.startsWith('  "lights"');
    if (!inLights) continue;
    final match = _jsonIntensity.firstMatch(line);
    if (match == null) continue;
    final value = double.parse(match.group(1)!);
    if (value > 0.0 && value < kSmallestLightIntensity) {
      found.add((literal: match.group(1)!, line: index + 1));
    }
  }
  return found;
}

// ------------------------------------------------------ a particle's world

final RegExp _particleSystem = RegExp(r'\bParticleSystem\s*\(');
final RegExp _givesParticlesAWorld = RegExp(r'\.world\s*=[^=]');
final RegExp _setsAWorld = RegExp(
  r'\bWorldProperties\b|\.collision\.properties\b|\bworld\.properties\b|'
  r'\bloaded\.collision\b|\bworldOver\s*\(|'
  r'\b(?:platformer|racing|shooter)World\b',
);

/// Whether [source] sets or reads a world other than the standard one: it
/// names `WorldProperties`, takes a loaded level's or a body's world
/// (`collision.properties`, `world.properties`, `loaded.collision`,
/// `Level.worldOver`), or a genre's own (`platformerWorld`, `racingWorld`,
/// `shooterWorld`).
bool setsAWorld(String source) => _setsAWorld.hasMatch(codeOf(source));

/// The 1-based lines of [source] that make a `ParticleSystem` while nothing
/// in [source] hands one its world (`particles.world = …`): sparks that fall
/// at the standard gravity and drift in no wind beside bodies in the
/// world a game set. Empty when [source] sets no world ([setsAWorld]).
List<int> particleSystemsWithoutWorldIn(String source) {
  final code = codeOf(source);
  if (!_setsAWorld.hasMatch(code) || _givesParticlesAWorld.hasMatch(code)) {
    return const <int>[];
  }
  return <int>[
    for (final match in _particleSystem.allMatches(code))
      '\n'.allMatches(code.substring(0, match.start)).length + 1,
  ];
}

// --------------------------------------------------- a property's reader

/// The members of `final class [type]` in a package's API snapshot [api]
/// that an application reads: its fields and getters by name, without the
/// static ones and `hashCode`.
Set<String> readableMembersIn(String api, String type) {
  final members = <String>{};
  var inside = false;
  for (final line in api.split('\n')) {
    if (!line.startsWith(' ')) {
      inside = RegExp(
        '^(?:\\w+ )*class ${RegExp.escape(type)}(?:\\s|\$)',
      ).hasMatch(line);
      continue;
    }
    if (!inside) continue;
    final member = RegExp(
      r'^  (?!static )(?:final |late )*[\w<>?, ]+ (?:get )?(\w+)$',
    ).firstMatch(line);
    if (member != null && member.group(1) != 'hashCode') {
      members.add(member.group(1)!);
    }
  }
  return members;
}

/// The property groups of `PhysicalMaterial` in the matter snapshot [api]:
/// its fields whose type is a `…Properties` group, by name.
Set<String> materialGroupsIn(String api) {
  final groups = <String>{};
  var inside = false;
  for (final line in api.split('\n')) {
    if (!line.startsWith(' ')) {
      inside = RegExp(r'^final class PhysicalMaterial(?:\s|$)').hasMatch(line);
      continue;
    }
    if (!inside) continue;
    final group = RegExp(r'^  final \w+Properties\?? (\w+)$').firstMatch(line);
    if (group != null) groups.add(group.group(1)!);
  }
  return groups;
}

/// Whether [source]'s code reads [member] of something: `.member` as a
/// whole word, a named argument (`member:`) and a comment not counting.
bool readsMember(String source, String member) => RegExp(
  '\\??\\.${RegExp.escape(member)}\\b(?!\\s*:)',
).hasMatch(codeOf(source));

// ------------------------------------------------- a section's fixture

/// The versions from [since] to [current] at which [exists] finds no file
/// for [fixture], `<N>` standing for the version: a section a format added
/// at [since] that no fixture of a later version carries.
List<int> versionsWithoutFixture(
  String fixture, {
  required int since,
  required int current,
  required bool Function(String path) exists,
}) => <int>[
  for (var version = since; version <= current; version++)
    if (!exists(fixture.replaceAll('<N>', '$version'))) version,
];

// ------------------------------------------------- what a fixture holds

/// The u32 little-endian word of [bytes] at [at], or null past the end.
int? _u32(List<int> bytes, int at) => at + 4 > bytes.length
    ? null
    : bytes[at] |
          bytes[at + 1] << 8 |
          bytes[at + 2] << 16 |
          bytes[at + 3] << 24;

/// `F3D\n`, the magic of `.f3d`.
const int _f3dMagic = 0x0A443346;

/// `F3DP`, the magic of `.f3dproj`.
const int _projectMagic = 0x50443346;

/// The section kinds the directory of [bytes] lists, a `.f3d` or a
/// `.f3dproj` read the way their readers walk them: the header's version,
/// the entry size it implies or names, then one kind per entry. Null for
/// anything else, or a directory that runs past the end.
///
/// **What the fixture rule could not see.** It counted a file per version
/// and never opened one, so seven `.f3d` kinds and three `.f3dproj` kinds
/// had no bytes anywhere and every check passed.
Set<int>? sectionKindsOf(List<int> bytes) {
  final magic = _u32(bytes, 0);
  final version = _u32(bytes, 4);
  final count = _u32(bytes, 8);
  if (version == null || count == null) return null;
  final (int header, int? entry) = switch (magic) {
    _f3dMagic => (16, version == 1 ? 16 : _u32(bytes, 12)),
    _projectMagic => version >= 3 ? (20, _u32(bytes, 16)) : (16, 16),
    _ => (0, null),
  };
  if (entry == null || entry < 16 || header + count * entry > bytes.length) {
    return null;
  }
  return <int>{
    for (var i = 0; i < count; i++) _u32(bytes, header + i * entry)!,
  };
}

/// The `static const int` constants of the class [className] in [source],
/// name to value: a format's section kinds, as `F3dSection` declares them.
Map<String, int> intConstantsOf(String source, String className) {
  final start = RegExp(
    'class\\s+${RegExp.escape(className)}\\b[^{]*\\{',
  ).firstMatch(source);
  if (start == null) return const <String, int>{};
  final end = source.indexOf('\n}', start.end);
  final body = source.substring(start.end, end < 0 ? source.length : end);
  return <String, int>{
    for (final match in RegExp(
      r'static\s+const\s+int\s+(\w+)\s*=\s*(\d+)\s*;',
    ).allMatches(codeOf(body)))
      match.group(1)!: int.parse(match.group(2)!),
  };
}

/// The version a fixture says it was written at: the u32 after the magic
/// of a `.f3d` or a `.f3dproj`, or the `version` of a JSON document. Null
/// where it says none this reads — a JSON shape from before the envelope,
/// or a binary layout of another kind.
///
/// A fixture under `v<N>/` that says another version is the wrong file
/// there: a reader would be held to a version nobody minted.
int? fixtureVersionOf(List<int> bytes) {
  final magic = _u32(bytes, 0);
  if (magic == _f3dMagic || magic == _projectMagic) return _u32(bytes, 4);
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
  return switch (decoded) {
    {'version': final int version} => version,
    _ => null,
  };
}

// ------------------------------------------------------------- the net wire

/// Every line of a wire snapshot ([text], the shape of
/// `packages/flutter3d_net/api/flutter3d_net.wire`) as a fact on its own: a
/// block's header, or `header / line` for a line inside it. Comments, blank
/// lines and the `protocol` line are not facts about a message.
List<String> wireFactsOf(String text) {
  final facts = <String>[];
  var header = '';
  for (final line in text.split('\n')) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    if (!line.startsWith(' ')) {
      if (line.startsWith('protocol ')) continue;
      header = line.trim();
      facts.add(header);
    } else {
      facts.add('$header / ${line.trim()}');
    }
  }
  return facts;
}

/// The protocol major a wire snapshot names, or null.
int? wireMajorOf(String text) => switch (RegExp(
  r'^protocol (\d+)\.\d+\s*$',
  multiLine: true,
).firstMatch(text)) {
  final RegExpMatch match => int.parse(match.group(1)!),
  null => null,
};

/// The facts of [base] that [current] no longer has, when both name the
/// same protocol major; nothing when [current] names a later one, which is
/// where a message may change.
List<String> wireFactsRemoved(String base, String current) {
  final major = wireMajorOf(current);
  if (major != null && major > (wireMajorOf(base) ?? major)) {
    return const <String>[];
  }
  final have = wireFactsOf(current).toSet();
  return <String>[
    for (final fact in wireFactsOf(base))
      if (!have.contains(fact)) fact,
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

/// Whether [source] declares a class that is a `GraphicsDevice`, which is
/// what makes a package a backend: one that `extends` it, as every backend
/// has since the device became an `abstract base class` in 1.0, or one that
/// `implements` it, as they did before. The declaration may span lines, as
/// `CpuDevice`'s `with` clause makes it.
///
/// **It read `implements` alone until 1.0.0-rc.1**, and every backend had
/// moved to `extends` by then, so the rule it serves found no backend at all
/// and held `SUPPORT.md` to nothing.
bool declaresGraphicsDevice(String source) => RegExp(
  r'^(?:[a-z]+ )*class \w+[^{;]*?\b(?:extends|implements)\b[^{;]*?'
  r'\bGraphicsDevice\b(?!\w)',
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

/// What [source], a file [depth] directories below the root of an example
/// written as from outside the repository (`examples/<name>/`), reaches
/// that a project outside the repository could not: another package's
/// `src/`, another package's `internal.dart` (what the engine's packages
/// share among themselves and nobody else builds on), and a relative path
/// out of the example (into `packages/`, say). [own] is the example's own
/// package name.
Set<String> outsideExampleReaches(
  String source, {
  required String own,
  required int depth,
}) => <String>{
  for (final package in foreignSrcImports(source, own)) 'package:$package/src/',
  for (final library in restrictedLibrariesIn(source))
    if (library.endsWith('/internal.dart') && packageOfUri(library) != own)
      library,
  for (final match in RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'":]+)['"]''',
    multiLine: true,
  ).allMatches(source))
    if (_climbs(match.group(1)!) > depth) match.group(1)!,
};

/// How far [path] climbs above where it starts, at its highest.
int _climbs(String path) {
  var at = 0;
  var highest = 0;
  for (final part in path.split('/')) {
    if (part == '..') {
      at -= 1;
      if (-at > highest) highest = -at;
    } else if (part.isNotEmpty && part != '.') {
      at += 1;
    }
  }
  return highest;
}

/// Why [pubspec], an outside example's, is not one a project outside the
/// repository could write: it may be published, or one of [repositoryPackages]
/// it depends on is reached some other way than by path to
/// `../../packages/<name>`, which is the override an outside project makes.
List<String> outsideExamplePubspecProblems(
  String pubspec,
  Set<String> repositoryPackages,
) {
  final lines = pubspec.split('\n');
  return <String>[
    if (!RegExp(
      r'''^publish_to:\s*['"]?none['"]?\s*$''',
      multiLine: true,
    ).hasMatch(pubspec))
      'it does not say `publish_to: none`: an example is not a package',
    for (var i = 0; i < lines.length; i++)
      if (RegExp(r'^\s+([a-z0-9_]+):\s*(\S*)\s*$').firstMatch(lines[i])
          case final match?
          when repositoryPackages.contains(match.group(1)) &&
              !RegExp(
                '^\\s+path:\\s*\\.\\./\\.\\./packages/${match.group(1)}\\s*\$',
              ).hasMatch(i + 1 < lines.length ? lines[i + 1] : ''))
        _notByPath(match.group(1)!),
  ];
}

String _notByPath(String package) =>
    '$package is not reached by `path: ../../packages/$package`';

/// What is wrong between the examples [onDisk] (`examples/<name>/` with a
/// pubspec) and the ones the root pubspec's `workspace:` [listed], as
/// `(name, why)`: one on disk the workspace leaves out, and one listed that
/// is not there.
List<(String, String)> exampleMembershipProblems(
  Set<String> onDisk,
  Set<String> listed,
) => <(String, String)>[
  for (final name in onDisk.difference(listed).toList()..sort())
    (
      name,
      'is not in the root pubspec\'s `workspace:`, so nothing analyses or '
          'tests it',
    ),
  for (final name in listed.difference(onDisk).toList()..sort())
    (name, 'is in the workspace and not on disk with a pubspec'),
];

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

/// What a CLI surface snapshot promises, as words a release can lose: the
/// subcommands (`== convert ==`) and flags (`--dry-run`) as `convert` and
/// `convert --dry-run`; each code of the exit-code table under the
/// top-level usage with the first word of its meaning, as `exit 3
/// refused`; and every key of each `--json` body, nested ones by their
/// path, as `--json convert reports[].mapped`.
///
/// **A key gone is a break, and so is a code renumbered.** A script reads
/// `.reports[0].mapped` and checks `$? -eq 3`; the flags were the only
/// part of the promise a regenerated snapshot could not drop unlabelled.
Set<String> cliSurfaceWords(String surface) {
  final words = <String>{};
  var command = 'flutter3d';
  var inExits = false;
  for (final line in surface.split('\n')) {
    final heading = RegExp(r'^== (\S+) ==$').firstMatch(line);
    if (heading != null) {
      command = heading[1]!;
      inExits = false;
      if (command != '--json') words.add(command);
      continue;
    }
    if (command == '--json') {
      final body = RegExp(r'^(\S+) (\{.*\})\s*$').firstMatch(line);
      if (body != null) {
        for (final key in cliJsonKeyPaths(body[2]!)) {
          words.add('--json ${body[1]} $key');
        }
      }
      continue;
    }
    if (command == 'flutter3d') {
      if (line.trim() == 'Exit codes:') {
        inExits = true;
        continue;
      }
      final code = RegExp(r'^  (\d+)  ([A-Za-z]+)').firstMatch(line);
      if (inExits && code != null) words.add('exit ${code[1]} ${code[2]}');
      if (line.trim().isEmpty) inExits = false;
    }
    for (final flag in RegExp(
      r'(?<![\w-])--[a-z][a-z0-9-]*',
    ).allMatches(line)) {
      words.add('$command ${flag[0]}');
    }
  }
  return words;
}

/// Every key a `--json` body shape names (`{a, b?, c: [{d}]}`), nested
/// keys by their path: `a`, `b`, `c`, `c[].d`. A parenthesised note
/// (`current? (with --check)`) is not a key.
List<String> cliJsonKeyPaths(String shape) {
  final keys = <String>[];
  final text = shape.replaceAll(RegExp(r'\([^)]*\)'), '');
  var at = 0;
  void skipSpace() {
    while (at < text.length && text[at] == ' ') {
      at++;
    }
  }

  void object(String prefix) {
    at++; // {
    while (at < text.length && text[at] != '}') {
      skipSpace();
      final start = at;
      while (at < text.length && !',:}'.contains(text[at])) {
        at++;
      }
      final name = text.substring(start, at).trim().replaceAll('?', '');
      if (name.isNotEmpty) keys.add('$prefix$name');
      if (at < text.length && text[at] == ':') {
        at++;
        skipSpace();
        if (at < text.length && text[at] == '[') {
          at++;
          skipSpace();
          if (at < text.length && text[at] == '{') object('$prefix$name[].');
          while (at < text.length && text[at] != ']') {
            at++;
          }
          at++; // ]
        } else if (at < text.length && text[at] == '{') {
          object('$prefix$name.');
        }
      }
      skipSpace();
      if (at < text.length && text[at] == ',') at++;
    }
    at++; // }
  }

  final open = text.indexOf('{');
  if (open < 0) return keys;
  at = open;
  object('');
  return keys;
}

/// What in [source] decides a conformance badge rather than reading one: a
/// `conformant@` text it builds, and a `const List<String>` naming two or
/// more of the suite's [checks], a copy that can disagree with the suite.
List<String> ownBadgeJudgesIn(String source, List<String> checks) {
  final code = codeOf(source);
  return <String>[
    if (RegExp('[\'"]conformant@').hasMatch(code))
      'builds a `conformant@` badge of its own',
    for (final list in RegExp(
      r'const\s+List<String>\s+(\w+)\s*=\s*<String>\[([^\]]*)\]',
    ).allMatches(code))
      if (<String>{
            for (final item in RegExp(r"'([^']*)'").allMatches(list[2]!))
              if (checks.contains(item[1])) item[1]!,
          }
          case final copied when copied.length >= 2)
        _copiedChecks(list[1]!, copied),
  ];
}

String _copiedChecks(String list, Set<String> copied) =>
    'keeps `$list`, a copy of the suite\'s checks (${copied.join(', ')})';

/// Whether [source] reads `CI` as a compile-time define
/// (`bool.fromEnvironment('CI')`), which no CI runner passes, instead of
/// from the process's environment.
bool readsCiAsDefine(String source) =>
    RegExp(r'''fromEnvironment\(\s*['"]CI['"]''').hasMatch(codeOf(source));

/// The keys `flutter3d_assets.yaml`'s reader accepts, as `format`,
/// `rules.glob` and `classes.lods`, and the format version it declares.
({Set<String> keys, int? version}) assetsManifestShapeIn(String source) {
  final code = codeOf(source);
  final keys = <String>{
    for (final (name, prefix) in const <(String, String)>[
      ('_topLevelKeys', ''),
      ('_classKeys', 'classes.'),
      ('_ruleKeys', 'rules.'),
    ])
      if (RegExp(
            'const Set<String> $name = <String>\\{([^}]*)\\}',
          ).firstMatch(code)
          case final set?)
        for (final key in RegExp(r"'([^']*)'").allMatches(set[1]!))
          '$prefix${key[1]}',
  };
  final version = RegExp(
    r'static const int formatVersion\s*=\s*(\d+)',
  ).firstMatch(code);
  return (keys: keys, version: version == null ? null : int.parse(version[1]!));
}

/// Why the manifest reader [now] does not move its format with its keys
/// against [released]: a key it reads that the released reader refused,
/// with the same `formatVersion`. Empty when the keys did not grow, or the
/// version did.
///
/// **A 1.0 build refuses an unknown key**, naming the keys it reads; only a
/// newer `format:` gets the sentence "update flutter3d_build". A key added
/// without the bump gives a team on two releases the first message for a
/// file the second wrote correctly.
List<String> assetsManifestGrowthProblems(String released, String now) {
  final was = assetsManifestShapeIn(released);
  final current = assetsManifestShapeIn(now);
  final added = current.keys.difference(was.keys);
  return switch ((was.version, current.version)) {
    _ when added.isEmpty => const <String>[],
    (final int then, final int version) when version <= then => <String>[
      _manifestGrowth(added, then, version),
    ],
    _ => const <String>[],
  };
}

String _manifestGrowth(Set<String> added, int then, int version) =>
    'reads ${added.map((String k) => '`$k`').join(', ')}, which format '
    '$then did not, and `formatVersion` is still $version: bump it, so a '
    'build that cannot read the key says "update flutter3d_build" instead '
    'of "unknown key"';

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

/// The literals of the `const` collection [name] declares in [code], which
/// has its comments removed: a map's keys with their values as written, a
/// set's entries with a null value. Null when [code] declares no [name].
Map<String, String?>? _constLiterals(String code, String name) {
  final declaration = RegExp(
    'const\\s+(?:Map|Set)<[^>]*>\\s+$name\\s*=\\s*<[^>]*>\\s*\\{(.*?)\\};',
    dotAll: true,
  ).firstMatch(code);
  if (declaration == null) return null;
  return <String, String?>{
    for (final entry in RegExp(
      r"'([^']*)'\s*(?::\s*([^,}]+))?",
    ).allMatches(declaration.group(1)!))
      entry.group(1)!: entry.group(2)?.trim(),
  };
}

/// A word-shaped string literal: two characters or more, so the swizzle's
/// `'x'` and `'r'` are not taken for words.
final RegExp _wordLiteral = RegExp(r"'([A-Za-z_][A-Za-z0-9_]+)'");

/// The words the kernel parser's code [code] reads as its own: the literals
/// of its `case` patterns (up to a `when`), of its switch expressions' arms,
/// and of the tokens it asks for with `_is`, `_accept` and `_expect`.
Set<String> _kernelDispatchWords(String code) {
  final words = <String>{};
  void collect(String text) {
    for (final m in _wordLiteral.allMatches(text)) {
      words.add(m.group(1)!);
    }
  }

  for (final m in RegExp(
    r'\bcase\s+([^:]*?)(?:\bwhen\b[^:]*)?:',
    dotAll: true,
  ).allMatches(code)) {
    collect(m.group(1)!);
  }
  for (final m in RegExp(
    r"('[^'\n]*'(?:\s*\|\|\s*'[^'\n]*')*)\s*=>",
  ).allMatches(code)) {
    collect(m.group(1)!);
  }
  for (final m in RegExp(
    r"\b_(?:is|accept|expect)\(\s*('[^'\n]*')\s*\)",
  ).allMatches(code)) {
    collect(m.group(1)!);
  }
  return words;
}

/// What breaks "every word of the kernel language carries the version it
/// arrived in", given the word table's source [words], the parser's
/// [parser] and [newest], the version this build reads.
///
/// **A word without a version is reserved in every version**, so the
/// version that adds it refuses every older kernel naming a local after
/// it. Four ways back to that are closed: a word the parser dispatches on
/// that the table does not version (`kernelWordVersions`) or name as the
/// other language's (`kernelOtherLanguageWords`); a version that is not a
/// number this build reads; a word in `kernelWordsReservedEarly` that is
/// not version 2's (the one exception, frozen); and a `const Set` of words
/// in the parser itself, the one list for every version it used to keep.
List<String> kernelWordProblems({
  required String words,
  required String parser,
  required int newest,
}) {
  final problems = <String>[];
  final table = codeOf(words);
  final versions = _constLiterals(table, 'kernelWordVersions');
  final early = _constLiterals(table, 'kernelWordsReservedEarly');
  final other = _constLiterals(table, 'kernelOtherLanguageWords');
  if (versions == null || early == null || other == null) {
    const missing =
        'the word table declares no kernelWordVersions, '
        'kernelWordsReservedEarly or kernelOtherLanguageWords';
    return <String>[missing];
  }
  final since = <String, int>{};
  for (final MapEntry(key: word, value: written) in versions.entries) {
    final version = written == null ? null : int.tryParse(written);
    if (version == null || version < 1 || version > newest) {
      problems.add(
        '"$word" arrives in "$written", which is not a version from 1 to '
        '$newest',
      );
    } else {
      since[word] = version;
    }
    if (other.containsKey(word)) {
      problems.add('"$word" is a kernel word and the other language\'s');
    }
  }
  for (final word in early.keys) {
    if (since[word] != 2) {
      problems.add(
        '"$word" is taken before its version arrives, and only version 2\'s '
        'words are: a later word is taken only in a source of its version',
      );
    }
  }
  final code = codeOf(parser);
  for (final word in _kernelDispatchWords(code)) {
    if (!versions.containsKey(word) && !other.containsKey(word)) {
      problems.add(
        'the parser reads "$word" as a word, and kernelWordVersions does not '
        'say which version it arrived in',
      );
    }
  }
  for (final m in RegExp(r'const\s+Set<String>\s+(\w+)').allMatches(code)) {
    problems.add(
      'the parser keeps a word list of its own, ${m.group(1)}, which no '
      'version reaches: version its words in kernelWordVersions',
    );
  }
  return problems;
}

// -------------------------------------------------------------- check names

/// `ToolName.pattern` as `flutter3d_mcp`'s `tool_table.dart` writes it: a
/// published tool name, lower-case words joined by dots, at least two.
/// `_checkNamesFollowToolNames` holds the file to this text, so the two
/// cannot drift.
const String toolNamePatternSource =
    r'^[a-z][A-Za-z0-9_]*(\.[a-z][A-Za-z0-9_]*)+$';

/// The string items of `const List<String> [name] = <String>[ … ];` in
/// [source], in order, or null when [source] declares no such list.
List<String>? constStringListIn(String source, String name) {
  final match = RegExp(
    'const\\s+List<String>\\s+${RegExp.escape(name)}\\s*=\\s*'
    '(?:<String>)?\\[([^\\]]*)\\]',
  ).firstMatch(codeOf(source));
  if (match == null) return null;
  return <String>[
    for (final item in RegExp(r"'([^'\\]*)'").allMatches(match.group(1)!))
      item.group(1)!,
  ];
}

/// The check names [source] reports an outcome under: each `check: '…'`
/// and each `'render.…'` string literal.
Set<String> reportedCheckNamesIn(String source) => <String>{
  for (final m in RegExp(
    r"""\bcheck:\s*'([^'\\]*)'|'(render\.[^'\\]*)'""",
  ).allMatches(codeOf(source)))
    m.group(1) ?? m.group(2)!,
};

/// The names of [names] that are not check names: each must match
/// [toolNamePatternSource] whole, dotted words with no space (`plugin.manifest`,
/// `render.litModel`), because a check's name is data in a report and a badge;
/// with [area] set, also those not in that area (`render.…`).
List<String> badCheckNames(Iterable<String> names, {String? area}) {
  final tool = RegExp(toolNamePatternSource);
  return <String>[
    for (final name in names)
      if (!tool.hasMatch(name) || (area != null && !name.startsWith('$area.')))
        name,
  ];
}

// ------------------------------------------- the shader ABI and vocabularies

/// The facts of a one-fact-a-line file: every line but the blank ones and
/// the `#` comments.
List<String> factLines(String text) => <String>[
  for (final line in text.split('\n'))
    if (line.isNotEmpty && !line.startsWith('#')) line,
];

/// The shapes a line of `flutter3d_shaders.abi` may have.
final List<RegExp> _abiLineShapes = <RegExp>[
  RegExp(r'^entry \w+ (?:vertex|fragment|compute)$'),
  RegExp(r'^stage \w+ block \w+$'),
  RegExp(r'^stage \w+ block \w+ member \w+ \d+ \d+ \d+ \w+$'),
  RegExp(r'^stage \w+ sampler \w+ (?:sampler|image|texture)\w*$'),
  RegExp(r'^(?:vertex|fragment) \w+ (?:in|out) \d+ \w+ \w+$'),
  RegExp(r'^vertex \w+ format \d+ \w+ \w+$'),
];

/// What breaks the shape of the shader ABI file [abi]: a line of no known
/// shape (a sampler written without its kind among them), a kind of fact
/// the file must hold and does not (samplers with kinds, varyings both
/// ways, attribute formats), or a vertex input with no format beside it.
///
/// **The only-grows rule is blind to a fact the file never had.** It reads
/// lines, so a writer that stopped writing varyings or sampler kinds would
/// leave nothing to lose, and a minor could insert a varying before
/// `v_instance` or turn a 2D sampler into a cube with every check green.
List<String> shaderAbiShapeProblems(String abi) {
  final lines = factLines(abi);
  final problems = <String>[];
  for (final line in lines) {
    if (!_abiLineShapes.any((RegExp shape) => shape.hasMatch(line))) {
      problems.add(
        '`$line` is not a line of the shader ABI: an entry, a block, a '
        'member, a sampler with its kind, an attribute with its format, or '
        'a varying',
      );
    }
  }
  for (final (what, shape) in <(String, RegExp)>[
    ('samplers with their kinds', RegExp(r'^stage \w+ sampler \w+ \w+$')),
    ('vertex stages\' varyings', RegExp(r'^vertex \w+ out ')),
    ('fragment stages\' varyings', RegExp(r'^fragment \w+ in ')),
    ('attribute formats', RegExp(r'^vertex \w+ format ')),
  ]) {
    if (!lines.any(shape.hasMatch)) {
      problems.add('holds no $what, which a prebuilt stage is bound by');
    }
  }
  final formats = <String>{
    for (final line in lines)
      if (RegExp(r'^vertex (\w+) format (\d+) (\w+) ').firstMatch(line)
          case final m?)
        '${m[1]} ${m[2]} ${m[3]}',
  };
  for (final line in lines) {
    if (RegExp(r'^vertex (\w+) in (\d+) \w+ (\w+)$').firstMatch(line)
        case final m? when !formats.contains('${m[1]} ${m[2]} ${m[3]}')) {
      problems.add('`$line` has no format beside it');
    }
  }
  return problems;
}

/// `<language> version <N>`: the newest version of a language a build
/// reads, the one line of a vocabulary that is not a word.
final RegExp _vocabularyVersion = RegExp(r'^\w+ version (\d+)$');

/// What breaks "a language's vocabulary grows only with its version",
/// given the [base] recorded at the tag and the package's [current] file.
///
/// **A word new since 1.0 that arrives in a version 1.0 read is a break**:
/// a 1.0 build reading a source that uses it refuses with an unknown name,
/// not with the sentence naming the version to update to, and a 1.x build
/// takes a name from a source that bound it. So every line the base lacks
/// carries a version above the base's newest, and at most this build's
/// newest; every line of the base is still here; and the newest version
/// never goes down.
List<String> vocabularyProblems({
  required String base,
  required String current,
}) {
  int? newest(List<String> lines) {
    for (final line in lines) {
      if (_vocabularyVersion.firstMatch(line) case final m?) {
        return int.parse(m[1]!);
      }
    }
    return null;
  }

  final was = factLines(base);
  final now = factLines(current);
  final (baseNewest, currentNewest) = (newest(was), newest(now));
  if (baseNewest == null || currentNewest == null) {
    return <String>[
      'says no "<language> version <N>", the newest version it reads',
    ];
  }
  final have = now.toSet();
  final had = was.toSet();
  String gone(String line) =>
      '`$line`, which the base recorded, is gone: a word a 1.0 source may '
      'use is one every 1.x reads as it did';
  return <String?>[
    if (currentNewest < baseNewest)
      'reads up to version $currentNewest, and the base read $baseNewest',
    for (final line in was)
      if (!_vocabularyVersion.hasMatch(line) && !have.contains(line))
        gone(line),
    for (final line in now)
      if (!_vocabularyVersion.hasMatch(line) && !had.contains(line))
        switch (int.tryParse(line.split(' ').last)) {
          null => '`$line` does not end in the version it arrived in',
          final since when since <= baseNewest =>
            '`$line` is new since the base and arrives in version $since, '
                'which the base already read: a build of that version '
                'refuses a source using it by an unknown name, not by its '
                'version. It belongs to version ${baseNewest + 1}',
          final since when since > currentNewest =>
            '`$line` arrives in version $since, after $currentNewest, the '
                'newest this build reads',
          _ => null,
        },
  ].nonNulls.toList();
}

/// The tag a base under `tool/api/abi_base/` says it was recorded from,
/// or null for one recorded from the working tree.
String? abiBaseTag(String base) =>
    RegExp(r'^# Recorded from (v\S+) \(').firstMatch(base)?.group(1);

/// What breaks "the base is the tag's": [base] says nowhere what it was
/// recorded from, or names a tag whose file ([atTag], null where this
/// clone has no such tag) holds other facts.
///
/// **A base edited by hand after the tag** would move the promise without
/// a release that made it. Recorded by `api_snapshot:abi_base`, it says
/// where it came from on its first line, and a base from a tag is that
/// tag's file, fact for fact.
List<String> abiBaseProblems({
  required String base,
  required String? Function(String tag) atTag,
}) {
  if (!base.startsWith('# Recorded from ')) {
    const unrecorded =
        'says nowhere what it was recorded from: record it with `dart run '
        'api_snapshot:abi_base` in tool/api';
    return const <String>[unrecorded];
  }
  final tag = abiBaseTag(base);
  final tagged = tag == null ? null : atTag(tag);
  if (tag == null || tagged == null) return const <String>[];
  final (was, now) = (factLines(tagged), factLines(base));
  if (was.length == now.length &&
      Iterable<int>.generate(was.length).every((int i) => was[i] == now[i])) {
    return const <String>[];
  }
  final first = Iterable<int>.generate(
    was.length < now.length ? was.length : now.length,
  ).firstWhere((int i) => was[i] != now[i], orElse: () => was.length);
  final from = first < was.length ? ', from `${was[first]}`' : '';
  final differs =
      'is not what $tag holds (${now.length} facts against ${was.length}'
      '$from): record it again with `dart run api_snapshot:abi_base $tag`';
  return <String>[differs];
}

/// What breaks "every frame resource says what it holds": a resource
/// [framePlan] declares (`FrameResourceIds`) with no row in the table of
/// [contracts]' "Frame resources a stage reads", a row naming no resource,
/// or a row that says nothing.
///
/// **A plugin reads every one of them by name**, so each is a contract the
/// day it is readable, and the table says which encodings are frozen and
/// which are not; a resource added without a row is one an author cannot
/// tell the promise of.
List<String> frameResourceRowProblems({
  required String framePlan,
  required String contracts,
}) {
  final ids = <String>{
    for (final m in RegExp(
      r"static const ResourceId \w+ = ResourceId\(\s*'(f3d\.[a-z_]+)'",
    ).allMatches(codeOf(framePlan)))
      m[1]!,
    // The one family a function names, a cube per probe.
    if (framePlan.contains("ResourceId('f3d.reflection_probe_\$index')"))
      'f3d.reflection_probe_<n>',
  };
  final start = contracts.indexOf('### Frame resources a stage reads');
  if (start < 0) {
    return <String>['has no "Frame resources a stage reads" section'];
  }
  final end = contracts.indexOf('\n## ', start);
  final section = contracts.substring(start, end < 0 ? contracts.length : end);
  final rows = <String, String>{
    for (final m in RegExp(
      r'^\| `([^`]+)` \|([^\n]*)\|\s*$',
      multiLine: true,
    ).allMatches(section))
      m[1]!: m[2]!.trim(),
  };
  String unsaid(String id) =>
      '`$id` is a frame resource a plugin may read, and the table does not '
      'say what it holds';
  return <String>[
    for (final id in ids)
      if (!rows.containsKey(id)) unsaid(id),
    for (final MapEntry(key: id, value: text) in rows.entries) ...<String>[
      if (!ids.contains(id)) '`$id` has a row and is no frame resource',
      if (text.isEmpty) '`$id` has a row that says nothing',
    ],
  ];
}

// ------------------------------------------------------------ taken names

/// The lines of [source] where an `ArgumentError` is thrown for a name
/// already taken: a `throw ArgumentError(…)` or `throw ArgumentError.value(…)`
/// whose arguments say `already` or `taken`.
///
/// The arguments are read to the end of the throw — its parentheses
/// balanced, outside string literals — so a message that spans lines, or
/// holds a `;` or a `)` of its own, is read whole. Comments are not code: a
/// doc saying a registry throws an `ArgumentError` for a name already taken
/// is not the throw.
List<int> takenNameArgumentErrorsIn(String source) {
  final out = <int>[];
  final start = RegExp(r'throw\s+ArgumentError(?:\.value)?\s*\(');
  for (final match in start.allMatches(source)) {
    final lineStart = source.lastIndexOf('\n', match.start) + 1;
    final before = source.substring(lineStart, match.start).trimLeft();
    if (before.startsWith('//')) continue;
    var depth = 1;
    String? quote;
    var i = match.end;
    for (; i < source.length && depth > 0; i++) {
      final c = source[i];
      if (quote != null) {
        if (c == r'\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      }
    }
    final arguments = source.substring(match.end, i);
    if (!RegExp(r'\b(already|taken)\b').hasMatch(arguments)) continue;
    out.add('\n'.allMatches(source.substring(0, match.start)).length + 1);
  }
  return out;
}

// ------------------------------------------------------ replays and saves

/// [source] with each line's `//` comment blanked, the lines kept, so an
/// offset still maps to its line.
String _linesWithoutComments(String source) =>
    source.split('\n').map(_codeOf).join('\n');

/// The 1-based line of [offset] in [text].
int _lineAt(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

/// The lines of [source] that play a recorded run's tape without checking
/// the run: `InputTapePlayback.tape(demo.tape)` or
/// `OrderTapePlayback.tape(match.tape)`, a `.tape` read off something.
///
/// **A replay that does not ask which simulation the run was recorded on
/// diverges instead of refusing**, and eight of them did: each built the
/// playback from `demo.tape` and none called `checkSimulation`. The unnamed
/// constructors take the recording and check it themselves; the raw `.tape`
/// form is for a tape the run made itself (a rewind point's), which is never
/// a `.tape` read off a file's document.
List<int> uncheckedRecordedPlaybacksIn(String source) {
  final code = _linesWithoutComments(source);
  final raw = RegExp(
    r'\b(?:InputTapePlayback|OrderTapePlayback)\.tape\(\s*[A-Za-z_]\w*\.tape\b',
  );
  return <int>[for (final m in raw.allMatches(code)) _lineAt(code, m.start)];
}

/// Each `Snapshot(...)` in [source] that wraps another snapshot's data
/// (its argument reads a `.data`, or a `data` taken out of one) and passes
/// no `requires:`, with the
/// argument as written, whitespace folded, for an exemption to name.
///
/// **A save that forgets which plugins it holds restores without them.**
/// Four paths built a snapshot again from one's `data` and dropped its
/// `requires`, so a save holding a plugin's state came back without the
/// plugin, and was written once more requiring nothing.
List<({int line, String argument})> snapshotsDroppingRequiresIn(String source) {
  final code = _linesWithoutComments(source);
  final found = <({int line, String argument})>[];
  for (final m in RegExp(r'\bSnapshot\(').allMatches(code)) {
    var depth = 1;
    var at = m.end;
    while (at < code.length && depth > 0) {
      final c = code[at];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') depth--;
      at++;
    }
    final inside = code.substring(m.end, at - 1);
    // The constructor's own declaration, `Snapshot(this.data, ...)`.
    if (inside.trimLeft().startsWith('this.')) continue;
    // `.data` read off a snapshot, or a `data` taken out of one: an
    // identifier, never the `'data'` key of a part's map.
    if (!RegExp(r'''(?<!['"\w])data\b(?!['"])''').hasMatch(inside)) continue;
    if (RegExp(r'\brequires\s*:').hasMatch(inside)) continue;
    found.add((
      line: _lineAt(code, m.start),
      argument: inside
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .replaceFirst(RegExp(r',$'), ''),
    ));
  }
  return found;
}

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

  // A recorded run's tape played without asking which simulation it was
  // recorded on, and a snapshot built again without what it requires.
  fires(
    'unchecked recorded playbacks',
    uncheckedRecordedPlaybacksIn(
      'final p = InputTapePlayback.tape(demo.tape);',
    ).isNotEmpty,
    'InputTapePlayback.tape(demo.tape)',
  );
  fires(
    'unchecked recorded playbacks',
    uncheckedRecordedPlaybacksIn(
      'final p = OrderTapePlayback.tape(\n  match.tape,\n);',
    ).isNotEmpty,
    'OrderTapePlayback.tape over two lines',
  );
  quiet(
    'unchecked recorded playbacks',
    uncheckedRecordedPlaybacksIn(
      'loop.playback = InputTapePlayback.tape(point.tapeToPoint);\n'
      'final q = InputTapePlayback(demo, simulation: running);\n'
      '// InputTapePlayback.tape(demo.tape) is what this forbids',
    ).isEmpty,
    'a rewind point\'s tape, the checked form and a comment',
    'a tape the run made itself is no recording, and prose is not code',
  );
  fires(
    'snapshots dropping requires',
    snapshotsDroppingRequiresIn(
          "run: Snapshot(run),\nfinal s = Snapshot(<String, Object?>{\n"
          "  part: <String, Object?>{'version': 1, 'data': runState.data},\n"
          '});',
        ).length ==
        1,
    'Snapshot({... runState.data}) without requires',
  );
  quiet(
    'snapshots dropping requires',
    snapshotsDroppingRequiresIn(
      'Snapshot(<String, Object?>{\n'
      "  id: <String, Object?>{'data': runState.data},\n"
      '}, requires: runState.requires);\n'
      'const Snapshot(<String, Object?>{});\n'
      'Snapshot.fromJson(json);\n'
      'const Snapshot(this.data, {this.requires = const <String>[]});',
    ).isEmpty,
    'a snapshot that carries requires, an empty one, and a read',
    'only a snapshot rebuilt from another\'s data can drop what it requires',
  );
  fires(
    'snapshots dropping requires',
    snapshotsDroppingRequiresIn(
          'Snapshot(\n  data.cast<String, Object?>(),\n)',
        ).singleOrNull?.argument ==
        'data.cast<String, Object?>()',
    'the argument an exemption names',
  );

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

  // Taken names.
  fires(
    'taken names',
    takenNameArgumentErrorsIn(
          "    throw ArgumentError.value(\n      step.name,\n      'step',\n"
          "      'a step of this name is already added, by \$owner',\n    );\n",
        ).join(',') ==
        '1',
    'a value error naming a step already added, over four lines',
  );
  fires(
    'taken names',
    takenNameArgumentErrorsIn(
      "final x = y ?? (throw ArgumentError('is (one) of ours; "
      "the name is taken'));",
    ).isNotEmpty,
    'a message with a parenthesis and a semicolon of its own',
  );
  quiet(
    'taken names',
    takenNameArgumentErrorsIn(
      "throw ArgumentError.value(name, 'at', 'is not an anchor here');\n"
      "throw NameTakenException(name, what: 'the node');\n"
      '/// Throws an [ArgumentError] for a name already taken.\n'
      "// throw ArgumentError('already');\n",
    ).isEmpty,
    'a refusal of something else, the typed throw, a doc and a comment',
    'only a thrown ArgumentError that says the name is taken breaks the rule',
  );

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
      'LightNode(intensity: 2.5 * LightNode.defaultIntensity)\n'
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
  // A level's own lights: the showcase's closet was lit with a 6.0 that
  // since 1.0 is six candela.
  fires(
    'light intensities',
    smallLightIntensitiesIn(
      'LevelLight(\n  position: Vector3(2, 3, 2),\n  intensity: 6.0,\n)',
    ).isNotEmpty,
    'LevelLight(intensity: 6.0)',
  );
  fires(
    'level light intensities',
    smallLevelLightIntensitiesIn(
          '{\n  "version": 5,\n  "lights": [\n    {\n'
          '      "intensity": 9.0,\n      "range": 16.0\n    }\n  ]\n}',
        ).single.line ==
        5,
    'a version 5 level with a light of 9.0',
  );
  quiet(
    'level light intensities',
    smallLevelLightIntensitiesIn(
      '{\n  "version": 1,\n  "lights": [\n    {\n'
      '      "intensity": 9.0\n    }\n  ]\n}\n'
      '{\n  "version": 5,\n  "lights": [\n    {\n'
      '      "intensity": 52115.25\n    }\n  ],\n  "entities": [\n    {\n'
      '      "intensity": 0.5\n    }\n  ]\n}',
    ).isEmpty,
    'a version 1 level, a light in candela and a probe\'s intensity',
    'an old document is lifted by the old unit on reading, and an entity '
        'is not a light',
  );

  // A vector's owner. The first is the camera that moved through its
  // collision when a caller scaled its eye; the second the spring whose
  // event carried its live position; the third the focus a brain read out
  // of the system's list.
  final live = liveVectorGettersIn(
    'final class PhotoCamera {\n'
    '  final Vector3 _eye = Vector3.zero();\n'
    '  Vector3 get eye => _eye;\n'
    '  Vector3 get target => _eye + forward;\n'
    '}\n'
    'final class Spring {\n'
    '  Vector3 get origin => collider.position;\n'
    '  Vector3 get copied => collider.position.clone();\n'
    '}\n'
    'final class ActorSystem {\n'
    '  Vector3 get focus => _foci[_at];\n'
    '  Vector3 velocityOf(int i) => _velocities[i];\n'
    '  Vector3 get heading {\n'
    '    if (_still) return _zero;\n'
    '    return _wish;\n'
    '  }\n'
    '  Aabb3 get bounds => _bounds ??= Aabb3();\n'
    '}\n',
  ).map((({String subject, int line}) h) => h.subject).toSet();
  fires(
    'vector getters',
    live.containsAll(<String>{
      'PhotoCamera.eye',
      'Spring.origin',
      'ActorSystem.focus',
      'ActorSystem.velocityOf',
      'ActorSystem.heading',
      'ActorSystem.bounds',
    }),
    'a private field, another object\'s field, a list element, an …Of '
        'query, a block body and a ??= cache',
  );
  quiet(
    'vector getters',
    live.length == 6 &&
        liveVectorGettersIn(
          'final class _Hidden { Vector3 get at => _at; }\n'
          'extension on Body { Vector3 get at => _at; }\n'
          'final class Probe {\n'
          '  Vector3 get up {\n'
          '    final out = Vector3.zero();\n'
          '    return out;\n'
          '  }\n'
          '  Vector3? get none => null;\n'
          '  Vector3 get _own => _at;\n'
          '  // Vector3 get commented => _at;\n'
          '}\n',
        ).isEmpty,
    'an operator, a clone, a private type, an unnamed extension, a vector '
        'the getter made, null, a private getter and a comment',
    'each answers a vector nobody else holds, or none a caller can reach',
  );
  final kept = keptVectorParametersIn(
    'final class Rig {\n'
    '  Vector3 _target = Vector3.zero();\n'
    '  final Vector3 _eye;\n'
    '  Vector3 _look = Vector3.zero();\n'
    '  Rig(Vector3 eye) : _eye = eye;\n'
    '  set target(Vector3 value) => _target = value;\n'
    '  void lookAt(Vector3 at, {double lag = 0.0}) {\n'
    '    _look = at;\n'
    '  }\n'
    '}\n',
  ).map((({String subject, int line}) h) => h.subject).toSet();
  fires(
    'kept vector parameters',
    kept.containsAll(<String>{
      'Rig(eye)',
      'Rig.target(value)',
      'Rig.lookAt(at)',
    }),
    'an initializer list, a setter and a method that keep the caller\'s '
        'vector',
  );
  quiet(
    'kept vector parameters',
    kept.length == 3 &&
        keptVectorParametersIn(
          'final class Rig {\n'
          '  final Vector3 _target = Vector3.zero();\n'
          '  final Vector3 eye;\n'
          '  Vector3 _look = Vector3.zero();\n'
          '  Rig(this.eye);\n'
          '  set target(Vector3 value) => _target.setFrom(value);\n'
          '  void lookAt(Vector3 at) {\n'
          '    _look = at.clone();\n'
          '  }\n'
          '  void _keep(Vector3 at) => _look = at;\n'
          '}\n'
          'final class _Hidden {\n'
          '  Vector3 _at = Vector3.zero();\n'
          '  void put(Vector3 at) => _at = at;\n'
          '}\n',
        ).isEmpty,
    'a copy into the field, a clone, an initializing formal, a private '
        'member and a private type',
    'a copy is not the caller\'s vector, and an initializing formal is '
        'how a value type is declared',
  );

  fires(
    'a live getter\'s reason',
    liveGetterReasonProblem(
              'read per shape by the broadphase every step',
              '',
            ) !=
            null &&
        liveGetterReasonProblem(
              '$liveCacheWords; recomputed when read',
              'The world transform.',
            ) !=
            null &&
        liveGetterReasonProblem(
              '$liveCacheWords, recomputed when read',
              'Live: the object\'s own cache, read-only by contract.',
            ) !=
            null,
    'an inner-loop reason, a cache whose doc does not say it is live, and a '
        'reason that runs on past the clause',
  );
  quiet(
    'a live getter\'s reason',
    liveGetterReasonProblem('`CameraRig.eye` answers a copy', '') == null &&
        liveGetterReasonProblem(
              '$liveCacheWords; recomputed when read',
              docAboveLine(
                '  /// The world transform.\n  ///\n  /// Live: the object\'s '
                'own cache,\n  /// read-only by contract.\n  @override\n'
                '  Matrix4 get worldMatrix {',
                6,
              ),
            ) ==
            null,
    'a chain that copies, and a cache whose wrapped doc says it is live',
    'each says which kind it is',
  );
  fires(
    'vector ownership in the contract',
    vectorOwnershipGapsIn(
      'A public `final` field is the owner\'s live state. A getter and an '
      '`…Of` query answer a copy the caller owns. A vector parameter is '
      'read, never kept. **Not every constructor copies yet.**',
    ).toSet().containsAll(<String>{
      'a value type owns what its constructor is given',
      'a constructor that does not copy is called a gap',
    }),
    'the three cases and the gap',
  );
  quiet(
    'vector ownership in the contract',
    vectorOwnershipGapsIn(
      '- **A public `final` field is the owner\'s live state.**\n'
      '- **A getter and an `…Of` query answer a copy the caller\n'
      '  owns.**\n- **A method\'s vector parameter is read, never kept.**\n'
      '- **A value type takes ownership of the vectors its constructor\n'
      '  is given.**',
    ).isEmpty,
    'the four cases, wrapped across lines',
    'a line break inside a case is still the case',
  );

  // A particle's world. The platformer's sparks fell at the standard
  // gravity beside a runner at the platformer's own 24.
  fires(
    'particle worlds',
    particleSystemsWithoutWorldIn(
          'final p = ParticleSystem(capacity: 2000);\n'
          'void load() { camera = FollowCamera(world: level.collision); '
          'gravity = level.collision.properties.gravityMagnitude; }',
        ).single ==
        1,
    'a ParticleSystem beside a level\'s world',
  );
  quiet(
    'particle worlds',
    particleSystemsWithoutWorldIn(
          'final p = ParticleSystem(capacity: 3000);\n'
          'void load() { p.world = level.loaded.collision.properties; }',
        ).isEmpty &&
        particleSystemsWithoutWorldIn(
          'final p = ParticleSystem(capacity: 8);\n'
          '// WorldProperties is the standard one here.',
        ).isEmpty,
    'particles given the level\'s world, and a page with no world',
    'the first hands the system its world, the second sets none',
  );

  // A property's reader. The snapshot is the source of the members, so a
  // property added to the world is a property the rule asks a reader for.
  const worldApi =
      'final class WorldProperties\n'
      '  Vector3 get gravity\n'
      '  double get speedOfSound\n'
      '  final GeoOrigin? geoOrigin\n'
      '  int get hashCode\n'
      '  static final WorldProperties standard\n'
      '  Map<String, Object?> toJson()\n'
      '\n'
      'final class WorldPropertiesPatch\n'
      '  final double airTemperature\n';
  fires(
    'readable members',
    readableMembersIn(
      worldApi,
      'WorldProperties',
    ).containsAll(<String>{'gravity', 'speedOfSound', 'geoOrigin'}),
    'the getters and fields of WorldProperties',
  );
  quiet(
    'readable members',
    !readableMembersIn(worldApi, 'WorldProperties').any(
      <String>{'hashCode', 'standard', 'toJson', 'airTemperature'}.contains,
    ),
    'hashCode, a static, a method and another class\'s field',
    'none is a property an application reads off a world',
  );
  fires(
    'material groups',
    materialGroupsIn(
          'final class PhysicalMaterial\n'
          '  final ElectricalProperties? electrical\n'
          '  final MaterialPhase phase\n'
          '  final String id\n',
        ).single ==
        'electrical',
    'the electrical group of PhysicalMaterial',
  );
  fires(
    'property readers',
    readsMember('final c = world?.speedOfSound;', 'speedOfSound') &&
        readsMember('if (m.electrical case final e?) {}', 'electrical'),
    'world?.speedOfSound and m.electrical',
  );
  quiet(
    'property readers',
    !readsMember(
      '// reads world.speedOfSound\nf(speedOfSound: 343.0);',
      'speedOfSound',
    ),
    'a comment and a named argument',
    'neither reads the property off anything',
  );

  // A section's fixture: `.f3d`'s physicalMaterials, section 36, came in
  // at version 2, and only a file of version 2 holding it shows it reads.
  fires(
    'section fixtures',
    versionsWithoutFixture(
          'v<N>/physical.f3d',
          since: 2,
          current: 3,
          exists: (String path) => path == 'v2/physical.f3d',
        ).single ==
        3,
    'a bump to 3 without v3/physical.f3d',
  );
  quiet(
    'section fixtures',
    versionsWithoutFixture(
      'v<N>/physical.f3d',
      since: 2,
      current: 2,
      exists: (String path) => path == 'v2/physical.f3d',
    ).isEmpty,
    'v2/physical.f3d at version 2',
    'the section is in a fixture at every version that writes it',
  );

  // What a fixture holds. A `.f3d` of version 1 with two sections, kinds 1
  // and 23; the same bytes as a version 2 file whose header names 20-byte
  // entries it does not have; a version 3 project with its fifth word.
  List<int> words(List<int> values) => <int>[
    for (final value in values) ...<int>[
      value & 0xFF,
      value >> 8 & 0xFF,
      value >> 16 & 0xFF,
      value >> 24 & 0xFF,
    ],
  ];
  final twoSections = words(<int>[
    0x0A443346, 1, 2, 0, //
    1, 48, 0, 0, //
    23, 48, 0, 0, //
  ]);
  fires(
    'section kinds',
    sectionKindsOf(twoSections)?.containsAll(<int>[1, 23]) ?? false,
    'a version 1 .f3d with kinds 1 and 23',
  );
  quiet(
    'section kinds',
    sectionKindsOf(<int>[
          ...twoSections.take(4),
          ...words(<int>[2, 2, 20]),
        ]) ==
        null,
    'a version 2 header naming entries past the end',
    'a directory that runs out is no list of kinds',
  );
  fires(
    'section kinds',
    sectionKindsOf(
          words(<int>[0x50443346, 3, 1, 0, 20, 0x80000001, 40, 0, 0, 2]),
        )?.single ==
        0x80000001,
    'a version 3 project with one 20-byte entry',
  );
  fires(
    'section constants',
    intConstantsOf(
          'abstract final class F3dSection {\n'
              '  static const int layouts = 1;\n'
              '  // static const int gone = 9;\n'
              '  static const Set<int> known = <int>{layouts};\n'
              '}\nclass Other {\n  static const int other = 2;\n}',
          'F3dSection',
        ).toString() ==
        '{layouts: 1}',
    'F3dSection with a commented constant and another class after it',
  );
  fires(
    'fixture version',
    fixtureVersionOf(utf8.encode('{"format": "f3d.level", "version": 2}')) == 2,
    'a level of version 2',
  );
  fires(
    'fixture version',
    fixtureVersionOf(twoSections) == 1,
    'a version 1 .f3d',
  );
  quiet(
    'fixture version',
    fixtureVersionOf(utf8.encode('{"fmat": 1}')) == null,
    'a material from before the envelope',
    'a shape with no version key reads as 1 and says nothing here',
  );

  // The wire. Mutation: compare whole lines and the `key slot` of one
  // message passes for another's.
  const wireBase =
      '# comment\nprotocol 3.1\n\nmessage relay.welcome\n  tag f3d=relay\n'
      '  key slot\n\nmessage relay.left\n  key slot\n';
  fires(
    'wire facts',
    wireFactsRemoved(
          wireBase,
          wireBase.replaceFirst(
            'message relay.welcome\n  tag f3d=relay\n'
                '  key slot\n',
            'message relay.welcome\n  tag f3d=relay\n',
          ),
        ).single ==
        'message relay.welcome / key slot',
    'a key dropped from one message and kept in another',
  );
  quiet(
    'wire facts',
    wireFactsRemoved(
      wireBase,
      '$wireBase  key code\nmessage relay.full\n',
    ).isEmpty,
    'a key and a message added within the major',
    'within a major the wire may grow',
  );
  quiet(
    'wire facts',
    wireFactsRemoved(
      wireBase,
      'protocol 4.0\nmessage relay.left\n  key slot\n',
    ).isEmpty,
    'a message dropped at protocol 4',
    'a new major is where a message may change',
  );
  fires(
    'wire facts',
    wireFactsRemoved(
          wireBase,
          wireBase
              .replaceFirst('protocol 3.1', 'protocol 3.2')
              .replaceFirst('message relay.left\n  key slot\n', ''),
        ).length ==
        2,
    'a message dropped at protocol 3.2',
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

  // An example written as from outside: what such a project could not
  // reach, and the pubspec it could not write.
  fires(
    'outside example',
    outsideExampleReaches(
      "import 'package:flutter3d_sim/src/loop/engine_loop.dart';\n",
      own: 'outside_plugin',
      depth: 1,
    ).contains('package:flutter3d_sim/src/'),
    "an engine package's src/",
  );
  fires(
    'outside example',
    exampleMembershipProblems(
      const <String>{'outside_plugin', 'flutter3d_backend_null'},
      const <String>{'outside_plugin'},
    ).any(((String, String) p) => p.$1 == 'flutter3d_backend_null'),
    'an example on disk the workspace leaves out',
  );
  quiet(
    'outside example',
    exampleMembershipProblems(
      const <String>{'outside_plugin'},
      const <String>{'outside_plugin'},
    ).isEmpty,
    'every example on disk listed',
    'the workspace and the directory agree',
  );
  fires(
    'outside example',
    outsideExampleReaches(
      "import 'package:flutter3d_shaders/internal.dart';\n",
      own: 'flutter3d_backend_null',
      depth: 1,
    ).contains('package:flutter3d_shaders/internal.dart'),
    "an engine package's internal.dart",
  );
  fires(
    'outside example',
    outsideExampleReaches(
      "import '../../../packages/flutter3d_sim/lib/flutter3d_sim.dart';\n",
      own: 'outside_plugin',
      depth: 1,
    ).isNotEmpty,
    'a relative path out of the example into packages/',
  );
  quiet(
    'outside example',
    outsideExampleReaches(
      "import 'package:outside_plugin/src/warming.dart';\n"
      "import 'scene.dart';\n"
      "import '../lib/outside_plugin.dart';\n",
      own: 'outside_plugin',
      depth: 1,
    ).isEmpty,
    "the example's own src/, a sibling, and its own lib/ from test/",
    'an example arranges its own files as it likes',
  );
  fires(
    'outside example',
    outsideExamplePubspecProblems(
      'name: x\npublish_to: none\ndependencies:\n'
      '  flutter3d_sim:\n    git: https://example.com/flutter3d\n',
      const <String>{'flutter3d_sim'},
    ).isNotEmpty,
    'an engine package reached by git',
  );
  fires(
    'outside example',
    outsideExamplePubspecProblems(
      'name: x\ndependencies:\n'
      '  flutter3d_sim:\n    path: ../../packages/flutter3d_sim\n',
      const <String>{'flutter3d_sim'},
    ).isNotEmpty,
    'an example that may be published',
  );
  quiet(
    'outside example',
    outsideExamplePubspecProblems(
      "name: x\npublish_to: 'none'\ndependencies:\n"
      '  flutter3d_sim:\n    path: ../../packages/flutter3d_sim\n'
      '  vector_math: ^2.2.0\n',
      const <String>{'flutter3d_sim'},
    ).isEmpty,
    'every engine package by path, and a package from pub.dev',
    'the override an outside project makes, and what it takes from pub.dev',
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
    declaresGraphicsDevice(
      'final class CpuDevice\n'
      '    with DeviceCapabilityForwarders\n'
      '    implements GraphicsDevice {\n',
    ),
    'a device declared over three lines',
  );
  fires(
    'backend',
    declaresGraphicsDevice(
      'final class NullDevice extends GraphicsDevice\n'
      '    with SynchronousBufferReadback {\n',
    ),
    'a device that extends the base class, as every backend does since 1.0',
  );
  quiet(
    'backend',
    !declaresGraphicsDevice(
      'final class Probe implements GraphicsDeviceFactory {}\n',
    ),
    'a longer name that starts the same',
    'a factory of devices is not a device',
  );
  quiet(
    'backend',
    !declaresGraphicsDevice(
      'final class Frame extends Pass {\n'
      '  final GraphicsDevice device;\n',
    ),
    'a field of the type inside another class',
    'holding a device is not being one',
  );
  final rows = packagePlatformRows(
    '| Package | Platforms |\n'
    '|---|---|\n'
    '| `flutter3d_webgl` | web |\n'
    '| `flutter3d_pointer_lock` | linux, macos, web, windows |\n',
  );
  fires(
    'support table',
    rows['flutter3d_pointer_lock']?.length == 4 &&
        (rows['flutter3d_webgl']?.join(',') ?? '') == 'web',
    'two rows of a package table',
  );
  quiet(
    'support table',
    !rows.containsKey('Package'),
    'the header row',
    'a header is not a package',
  );

  // A template's pins on a sibling. Mutation: drop the multiline flag and
  // only a first line is read; read any name and `vector_math` is a sibling.
  final pins = siblingPinsIn(
    "const String _options = '''\n"
    'plugins:\n'
    '  flutter3d_lints: ^1.0.0-rc.1\n'
    "''';\n"
    '  flutter3d: ^1.0.0-rc.1\n'
    '  vector_math: ^2.1.4\n'
    "  flutter3d_core: ^\$version\n",
    const <String>{'flutter3d_lints', 'flutter3d', 'flutter3d_core'},
  );
  fires(
    'pins on a sibling',
    pins.contains(('flutter3d_lints', '^1.0.0-rc.1')) &&
        pins.contains(('flutter3d', '^1.0.0-rc.1')),
    'a lints pin inside a template string and a facade pin',
  );
  quiet(
    'pins on a sibling',
    pins.length == 2,
    'a third-party pin and an interpolated one',
    'only a sibling at a written version is held to that sibling',
  );

  // The engine's render names. Mutation: drop `RenderStep\._` from the
  // pattern and `color grade` passes; accept any dotted word for the engine
  // and `acme.after_bloom` passes as the engine's; drop the space test and
  // `acme.after glow` passes.
  final unprefixed = unprefixedRenderNamesIn(
    "  static const RenderAnchor afterBloom = RenderAnchor._('after bloom');\n"
    "  static const RenderStep grade = RenderStep._(\n    'color grade',\n"
    "  static const ResourceId hdr = ResourceId('hdr_color');\n"
    "  static const RenderAnchor ok = RenderAnchor._('f3d.after_bloom');\n"
    "  static const ResourceId good = ResourceId('f3d.scene_color');\n"
    "  const RenderAnchor odd = RenderAnchor._('acme.after_bloom');\n"
    "  final id = ResourceId('\${id.name}#\$index');\n"
    "  /// RenderStep('in a doc') is prose.\n",
    engine: true,
  );
  fires(
    'render names without f3d.',
    unprefixed.toSet().containsAll(<String>{
      'after bloom',
      'color grade',
      'hdr_color',
      'acme.after_bloom',
    }),
    "an anchor, a step and a resource in the old words, a plugin's name in "
        "the engine's package",
  );
  quiet(
    'render names without f3d.',
    unprefixed.length == 4,
    'f3d. words, an interpolated name and a doc comment',
    'they are the words the rule asks for, or not a name declared',
  );
  final plugins = unprefixedRenderNamesIn(
    "const RenderStep sky = RenderStep('sky', isOn: _on, switchOff: _off);\n"
    "const RenderStep glow = RenderStep('acme.soft_glow');\n"
    "final at = RenderAnchor.after(RenderAnchor.afterBloom, 'acme.after glow');\n"
    "final ok = RenderAnchor.after(RenderAnchor.afterBloom, 'acme.after_glow');\n",
    engine: false,
  );
  fires(
    'render names without a namespace',
    plugins.toSet().containsAll(<String>{'sky', 'acme.after glow'}),
    'a step with no namespace, an anchor with a space',
  );
  quiet(
    'render names without a namespace',
    plugins.length == 2,
    "a plugin's dotted step and anchor",
    'they carry their namespace',
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
  // A key a `--json` body drops, and an exit code moved to another number,
  // are words gone from the surface, which the release rule asks a
  // `**Breaking:**` entry for.
  const releasedCli =
      '== flutter3d ==\nExit codes:\n  0  ok\n  3  refused, or out of date\n'
      '\n== --json ==\n'
      'convert {output, reports: [{input, mapped, error?}]}\n'
      'plugins {check, current? (with --check)}\n';
  const nowCli =
      '== flutter3d ==\nExit codes:\n  0  ok\n  5  refused, or out of date\n'
      '\n== --json ==\n'
      'convert {output, reports: [{input, error?}]}\n'
      'plugins {check, current? (with --check)}\n';
  final goneCli = cliSurfaceWords(
    releasedCli,
  ).difference(cliSurfaceWords(nowCli));
  fires(
    'cli surface json keys and exit codes',
    goneCli.length == 2 &&
        goneCli.contains('--json convert reports[].mapped') &&
        goneCli.contains('exit 3 refused') &&
        cliSurfaceWords(releasedCli).contains('--json plugins current') &&
        !cliSurfaceWords(releasedCli).any((w) => w.contains('--check')),
    'a nested key dropped and a code renumbered, not a note in parentheses',
  );
  // `plugin.report` once kept the suite's check list itself and counted 5
  // of its 7; a copy, or a badge spelled out, is a second judge.
  const suiteChecks = <String>['manifest', 'switch', 'names', 'budget'];
  fires(
    'own badge judges',
    ownBadgeJudgesIn(
          "const List<String> pluginConformanceChecks = <String>['manifest', "
          "'switch', 'budget'];\n"
          "String? get badge => ok ? 'conformant@1.0' : null;\n",
          suiteChecks,
        ).length ==
        2,
    'a copied check list and a badge built by hand',
  );
  quiet(
    'own badge judges',
    ownBadgeJudgesIn(
      "/// earns `conformant@1.0` when the report says so\n"
      "const List<String> tools = <String>['plugin.report', 'manifest'];\n"
      "final badge = report.badge;\n",
      suiteChecks,
    ).isEmpty,
    'a doc comment naming the badge, and a list with one check word in it',
    'reading the report\'s badge, and saying it in prose, judge nothing',
  );
  fires(
    'CI as a define',
    readsCiAsDefine(
      "final record = !const bool.fromEnvironment('CI', defaultValue: false);",
    ),
    'bool.fromEnvironment(\'CI\')',
  );
  quiet(
    'CI as a define',
    !readsCiAsDefine(
      "final ci = Platform.environment['CI'];\n"
      "// was: bool.fromEnvironment('CI')\n"
      "const debug = bool.fromEnvironment('CIRCLE');\n",
    ),
    'the environment read, a comment, and another define',
    'only the define nobody passes is the bug',
  );
  const manifestAt1 =
      "const Set<String> _topLevelKeys = <String>{'format', 'rules'};\n"
      "const Set<String> _ruleKeys = <String>{'glob', 'lods'};\n"
      'static const int formatVersion = 1;\n';
  fires(
    'assets manifest growth',
    assetsManifestGrowthProblems(
          manifestAt1,
          manifestAt1.replaceFirst("'lods'}", "'lods', 'decimate'}"),
        ).length ==
        1,
    'a rule key added under format 1',
  );
  quiet(
    'assets manifest growth',
    assetsManifestGrowthProblems(
          manifestAt1,
          manifestAt1
              .replaceFirst("'lods'}", "'lods', 'decimate'}")
              .replaceFirst('= 1;', '= 2;'),
        ).isEmpty &&
        assetsManifestGrowthProblems(
          manifestAt1,
          manifestAt1.replaceFirst(", 'lods'}", '}'),
        ).isEmpty,
    'a key added with format 2, and a key taken away',
    'the version moved with the key; a key gone is the reader\'s own break',
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

  // A third-party type from a package at 0.x: found through the lock's
  // version and the package's declarations; the same name from a 1.x
  // package, or a 0.x package that does not declare it, is not.
  final locked = lockedVersions('''
packages:
  tiled:
    dependency: transitive
    description:
      name: tiled
    source: hosted
    version: "0.11.1"
  flame:
    dependency: transitive
    source: hosted
    version: "1.38.2"
''');
  fires(
    'third-party types at 0.x',
    locked['tiled'] == '0.11.1' && locked['flame'] == '1.38.2',
    'the versions of a pubspec.lock',
  );
  fires(
    'third-party types at 0.x',
    declaredTypeNames(
      'abstract base class Foo {}\nfinal class _Bar {}\nextension type '
      'Baz(int i) {}\ntypedef Qux = int;',
    ).difference(<String>{'Foo', 'Baz', 'Qux'}).isEmpty,
    'the types a library declares, private ones left out',
  );
  final zeroX = zeroThirdPartyTypes(
    <String>['bridge:TiledMap', 'bridge:Component', 'bridge:Other'],
    dependencies: <String, Set<String>>{
      'bridge': <String>{'tiled', 'flame'},
    },
    versions: locked,
    typesOf: (String p) => switch (p) {
      'tiled' => <String>{'TiledMap'},
      'flame' => <String>{'Component'},
      _ => null,
    },
  );
  fires(
    'third-party types at 0.x',
    zeroX.length == 1 && zeroX.single == ('bridge:TiledMap', 'bridge -> tiled'),
    'a bridge naming a type of tiled 0.11',
  );
  quiet(
    'third-party types at 0.x',
    !zeroX.any(((String, String) z) => z.$1 != 'bridge:TiledMap'),
    'a type of flame 1.38, and one no 0.x dependency declares',
    'only a type a 0.x package declares is asked about',
  );

  // The simulation stack's closure: a core whose hook depends on a sidecar
  // that names the graphics vocabulary is found, with the path; a
  // dependency that draws nothing is not.
  final closure = simulationClosureProblems(
    <String, Set<String>>{
      'core': <String>{'sidecar', 'maths'},
      'sidecar': <String>{'graphics'},
      'maths': <String>{},
    },
    stack: <String>{'core'},
    forbidden: <String>{'graphics'},
  );
  fires(
    'the simulation draws nothing',
    closure.length == 1 &&
        closure.single.$2 == 'graphics' &&
        closure.single.$3.join(' ') == 'core sidecar graphics',
    'the physics core resolving the graphics vocabulary through its sidecar',
  );
  quiet(
    'the simulation draws nothing',
    simulationClosureProblems(
      <String, Set<String>>{
        'core': <String>{'maths'},
        'maths': <String>{},
      },
      stack: <String>{'core'},
      forbidden: <String>{'graphics'},
    ).isEmpty,
    'a core on its maths',
    'only a forbidden package in the closure is a finding',
  );

  // The plugin templates' run-time dependencies, from both shapes the
  // template file writes a pubspec in; the dev dependencies are not read.
  final templateDeps = templateRuntimeDependencies(r"""
  final dependencies = <String>[
    '  flutter3d_plugin_api: ^1.0.0-rc.1',
    if (kind == PluginKind.tool) '  flutter3d_mcp: ^1.0.0-rc.1',
  ];
  final devDependencies = <String>[
    '  flutter3d_conformance: ^1.0.0-rc.1',
  ];
const String _backendPubspec = '''
dependencies:
  flutter3d_hardware: ^1.0.0-rc.1

dev_dependencies:
  test: ^1.25.0
''';
""");
  fires(
    'the runtime is not a tool',
    templateDeps.contains('flutter3d_mcp') &&
        templateDeps.contains('flutter3d_hardware'),
    'a plugin template depending on the agent servers',
  );
  quiet(
    'the runtime is not a tool',
    !templateDeps.contains('flutter3d_conformance') &&
        !templateDeps.contains('test'),
    'a template\'s dev dependencies',
    'a test may drive a tool; only what a game resolves is asked about',
  );

  // The applications: a demo on an editor's core is found, the modeller on
  // its own document layer is not; and an application on another is in its
  // own layer, which the layers refuse.
  final applicationsOnTools = runtimeToolDependencies(
    <String, Set<String>>{
      'flutter3d_lesson_viewer': <String>{'flutter3d_editor_core'},
      'flutter3d_modeler': <String>{'flutter3d_model_core'},
    },
    runtime: isRuntimeApplication,
    tools: runtimeMayNotDependOn.keys.toSet(),
  );
  fires(
    'the runtime is not a tool',
    applicationsOnTools.contains((
      'flutter3d_lesson_viewer',
      'flutter3d_editor_core',
    )),
    'a lesson viewer depending on the editor\'s core',
  );
  quiet(
    'the runtime is not a tool',
    applicationsOnTools.length == 1,
    'the modeller on its document layer',
    'an application that is a tool is not the runtime',
  );
  fires(
    'the layers',
    layerProblems(
      <String, Set<String>>{
        'demo_a': <String>{'demo_b', 'f'},
        'demo_b': <String>{'f'},
        'f': <String>{},
      },
      layers: <String, int>{'f': 0, 'demo_a': 9, 'demo_b': 9},
      forbidden: const <String, Map<String, String>>{},
    ).any(((String, String?, String) p) => p.$2 == 'demo_b'),
    'an application depending on another application',
  );

  // Nothing at 1.x stands on 0.x (S6). Mutation: compare the major with `>`
  // and a release candidate is not 1.x; drop the `versions.containsKey` and
  // a pub.dev package with no version here reads as 0.x.
  const lines = <String, String>{
    'stable': '1.0.0-rc.1',
    'lab': '0.3.0',
    'other': '1.2.0',
  };
  fires(
    'nothing at 1.x stands on 0.x',
    stableOnUnstable(<String, Set<String>>{
          'stable': <String>{'lab', 'other', 'vector_math'},
        }, lines).single ==
        ('stable', 'lab'),
    'a release candidate of 1.0.0 depending on a 0.x package',
  );
  quiet(
    'nothing at 1.x stands on 0.x',
    stableOnUnstable(<String, Set<String>>{
      'lab': <String>{'stable', 'other'},
      'other': <String>{'stable', 'vector_math'},
    }, lines).isEmpty,
    'a 0.x package on 1.x ones, and a 1.x one on 1.x and pub.dev',
    'the rule holds the stable side only, and only to this repository',
  );
  // ... and what is refused is a 0.x type in the 1.x API. Mutation: match
  // without word boundaries and `GamePadButton` names `PadButton`; drop the
  // capital and a member `read` names a 0.x function.
  const unstable = <String>{'PadButton', 'PointerLock', 'read'};
  fires(
    'a 1.x API names no 0.x type',
    unstableNamesIn(
          'final class DesktopInput\n  DesktopInput({PointerLock? capture})\n',
          unstable,
        ).single ==
        'PointerLock',
    'a 0.x type in a 1.x constructor',
  );
  quiet(
    'a 1.x API names no 0.x type',
    unstableNamesIn(
      'final class PadInput\n  Iterable<GamePadButton> get held\n'
      '  void read(PadReading out)\n',
      unstable,
    ).isEmpty,
    'a type of its own whose name ends in a 0.x one, and a member named alike',
    'only a whole type name is the 0.x package\'s',
  );
  fires(
    'major version',
    majorVersionOf('1.0.0-rc.1') == 1 &&
        majorVersionOf('0.5.0') == 0 &&
        majorVersionOf('none') == null,
    '1.0.0-rc.1, 0.5.0 and a word',
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

  // A hook is compiled against the run-time dependencies alone: a dev
  // dependency or a package named nowhere is the finding, the package's own
  // library and the SDK's are not.
  const hook =
      "import 'dart:io';\n"
      "import 'package:flutter3d_build/flutter3d_build.dart';\n"
      "import 'package:hooks/hooks.dart';\n"
      "import 'package:demo/assets.dart';\n";
  fires(
    'declare what you name',
    undeclaredHookImports(
      hook,
      own: 'demo',
      dependencies: const <String>{'flutter3d_app'},
    ).containsAll(const <String>{'flutter3d_build', 'hooks'}),
    'a hook importing a dev dependency and an undeclared package',
  );
  quiet(
    'declare what you name',
    undeclaredHookImports(
      hook,
      own: 'demo',
      dependencies: const <String>{'flutter3d_build', 'hooks'},
    ).isEmpty,
    'a hook whose imports are all dependencies, its own and the SDK\'s',
    'what the pubspec lists is what the hook is compiled against',
  );

  // A demo that declares a package's type is a copy; one whose name only a
  // pub.dev package also has, or that is allowed with its reason, is not.
  final copies = applicationCopies(
    const <String, Set<String>>{
      'demo': <String>{'ElementSounds', 'Link', 'RaceState', 'OpenKind'},
    },
    homes: const <String, String>{
      'ElementSounds': 'flutter3d_game_physics',
      'Link': 'flutter3d_game',
      'OpenKind': 'flutter3d_sim',
    },
    allowed: const <String, String>{'demo: OpenKind': 'waits'},
  );
  fires(
    'an application declares no type a package publishes',
    copies.any(((String, String, String) c) => c.$2 == 'ElementSounds'),
    'a demo declaring the game physics\' ElementSounds',
  );
  quiet(
    'an application declares no type a package publishes',
    copies.length == 1,
    'a name of its own, one Flutter also declares, and an allowed copy',
    'only a package\'s name, unallowed and not also the SDK\'s, is a copy',
  );

  // An application hands on only what it depends on.
  final handedOn = applicationReexportProblems(
    const <String, Map<String, List<({String uri, bool named})>>>{
      'demo': <String, List<({String uri, bool named})>>{
        'apps/demo/lib/src/backend.dart': <({String uri, bool named})>[
          (uri: 'package:flutter3d_app/flutter3d_app.dart', named: false),
          (uri: 'package:flutter3d_net/flutter3d_net.dart', named: true),
          (uri: 'package:vector_math/vector_math.dart', named: false),
        ],
      },
    },
    repository: const <String>{'flutter3d_app', 'flutter3d_net'},
    dependencies: const <String, Set<String>>{
      'demo': <String>{'flutter3d_app', 'vector_math'},
    },
  );
  fires(
    'a package re-exports another only where the list allows it',
    handedOn.any(
      ((String, String, String) p) => p.$3.contains('flutter3d_net'),
    ),
    'an application re-exporting a package it does not depend on',
  );
  quiet(
    'a package re-exports another only where the list allows it',
    handedOn.length == 1,
    'an application re-exporting its own dependency, and one from pub.dev',
    'an application is nobody\'s library; what it depends on it may hand '
        'its own files',
  );

  fires(
    'a timeout past a minute',
    longTimeoutsIn(
      'library;\n@Timeout(Duration(minutes: 20))\nlibrary;',
    ).any((LongTimeout t) => t.line == 2),
    'a file given twenty minutes',
  );
  fires(
    'a timeout past a minute',
    longTimeoutsIn(
      '  }, timeout: const Timeout(Duration(seconds: 90)));',
    ).isNotEmpty,
    'a test given ninety seconds',
  );
  fires(
    'a timeout past a minute',
    longTimeoutsIn(
      'const Timeout _slow = Timeout(\n  Duration(minutes: 1, seconds: 1),\n);',
    ).isNotEmpty,
    'a minute and a second, wrapped by the formatter',
  );
  fires(
    'a timeout past a minute',
    longTimeoutsIn('timeout: Timeout.factor(2),').isNotEmpty,
    'twice the minute, as a factor',
  );
  fires(
    'a timeout past a minute',
    longTimeoutsIn('timeout: Timeout.none,').isNotEmpty,
    'no timeout at all',
  );
  fires(
    'a timeout past a minute',
    longTimeoutsIn('timeout: Timeout(budget),').isNotEmpty,
    'a duration it cannot read, which it has to ask about',
  );
  quiet(
    'a timeout past a minute',
    longTimeoutsIn(
      '}, timeout: const Timeout(Duration(seconds: 60)));\n'
      'defaultTestTimeout = const Timeout.factor(1);\n'
      'await done.future.timeout(const Duration(minutes: 4));',
    ).isEmpty,
    'a minute, a factor of one, and a future\'s own timeout',
    'only a test given more than the minute is the claim to read',
  );
  quiet(
    'a timeout past a minute',
    longTimeoutsIn(
      '/// Once had `@Timeout(Duration(minutes: 20))` on it.\n'
      '// timeout: const Timeout(Duration(minutes: 5)),',
    ).isEmpty,
    'a comment recalling a timeout',
    'prose explaining the rule must not break it',
  );
  fires(
    'a package timeout past a minute',
    longYamlTimeoutsIn(
      'timeout: 1m\ntags:\n  slow:\n    timeout: 2m\n',
    ).any((LongTimeout t) => t.line == 4),
    'a tag given two minutes',
  );
  quiet(
    'a package timeout past a minute',
    longYamlTimeoutsIn(
      'timeout: 1m\n# timeout: 5m\ntags:\n  a:\n    '
      'timeout: 30s\n',
    ).isEmpty,
    'the minute, a comment and a shorter tag',
    'only more than the minute is the claim to read',
  );

  // An accessible UI. Each mutation is the one the widgets carried before
  // their promise was kept.
  fires(
    'a typed colour',
    typedColorsIn(
          'return DecoratedBox(\n'
          '  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55)),\n'
          ');\nconst c = Color(0xCCFFFFFF);',
        ).length ==
        2,
    'a black at 0.55 and a hex colour in a widget',
  );
  quiet(
    'a typed colour',
    typedColorsIn(
      '/// Was `Colors.white` on a sky.\n'
      'final c = theme.panel; // not Color(0x73000000) any more',
    ).isEmpty,
    'a doc and a comment naming colours',
    'prose explaining the rule must not break it',
  );
  fires(
    'a pinned text size',
    fixedTextScalesIn(
          'Text(t, textScaler: TextScaler.noScaling);\n'
          'MediaQuery(data: d.copyWith(textScaler: TextScaler.linear(1)));',
        ).length ==
        2,
    'no scaling, and a linear scaler of one',
  );
  fires(
    'an unscaled painter',
    unscaledTextPaintersIn(
          'final p = TextPainter(\n  text: span,\n  textDirection: d,\n);',
        ).single ==
        1,
    'a TextPainter made without a scaler',
  );
  quiet(
    'an unscaled painter',
    unscaledTextPaintersIn(
      'final p = TextPainter(\n  text: TextSpan(text: f(x)),\n'
      '  textScaler: MediaQuery.textScalerOf(context),\n);',
    ).isEmpty,
    "a TextPainter given the context's scaler past a nested call",
    'the scaler is inside its arguments',
  );
  fires(
    'an unnamed control',
    unnamedPointerWidgetsIn(
          'Widget build(BuildContext context) => Listener(\n'
          '  onPointerDown: (_) => begin(),\n  child: sheet,\n);',
        ).single ==
        1,
    "a title sheet's Listener with nothing to name it",
  );
  quiet(
    'an unnamed control',
    unnamedPointerWidgetsIn(
          'return Semantics(\n  button: true,\n  label: prompt,\n'
          '  child: Listener(onPointerDown: (_) => begin()),\n);',
        ).isEmpty &&
        unnamedPointerWidgetsIn(
          'final l = ValueListenableBuilder(x);\n'
          'controller.addListener(f);',
        ).isEmpty,
    'a Listener under Semantics, a ValueListenableBuilder, an addListener',
    'the first is named, the others take no pointer',
  );
  fires(
    'motion without reduction',
    motionWithoutReductionIn(
          'late final c = AnimationController(vsync: this);',
        ).single ==
        1,
    'an AnimationController in a library that never asks',
  );
  quiet(
    'motion without reduction',
    motionWithoutReductionIn(
      'late final c = AnimationController(vsync: this);\n'
      'if (MediaQuery.disableAnimationsOf(context)) c.value = 1.0;',
    ).isEmpty,
    'a controller beside the reduced-motion flag',
    'the library reads what the player asked for',
  );
  fires(
    'an accessibility test',
    accessibilityTestGapsIn(
          '// labeledTapTargetGuideline textContrastGuideline textScaler\n'
          'void main() {}',
        ).length ==
        4,
    'a test with the words only in a comment',
  );
  quiet(
    'an accessibility test',
    accessibilityTestGapsIn(
      "@Tags(<String>['accessibility'])\nlibrary;\n"
      'final g = <Object>[labeledTapTargetGuideline, '
      'androidTapTargetGuideline, textContrastGuideline];\n'
      'final s = TextScaler.linear(2); // textScaler',
    ).isEmpty,
    'a test that asks every guideline at a larger size',
    'it does what the promise asks',
  );

  // The engine's number is a major.minor: a patch of one package stays on
  // it, a pre-release under a final release and another minor do not.
  for (final (version, engine) in const <(String, String)>[
    ('1.0.0-rc.1', '1.0.0-rc.1'),
    ('1.0.1', '1.0.0'),
    ('1.0.1', '1.0.0-rc.1'),
  ]) {
    quiet(
      'the engine number',
      onEngineNumber(version, engine),
      '$version beside $engine',
      'a patch goes to the one package that needs it',
    );
  }
  for (final (version, engine) in const <(String, String)>[
    ('1.0.0-rc.1', '1.0.0'),
    ('1.1.0', '1.0.0'),
    ('0.5.0', '1.0.0-rc.1'),
    ('2.0.0', '1.0.0'),
  ]) {
    fires(
      'the engine number',
      !onEngineNumber(version, engine),
      '$version beside $engine',
    );
  }

  // Every package that names a sibling is on the engine's number. Four
  // left it for 0.9.0 once; a package of the repository at 0.9.0 is what
  // this exists to name.
  fires(
    'off the engine number',
    offTheEngineNumber(<String, ({String version, bool namesSibling})>{
          'flutter3d_lints': (version: '0.9.0', namesSibling: true),
          'flutter3d_editor_play': (
            version: '1.0.0-rc.1+1',
            namesSibling: true,
          ),
        }, '1.0.0-rc.1').join(',') ==
        'flutter3d_lints',
    'a package of the repository at 0.9.0',
  );
  quiet(
    'off the engine number',
    offTheEngineNumber(<String, ({String version, bool namesSibling})>{
      'pad_input': (version: '0.5.0', namesSibling: false),
      'flutter3d_editor_play': (version: '1.0.0-rc.1+1', namesSibling: true),
      'flutter3d_impeller': (version: '1.0.1', namesSibling: true),
    }, '1.0.0-rc.1').isEmpty,
    'a plugin that names no sibling, a build and a patch',
    'each is on the number, or stands on nothing of the engine',
  );

  // A policy document's revision line. The SECURITY.md of 0.x said "nothing
  // is published to pub.dev yet" for months after 0.4.0 went up, and ROADMAP
  // described a quarter that had closed.
  final today = DateTime.utc(2026, 10, 12);
  quiet(
    'a revision line',
    revisionProblemsIn(
      '# Roadmap\n\nRevised 2026-10-12, for the 1.0.0-rc.1 tree.\n',
      version: '1.0.0-rc.1',
      today: today,
    ).isEmpty,
    'a line with today and the version the packages carry',
    'it is the revision the rule asks for',
  );
  fires(
    'a revision line',
    revisionProblemsIn(
      '# Roadmap\n\nRevised 8 September 2026.\n',
      version: '1.0.0-rc.1',
      today: today,
    ).isNotEmpty,
    'a date in words and no version',
  );
  fires(
    'a revision line',
    revisionProblemsIn(
      'Revised 2026-10-12, for the 1.0.0-rc.1 tree.\n',
      version: '1.0.0-rc.2',
      today: today,
    ).isNotEmpty,
    'the version before the one the packages carry',
  );
  fires(
    'a revision line',
    revisionProblemsIn(
      'Revised 2026-10-12, for the 1.0.0-rc.1 tree.\n',
      version: '1.0.0',
      today: today,
    ).isNotEmpty,
    'a candidate where the release is out (a prefix is not the version)',
  );
  fires(
    'a revision line',
    revisionProblemsIn(
      'Revised 2026-11-30, for the 1.0.0-rc.1 tree.\n',
      version: '1.0.0-rc.1',
      today: today,
    ).isNotEmpty,
    'a date after today',
  );
  fires(
    'a revision line',
    revisionProblemsIn(
      'Revised 2026-02-30, for the 1.0.0-rc.1 tree.\n',
      version: '1.0.0-rc.1',
      today: today,
    ).isNotEmpty,
    'a date that does not exist',
  );
  quiet(
    'a revision line',
    revisionProblemsIn(
      'Text first.\n\nRevised 2026-10-01, for the 1.0.0-rc.1 tree.\n',
      version: '1.0.0-rc.1',
      today: today,
    ).isEmpty,
    'an older date on the same version',
    'a document is revised for a version, not on a timer',
  );
  quiet(
    'a revision line',
    revisionProblemsIn(
      'Revised 2026-10-12, for the `1.0.0-rc.1` tree.\n',
      version: '1.0.0-rc.1',
      today: today,
    ).isEmpty,
    'the version written as code',
    'markdown may set the version in backticks',
  );

  // The kernel language's words. The clean table and parser are the shape
  // the real files have; each break below is one way back to a word
  // reserved in every version.
  const kernelTable = '''
const Map<String, int> kernelWordVersions = <String, int>{
  'let': 1,
  'atomicAdd': 2,
};
const Set<String> kernelWordsReservedEarly = <String>{'atomicAdd'};
const Set<String> kernelOtherLanguageWords = <String>{'material'};
''';
  const kernelParser = '''
switch (_word(word)) {
  case 'let' when word.kind == _Kind.ident:
  case 'atomicAdd':
}
if (_is('material')) {}
final c = switch (s) { 'x' || 'r' => 0, _ => 1 };
''';
  List<String> kernelWords({
    String table = kernelTable,
    String parser = kernelParser,
    int newest = 2,
  }) => kernelWordProblems(words: table, parser: parser, newest: newest);
  quiet(
    'kernel words',
    kernelWords().isEmpty,
    'a versioned table and the parser it covers',
    'every word has a version, the early one is version 2\'s, and the '
        'swizzle letters are not words',
  );
  fires(
    'kernel words',
    kernelWords(parser: "$kernelParser\ncase 'barrier':\n").isNotEmpty,
    'a statement word the table does not version',
  );
  fires(
    'kernel words',
    kernelWords(parser: "$kernelParser\n'shared' => 1,\n").isNotEmpty,
    'a switch arm\'s word the table does not version',
  );
  fires(
    'kernel words',
    kernelWords(
      table: kernelTable.replaceFirst("'atomicAdd': 2", "'atomicAdd': 3"),
    ).isNotEmpty,
    'a version after the newest this build reads',
  );
  final kernelThree = kernelTable.replaceFirst(
    "'atomicAdd': 2,",
    "'atomicAdd': 2,\n  'barrier': 3,",
  );
  quiet(
    'kernel words',
    kernelWords(table: kernelThree, newest: 3).isEmpty,
    'a version 3 word in a build that reads version 3',
    'a later version adds its words to the same table',
  );
  fires(
    'kernel words',
    kernelWords(
      table: kernelThree.replaceFirst(
        "{'atomicAdd'}",
        "{'atomicAdd', 'barrier'}",
      ),
      newest: 3,
    ).isNotEmpty,
    'a version 3 word taken before its version',
  );
  fires(
    'kernel words',
    kernelWords(
      table: kernelTable.replaceFirst("'let': 1", "'let': newest"),
    ).isNotEmpty,
    'a version that is not a number',
  );
  fires(
    'kernel words',
    kernelWords(
      parser: "const Set<String> _reserved = <String>{'let'};\n$kernelParser",
    ).isNotEmpty,
    'an unversioned word list kept in the parser',
  );

  // Check names. The spaced names are the ones the render suite shipped in
  // 1.0.0-rc.1; a report and a badge carry them as data.
  fires(
    'a check name',
    badCheckNames(<String>['render.lit model'], area: 'render').isNotEmpty,
    'render.lit model',
  );
  fires(
    'a check name',
    badCheckNames(<String>['lit model']).isNotEmpty,
    'lit model (no area)',
  );
  fires(
    'a check name',
    badCheckNames(<String>['litModel'], area: 'render').isNotEmpty,
    'a render check outside render.',
  );
  fires(
    'a check name',
    badCheckNames(<String>['Manifest']).isNotEmpty,
    'Manifest (upper case)',
  );
  fires(
    'a check name',
    badCheckNames(<String>['manifest']).isNotEmpty,
    'manifest (one word, no area)',
  );
  fires(
    'a check name',
    badCheckNames(<String>['render.manifest'], area: 'plugin').isNotEmpty,
    'a plugin check outside plugin.',
  );
  quiet(
    'a check name',
    badCheckNames(<String>[
          'plugin.manifest',
          'plugin.determinism',
        ], area: 'plugin').isEmpty &&
        badCheckNames(<String>[
          'render.litModelDefaults',
          'render.lightType',
        ], area: 'render').isEmpty,
    'plugin.manifest, render.litModelDefaults',
    'a word, camel-cased or not, after its area is a name',
  );
  fires(
    'a const string list',
    constStringListIn(
          "/// x\nconst List<String> checks = <String>[\n  'a', // one\n  'b',\n];",
          'checks',
        )?.join(',') ==
        'a,b',
    'a list of two',
  );
  quiet(
    'a const string list',
    constStringListIn("const List<String> other = <String>['a'];", 'checks') ==
        null,
    'a list of another name',
    'the rule names the list it compares',
  );
  fires(
    'a reported check name',
    reportedCheckNamesIn(
      "outcome('render.light type', false);\n"
      "PluginCheckOutcome(check: 'names', passed: true);",
    ).containsAll(<String>['render.light type', 'names']),
    'an outcome and a render literal',
  );
  quiet(
    'a reported check name',
    reportedCheckNamesIn(
      "// 'render.lit model' was the name\nfinal x = 'rendered';",
    ).isEmpty,
    'a comment and a word that starts with render',
    'only code reports a check',
  );

  // **A wire message under the reserved key.** The first two are the shapes
  // `flame_multiplayer`'s tape and the relay's welcome had before protocol
  // 3.1; the rule built on this is what keeps them from coming back.
  fires(
    'a bare wire message',
    bareWireMessagesIn('''
    wire.send(
      PeerSend(
        message: <String, Object?>{
          'tape': step,
          'frames': <String, Object?>{
            for (final MapEntry(:key, :value) in frames.entries) '\$key': value,
          },
        },
      ),
    );''').single.keys.join(',') ==
        'frames,tape',
    "PartyTape's bare `tape` and `frames`",
  );
  fires(
    'a bare wire message',
    bareWireMessagesIn(
      "socket.add(jsonEncode(<String, Object?>{'relay': 'welcome', "
      "'slot': slot}));",
    ).isNotEmpty,
    "the relay's bare `relay` welcome",
  );
  fires(
    'a bare wire message',
    bareWireMessagesIn(
      "send(PeerSend(message: const <String, Object?>{'watching': true}));",
    ).isNotEmpty,
    'a const literal',
  );
  fires(
    'a bare wire message',
    bareWireMessagesIn(
          "send(PeerSend(message: {if (asking) 'hello': h, 'n': 1}));",
        ).single.keys.join(',') ==
        'hello,n',
    'a key behind a collection `if`, untyped',
  );
  quiet(
    'a bare wire message',
    bareWireMessagesIn('''
      PeerSend(
        message: <String, Object?>{
          PeerWire.engineKey: _party,
          _event: _tape,
          'step': step,
          // 'tape': step, as it was.
          'frames': <String, Object?>{'0': <String, Object?>{'a': 1}},
        },
      );''').isEmpty,
    'a message under `PeerWire.engineKey`',
    'the reserved key is what the rule asks for',
  );
  quiet(
    'a bare wire message',
    bareWireMessagesIn(
      "jsonEncode(<String, Object?>{'f3d': 'relay', 'event': 'left'});",
    ).isEmpty,
    "a message under `'f3d'` spelled out",
    'the key is the key, however it is written',
  );
  quiet(
    'a bare wire message',
    bareWireMessagesIn(
      "/// `PeerSend(message: {'tape': 1})` was the old shape.\n"
      "final note = 'message: {\"tape\": 1}';",
    ).isEmpty,
    'a message in a comment and in a string',
    'prose explaining the rule must not break it',
  );

  // The shader ABI's shape. The clean file has one line of each kind the
  // real one has; each break is a fact the only-grows rule cannot lose
  // because the file never had it.
  const abi = '''
# header
entry MeshVertex vertex
stage Pbr block FragInfo
stage Pbr block FragInfo member light_color 128 128 8 Vector4
stage Pbr sampler environment_texture samplerCube
vertex MeshVertex in 0 vec3 position
vertex MeshVertex format 0 position float32x3
vertex MeshVertex out 0 vec3 v_world_position
fragment Pbr in 0 vec3 v_world_position
fragment Pbr out 0 vec4 frag_color
''';
  quiet(
    'shader ABI shape',
    shaderAbiShapeProblems(abi).isEmpty,
    'one line of every kind',
    'a sampler with its kind, both varyings and a format are the shape',
  );
  fires(
    'shader ABI shape',
    shaderAbiShapeProblems(
      abi.replaceFirst(' environment_texture samplerCube', ' environment'),
    ).isNotEmpty,
    'a sampler written by name alone',
  );
  fires(
    'shader ABI shape',
    shaderAbiShapeProblems(
      abi.replaceFirst('vertex MeshVertex out 0 vec3 v_world_position\n', ''),
    ).isNotEmpty,
    'a file with no vertex varyings',
  );
  fires(
    'shader ABI shape',
    shaderAbiShapeProblems(
      abi.replaceFirst('vertex MeshVertex format 0 position float32x3\n', ''),
    ).isNotEmpty,
    'an attribute with no format',
  );
  // The only-grows check over the new lines: a varying inserted before
  // another moves its index, a sampler turned into a cube changes its line,
  // and an array grown past its length moves its byte count (eight forward
  // lights and sixteen decals a draw are held this way).
  final abiBase = abi.replaceFirst(
    'vertex MeshVertex out 0 vec3 v_world_position',
    'vertex MeshVertex out 0 vec3 v_world_position\n'
        'vertex MeshVertex out 1 vec3 v_normal',
  );
  fires(
    'shader ABI only grows',
    factLines(abiBase).any(
      (String line) => !factLines(
        abiBase.replaceFirst('out 1 vec3 v_normal', 'out 2 vec3 v_normal'),
      ).contains(line),
    ),
    'a varying moved to another index',
  );
  fires(
    'shader ABI only grows',
    !factLines(
      abi.replaceFirst(
        'member light_color 128 128 8',
        'member light_color '
            '128 256 16',
      ),
    ).contains('stage Pbr block FragInfo member light_color 128 128 8 Vector4'),
    'eight lights grown to sixteen',
  );

  // The vocabularies. The base reads up to version 2; the current file adds
  // a word, and each break is a way back to a word 1.0 would not know.
  const vocabularyBase = '''
# header
kernel version 2
kernel word let 1
kernel word atomicAdd 2
''';
  List<String> vocabulary(String current) =>
      vocabularyProblems(base: vocabularyBase, current: current);
  quiet(
    'vocabulary',
    vocabulary(
      vocabularyBase
          .replaceFirst('version 2', 'version 3')
          .replaceFirst(
            'atomicAdd 2\n',
            'atomicAdd 2\nkernel word barrier 3\n',
          ),
    ).isEmpty,
    'a version 3 word in a build that reads version 3',
    'a word new since the base arrives with a version above its newest',
  );
  fires(
    'vocabulary',
    vocabulary('${vocabularyBase}kernel word barrier 2\n').isNotEmpty,
    'a word new since the base, under a version the base read',
  );
  fires(
    'vocabulary',
    vocabulary('${vocabularyBase}kernel word barrier 3\n').isNotEmpty,
    'a word of a version this build does not read',
  );
  fires(
    'vocabulary',
    vocabulary(
      vocabularyBase.replaceFirst('kernel word let 1\n', ''),
    ).isNotEmpty,
    'a word of the base dropped',
  );
  fires(
    'vocabulary',
    vocabulary('${vocabularyBase}kernel word barrier\n').isNotEmpty,
    'a word with no version',
  );
  fires(
    'vocabulary',
    vocabulary(
      vocabularyBase.replaceFirst('version 2', 'version 1'),
    ).isNotEmpty,
    'the newest version going down',
  );

  // Where a base came from.
  const recorded = '# Recorded from v1.0.0-rc.1 (abcdef012345) by the tool.\n';
  quiet(
    'abi base',
    abiBaseProblems(
      base: '$recorded$vocabularyBase',
      atTag: (_) => vocabularyBase,
    ).isEmpty,
    'a base that is the tag\'s file',
    'the header is not a fact',
  );
  quiet(
    'abi base',
    abiBaseProblems(
      base: '# Recorded from the working tree.\n$vocabularyBase',
      atTag: (_) => throw StateError('no tag to read'),
    ).isEmpty,
    'a base recorded before the tag',
    'before the tag there is nothing to hold it to',
  );
  fires(
    'abi base',
    abiBaseProblems(
      base: '$recorded${vocabularyBase}kernel word barrier 3\n',
      atTag: (_) => vocabularyBase,
    ).isNotEmpty,
    'a base edited by hand after the tag',
  );
  fires(
    'abi base',
    abiBaseProblems(base: vocabularyBase, atTag: (_) => null).isNotEmpty,
    'a base that says nowhere what it was recorded from',
  );

  // Every frame resource has a row that says what it holds.
  const framePlan = '''
abstract final class FrameResourceIds {
  static const ResourceId hdrColor = ResourceId('f3d.hdr_color');
  static const ResourceId cubeShadowStatic = ResourceId(
    'f3d.cube_shadow_static',
  );
  static ResourceId reflectionProbe(int index) =>
      ResourceId('f3d.reflection_probe_\$index');
}
''';
  const contracts = '''
### Frame resources a stage reads

| Resource | What it holds |
|---|---|
| `f3d.hdr_color` | The scene's light. |
| `f3d.cube_shadow_static` | Readable, encoding not frozen. |
| `f3d.reflection_probe_<n>` | Readable, encoding not frozen. |

## Names
''';
  quiet(
    'frame resource rows',
    frameResourceRowProblems(
      framePlan: framePlan,
      contracts: contracts,
    ).isEmpty,
    'a row for each resource, the probe family among them',
    'a constructor spread over lines is a resource too',
  );
  fires(
    'frame resource rows',
    frameResourceRowProblems(
      framePlan: framePlan.replaceFirst(
        '}\n',
        "  static const ResourceId ao = ResourceId('f3d.ao');\n}\n",
      ),
      contracts: contracts,
    ).isNotEmpty,
    'a resource added without a row',
  );
  fires(
    'frame resource rows',
    frameResourceRowProblems(
      framePlan: framePlan,
      contracts: contracts.replaceFirst(
        '| `f3d.hdr_color` | The scene\'s light. |',
        '| `hdr_color` | The scene\'s light. |',
      ),
    ).isNotEmpty,
    'a row under the name from before the rename',
  );

  // Platform channel names. The negative is the name the cloud saves had.
  fires(
    'a channel outside dev.flutter3d/',
    channelNamesOutsideNamespaceIn(
      "_channel = channel ?? const MethodChannel('flutter3d/cloud_saves');",
    ).contains('flutter3d/cloud_saves'),
    "MethodChannel('flutter3d/cloud_saves')",
  );
  fires(
    'a channel outside dev.flutter3d/',
    channelNamesOutsideNamespaceIn(
      "static const EventChannel _channel = EventChannel(\n"
      "    'gamepad/events',\n  );",
    ).isNotEmpty,
    'an event channel with its name on the next line',
  );
  quiet(
    'a channel outside dev.flutter3d/',
    channelNamesOutsideNamespaceIn(
      "const EventChannel('dev.flutter3d/stereo/head');\n"
      "/// Was `MethodChannel('flutter3d/cloud_saves')`.",
    ).isEmpty,
    'an engine channel, and the old name in a comment',
    'the namespace is the rule, and prose explaining it must not break it',
  );

  // Platform calls without the catch. The negative is pointer lock's own
  // `capture` as it was.
  fires(
    'a platform call without MissingPluginException',
    unguardedPlatformCallsIn(
      "Future<void> capture() => methodChannel.invokeMethod<void>('capture');",
    ).isNotEmpty,
    "methodChannel.invokeMethod<void>('capture')",
  );
  fires(
    'a platform call without MissingPluginException',
    unguardedPlatformCallsIn(
      'Future<void> f() async {\n'
      "  try {\n    await c.invokeMapMethod('a');\n"
      '  } on PlatformException {\n    return;\n  }\n}',
    ).isNotEmpty,
    'a call caught for another exception',
  );
  quiet(
    'a platform call without MissingPluginException',
    unguardedPlatformCallsIn(
      'Future<void> _call(String method) async {\n'
      '  try {\n    if (ready) { await methodChannel.invokeMethod<void>(method); }\n'
      '  } on MissingPluginException {\n    return;\n  }\n}',
    ).isEmpty,
    'a call inside a try that catches it, under a nested block',
    'a guarded call is the rule kept',
  );

  // The HAL's contract with its backends: `hal.dart` keeps its own proofs.
  broken.addAll(proveHalDetectorsWork());

  return broken;
}

// ------------------------------------------------------- the engine's number

/// Whether a package at [version] is on the engine's number [engine].
///
/// **The number is a major.minor, not a full version** (decided by Dmitrii
/// on 2026-10-12). A patch goes to the one package that needs it, so
/// `flutter3d_impeller` can be 1.0.1 beside the rest at 1.0.0, typically
/// after a Flutter release changed `flutter_gpu`, and every sibling's
/// `^1.0.0` still reaches it. Holding every package to the same full
/// version would force 60 uploads for one fix. Off the number is a package
/// another minor or major apart, or one the engine's caret cannot reach
/// (a pre-release under a final release).
bool onEngineNumber(String version, String engine) {
  if (version == engine) return true;
  final (v, e) = (parseVersion(version), parseVersion(engine));
  return v != null &&
      e != null &&
      v.major == e.major &&
      v.minor == e.minor &&
      caretAdmits(engine, version);
}

/// The packages of [packages] off the engine's number [engine], in order:
/// each at a version [onEngineNumber] does not put on it, unless it names
/// no sibling.
///
/// **Every package that stands on another of the repository carries the
/// engine's number.** A number of its own says nothing a reader can use and
/// moves five places at once when it changes; a package outside the 1.0
/// promise says so in SUPPORT.md and by its reasoned third-party
/// exemptions, not by a 0.x line. A package that names no sibling
/// (`pad_input`, `flutter3d_pointer_lock`) is a platform plugin anybody may
/// use without the engine, on a line of its own.
List<String> offTheEngineNumber(
  Map<String, ({String version, bool namesSibling})> packages,
  String engine,
) => <String>[
  for (final MapEntry(key: name, value: p) in packages.entries)
    if (p.namesSibling && !onEngineNumber(p.version, engine)) name,
];

// ------------------------------------------------------- a policy's revision

/// What is wrong with the revision line of a policy document such as
/// SECURITY.md or ROADMAP.md, or nothing.
///
/// The line reads `Revised YYYY-MM-DD, for the <version> tree.` The date has
/// to exist and not be after [today]; the version has to be [version], the
/// one the engine's packages carry, exactly. So a version bump turns the rule
/// red until somebody rereads both documents and moves the line, which is the
/// moment both go stale: a support window, a scope and a plan are all
/// written for one release.
List<String> revisionProblemsIn(
  String text, {
  required String version,
  required DateTime today,
}) {
  // The version may be written as code, `1.0.0-rc.1`, or plain.
  final line = RegExp(
    r'^Revised ((\d{4})-(\d{2})-(\d{2})), for the `?([^\s`]+)`? tree\.',
    multiLine: true,
  ).firstMatch(text);
  if (line == null) {
    const why = 'saying when it was last reread and for which release';
    return <String>[
      'has no line "Revised YYYY-MM-DD, for the $version tree." $why',
    ];
  }
  final written = line.group(1)!;
  final (year, month, day) = (
    int.parse(line.group(2)!),
    int.parse(line.group(3)!),
    int.parse(line.group(4)!),
  );
  final date = DateTime.utc(year, month, day);
  final exists = date.year == year && date.month == month && date.day == day;
  final said = line.group(5);
  const reread = 'reread it for this release and move the line';
  return <String>[
    if (!exists)
      'is revised on $written, a date that does not exist'
    else if (date.isAfter(today))
      'is revised on $written, after today',
    if (said != version)
      'was revised for $said, and the packages are at $version: $reread',
  ];
}

// ------------------------------------------------------------- a test's minute

/// One place a test or a package is given longer than a minute.
typedef LongTimeout = ({int line, String says});

/// The longest a test may run without its reason being written down.
const Duration testMinute = Duration(minutes: 1);

/// Where [source], a Dart file under a `test/` directory, gives a test or a
/// file longer than [testMinute]: a `Timeout` of a longer `Duration`, a
/// `Timeout.factor` above one, or `Timeout.none`.
///
/// **A duration it cannot read is reported too**, as a duration it cannot
/// read. `Timeout(budget)` could be anything, and a rule that let it through
/// would be a rule with a door in it.
///
/// Comments are left out, so a doc comment recalling the allowance a test
/// once had is not the allowance. A future's own `.timeout(...)` is not a
/// test's and is not read.
List<LongTimeout> longTimeoutsIn(String source) {
  final code = <String>[
    for (final line in source.split('\n')) _codeOf(line),
  ].join('\n');
  int lineAt(int offset) =>
      '\n'.allMatches(code.substring(0, offset)).length + 1;

  final found = <LongTimeout>[];
  for (final match in RegExp(r'\bTimeout\s*\(').allMatches(code)) {
    // To the parenthesis that closes this one, counted rather than matched:
    // `Timeout(Duration(minutes: 3))` ends on its second, and the formatter
    // is free to put a line break anywhere inside it.
    var depth = 1;
    var at = match.end;
    while (at < code.length && depth > 0) {
      final char = code[at];
      if (char == '(') depth++;
      if (char == ')') depth--;
      at++;
    }
    final inside = code
        .substring(match.end, depth == 0 ? at - 1 : at)
        .trim()
        .replaceAll(RegExp(r',$'), '')
        .trim();
    final duration = RegExp(
      r'^(?:const\s+)?Duration\s*\(([^)]*)\)$',
    ).firstMatch(inside);
    final Duration? given = duration == null
        ? null
        : _durationOf(duration.group(1)!);
    if (given == null) {
      found.add((
        line: lineAt(match.start),
        says: 'Timeout($inside), a duration this cannot read',
      ));
    } else if (given > testMinute) {
      found.add((
        line: lineAt(match.start),
        says: 'Timeout of ${given.inSeconds} s',
      ));
    }
  }
  for (final match in RegExp(
    r'\bTimeout\.factor\s*\(\s*([0-9.]+)\s*\)',
  ).allMatches(code)) {
    final factor = double.tryParse(match.group(1)!);
    if (factor == null || factor > 1) {
      found.add((
        line: lineAt(match.start),
        says: 'Timeout.factor(${match.group(1)})',
      ));
    }
  }
  for (final match in RegExp(r'\bTimeout\.none\b').allMatches(code)) {
    found.add((line: lineAt(match.start), says: 'Timeout.none'));
  }
  return found;
}

/// The `Duration` a list of named literal arguments describes, or null for
/// one written any other way.
Duration? _durationOf(String arguments) {
  const Map<String, int> micros = <String, int>{
    'days': Duration.microsecondsPerDay,
    'hours': Duration.microsecondsPerHour,
    'minutes': Duration.microsecondsPerMinute,
    'seconds': Duration.microsecondsPerSecond,
    'milliseconds': Duration.microsecondsPerMillisecond,
    'microseconds': 1,
  };
  final parts = arguments
      .split(',')
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  var total = 0;
  for (final part in parts) {
    final named = RegExp(r'^(\w+)\s*:\s*([0-9]+)$').firstMatch(part);
    final unit = named == null ? null : micros[named.group(1)!];
    if (named == null || unit == null) return null;
    total += int.parse(named.group(2)!) * unit;
  }
  return Duration(microseconds: total);
}

/// Where [yaml], a `dart_test.yaml`, gives longer than [testMinute]: the
/// package's own `timeout:`, or one in a tag, a preset or a platform.
///
/// `1m`, `60s` and `1x` are the minute; `none` is not a minute at all. A
/// value it cannot read is reported, for the reason [longTimeoutsIn] gives.
List<LongTimeout> longYamlTimeoutsIn(String yaml) {
  final lines = yaml.split('\n');
  final found = <LongTimeout>[];
  for (var i = 0; i < lines.length; i++) {
    final match = RegExp(
      r'^\s*timeout:\s*(\S+)',
    ).firstMatch(lines[i].split('#').first);
    if (match == null) continue;
    final value = match.group(1)!.replaceAll(RegExp('["\']'), '');
    final unit = RegExp(r'^([0-9.]+)(ms|s|m|h|x)$').firstMatch(value);
    final bool long;
    if (unit == null) {
      long = true;
    } else {
      final amount = double.parse(unit.group(1)!);
      long = switch (unit.group(2)!) {
        'ms' => amount > 60000,
        's' => amount > 60,
        'm' => amount > 1,
        'h' => amount > 0,
        _ => amount > 1, // a factor of the minute
      };
    }
    if (long) found.add((line: i + 1, says: 'timeout: $value'));
  }
  return found;
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

// --------------------------------------------------- an accessible UI

/// The 1-based lines of [code] that [pattern] matches, [code] being source
/// with its comments already removed.
List<int> _linesMatching(String code, RegExp pattern) {
  final lines = code.split('\n');
  return <int>[
    for (var i = 0; i < lines.length; i++)
      if (pattern.hasMatch(lines[i])) i + 1,
  ];
}

final RegExp _typedColor = RegExp(
  r'\bColors\.\w|\bColor\s*\(\s*0x|\bColor\.(?:fromARGB|fromRGBO|from)\s*\(',
);

/// The 1-based lines of [source] that type a colour in: `Colors.white`,
/// `Color(0x…)`, `Color.fromARGB(…)`.
///
/// **A colour typed into a widget is a colour no contrast check sees.** The
/// tokens of a theme are held to WCAG's ratios over any frame
/// (`GameUiTheme.contrastPairs`); a `Colors.white.withValues(alpha: 0.55)` in
/// a widget is a pair nobody named, and the touch controls were exactly
/// that, a third of white over a sky.
List<int> typedColorsIn(String source) =>
    _linesMatching(codeOf(source), _typedColor);

final RegExp _fixedTextScale = RegExp(
  r'\bTextScaler\.noScaling\b|\btextScaleFactor\b|\bTextScaler\.linear\s*\(',
);

/// The 1-based lines of [source] that pin the text size: a
/// `TextScaler.noScaling`, a `textScaleFactor`, a `TextScaler.linear(…)`.
List<int> fixedTextScalesIn(String source) =>
    _linesMatching(codeOf(source), _fixedTextScale);

/// The 1-based lines of [source] that make a `TextPainter` without handing
/// it a `textScaler` before its arguments close.
///
/// **A painter's text does not scale unless it is told to**: `TextPainter`
/// defaults to `TextScaler.noScaling`, so a label painted on a canvas stays
/// small on a phone set to large text while every `Text` beside it grows.
List<int> unscaledTextPaintersIn(String source) {
  final code = codeOf(source);
  final found = <int>[];
  for (final match in RegExp(r'\bTextPainter\s*\(').allMatches(code)) {
    var depth = 0;
    var end = match.end - 1;
    for (; end < code.length; end++) {
      if (code[end] == '(') depth++;
      if (code[end] == ')' && --depth == 0) break;
    }
    if (!code.substring(match.start, end).contains('textScaler')) {
      found.add('\n'.allMatches(code.substring(0, match.start)).length + 1);
    }
  }
  return found;
}

final RegExp _pointerWidget = RegExp(
  r'\b(?:GestureDetector|RawGestureDetector|Listener|InkWell)\s*\(',
);
final RegExp _semanticsWidget = RegExp(r'\b(?:Merge)?Semantics\s*\(');

/// How many lines above a widget that takes the pointer its `Semantics` may
/// open: the wrapper, its flags and label, and a `child:` that calls the
/// method building the widget.
const int semanticsReach = 12;

/// The 1-based lines of [source] that make a widget taking the pointer —
/// a `GestureDetector`, a `Listener`, an `InkWell` — with no `Semantics` or
/// `MergeSemantics` opened in the [semanticsReach] lines above it.
///
/// **A control a screen reader cannot name is a control that is not there**
/// for its user. Flutter's own controls carry their semantics; a widget
/// built from a bare `Listener` carries none, and the stick, the pedals and
/// the title sheet that began a game on any touch were each one.
List<int> unnamedPointerWidgetsIn(String source) {
  final lines = codeOf(source).split('\n');
  return <int>[
    for (var i = 0; i < lines.length; i++)
      if (_pointerWidget.hasMatch(lines[i]) &&
          !lines
              .sublist(i - semanticsReach < 0 ? 0 : i - semanticsReach, i + 1)
              .any(_semanticsWidget.hasMatch))
        i + 1,
  ];
}

final RegExp _animates = RegExp(
  r'\b(?:AnimationController|TweenAnimationBuilder|AnimatedContainer|'
  r'AnimatedOpacity|AnimatedPositioned|AnimatedSwitcher|AnimatedScale|'
  r'AnimatedSlide|AnimatedRotation|AnimatedAlign|AnimatedPadding)\s*[<(]|'
  r'\bcreateTicker\s*\(',
);
final RegExp _readsReducedMotion = RegExp(
  r'[dD]isableAnimations|\breduceMotion\b|\bAccommodations\b',
);

/// The 1-based lines of [source] that animate — a controller, a ticker, an
/// implicitly animated widget — in a library that never reads whether the
/// player asked for less motion (`MediaQuery.disableAnimationsOf`,
/// `Accommodations.reduceMotion`). Empty when it reads it.
List<int> motionWithoutReductionIn(String source) {
  final code = codeOf(source);
  if (_readsReducedMotion.hasMatch(code)) return const <int>[];
  return _linesMatching(code, _animates);
}

/// What an accessibility test [source] does not do of what the promise
/// asks, one phrase each; empty when it does all of it.
///
/// It asks Flutter's guidelines for labelled targets, target size and text
/// contrast, and it mounts at a larger text size through a `textScaler`.
/// `tool/ci.sh` finds it by its path, `test/accessibility_test.dart`.
List<String> accessibilityTestGapsIn(String source) {
  final code = codeOf(source);
  return <String>[
    if (!code.contains('labeledTapTargetGuideline'))
      'never asks `labeledTapTargetGuideline`',
    if (!code.contains('MinimumTapTargetGuideline') &&
        !code.contains('androidTapTargetGuideline'))
      'never asks a target-size guideline',
    if (!code.contains('textContrastGuideline'))
      'never asks `textContrastGuideline`',
    if (!RegExp('[tT]extScaler').hasMatch(code))
      'never mounts at a larger text size',
  ];
}

// ------------------------------------------------------------- wire messages

/// A message literal a wire encoder sends that has no reserved key: its
/// 1-based line and its top-level keys, sorted, a spread written `...`.
typedef BareWireMessage = ({int line, List<String> keys});

/// Where a message is built: the map handed to `PeerSend(message: …)`, or
/// the one a relay encodes and writes to a socket (`jsonEncode(…)`).
final RegExp _wireMessageStart = RegExp(
  r'(?:\bmessage:\s*|\bjsonEncode\(\s*)(?:const\s+)?\{',
);

/// The messages in [source] that a wire encoder sends with no reserved key
/// at their top level — neither `'f3d'` nor a name ending in `engineKey`
/// (`PeerWire.engineKey`). A bare top-level key on a shared wire is one a
/// game's own message can carry, so a game's message is taken for the
/// engine's or the engine's for a game's; and a key added there later
/// cannot be told from what an older build sends.
///
/// Comments and string contents are read past, so prose and a quoted `{`
/// change nothing. A key behind a collection `if` counts as a key; a
/// spread is `...`, since what it spreads is not visible here.
List<BareWireMessage> bareWireMessagesIn(String source) {
  final found = <BareWireMessage>[];
  final code = _blankTypeArguments(_blankCommentsAndStrings(source));
  for (final start in _wireMessageStart.allMatches(code)) {
    final open = start.end - 1;
    final close = _closing(code, open);
    if (close < 0) continue;
    final keys = <String>[];
    var reserved = false;
    var at = open + 1;
    for (final entry in _topLevel(code, open + 1, close)) {
      final entryStart = at;
      at += entry.length + 1;
      var offset = 0;
      final text = entry;
      String trimmed() => text.substring(offset).trimLeft();
      // `if (…) key: value` — the key after the condition.
      while (RegExp(r'^if\s*\(').hasMatch(trimmed())) {
        final lead = text.length - trimmed().length;
        final shut = _closing(text, text.indexOf('(', lead));
        if (shut < 0) break;
        offset = shut + 1;
      }
      final rest = trimmed();
      if (rest.isEmpty) continue;
      if (rest.startsWith('...')) {
        keys.add('...');
        continue;
      }
      final colon = _topLevelColon(rest);
      if (colon < 0) continue;
      final keyAt = entryStart + (text.length - rest.length);
      final written = source.substring(keyAt, keyAt + colon).trim();
      final name =
          RegExp(r"""^(['"])(\w*)\1$""").firstMatch(written)?.group(2) ??
          written;
      if (name == 'f3d' || RegExp(r'(?:^|\.)_?engineKey$').hasMatch(name)) {
        reserved = true;
      }
      keys.add(name);
    }
    if (reserved) continue;
    found.add((
      line: '\n'.allMatches(code.substring(0, start.start)).length + 1,
      keys: keys..sort(),
    ));
  }
  return found;
}

/// [source] with every comment and the inside of every string literal
/// turned to spaces, newlines kept, so offsets and lines still match.
String _blankCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end < 0 ? source.length : end + 2;
      for (; i < stop; i++) {
        out.write(source[i] == '\n' ? '\n' : ' ');
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final quote = source.startsWith(c * 3, i) ? c * 3 : c;
      out.write(quote);
      i += quote.length;
      while (i < source.length && !source.startsWith(quote, i)) {
        if (source[i] == r'\' && i + 1 < source.length) {
          out.write('  ');
          i += 2;
          continue;
        }
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < source.length) {
        out.write(quote);
        i += quote.length;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// [code] with the type arguments of a literal (`<String, Object?>{`)
/// turned to spaces, so their comma splits no entry and a `<` or `>` left
/// is a comparison or an arrow.
String _blankTypeArguments(String code) => code.replaceAllMapped(
  RegExp(r'<[A-Za-z_][\w\s,?<>.]*>(?=\s*[\{\[])'),
  (Match m) => ' ' * m.group(0)!.length,
);

/// The index of the bracket closing the one at [open] in [code], whose
/// strings and comments are blank; -1 when it never closes.
int _closing(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    switch (code[i]) {
      case '(' || '[' || '{':
        depth++;
      case ')' || ']' || '}':
        depth--;
        if (depth == 0) return i;
    }
  }
  return -1;
}

/// The comma-separated entries of [code] between [from] and [to], split at
/// depth nought only.
List<String> _topLevel(String code, int from, int to) {
  final entries = <String>[];
  var depth = 0;
  var start = from;
  for (var i = from; i < to; i++) {
    switch (code[i]) {
      case '(' || '[' || '{':
        depth++;
      case ')' || ']' || '}':
        depth--;
      case ',' when depth == 0:
        entries.add(code.substring(start, i));
        start = i + 1;
    }
  }
  entries.add(code.substring(start, to));
  return entries;
}

/// The first `:` of [entry] at depth nought, the one after a map key.
int _topLevelColon(String entry) {
  var depth = 0;
  for (var i = 0; i < entry.length; i++) {
    switch (entry[i]) {
      case '(' || '[' || '{':
        depth++;
      case ')' || ']' || '}':
        depth--;
      case ':' when depth == 0:
        return i;
    }
  }
  return -1;
}

// ------------------------------------------------------- the engine's words

/// Each render name [source] declares that does not carry its namespace:
/// the literal of a `RenderAnchor._`, `RenderAnchor.after`, `RenderStep._`,
/// `RenderStep(` or `ResourceId(`, when it is not `<namespace>.<word>` with
/// no space in it — or, for the [engine]'s own packages, not `f3d.<word>`.
///
/// **Decision 23 for the engine's half.** A plugin's names were refused
/// without their namespace from the start (`PluginManifest.nameProblem`),
/// and the engine's went on the wire as `after bloom`, `scene_color` and
/// `color grade`: spaces, no `f3d.`, written into every `f3d.pipeline`. A
/// name that is interpolated (`'${id.name}#$index'`) is built from one that
/// was checked and is not read, and neither is a template's `{{name}}`,
/// which the generated plugin fills with its own namespace.
List<String> unprefixedRenderNamesIn(String source, {required bool engine}) =>
    <String>[
      for (final m in RegExp(
        r"(?:RenderAnchor\._\(|RenderAnchor\.after\([^,()]+,|"
        r"RenderStep\._\(|RenderStep\(|ResourceId\()\s*'([^'$]*)'",
      ).allMatches(codeOf(source)))
        if (!m.group(1)!.contains('{{') &&
            !RegExp(
              engine ? r'^f3d\.[a-z0-9_]+$' : r'^[a-z][a-z0-9_]*\.[^ ]+$',
            ).hasMatch(m.group(1)!))
          m.group(1)!,
    ];

// ---------------------------------------------- pins on a sibling, in text

/// Each `<package>: ^<version>` pin [source] writes on one of [packages],
/// as package and constraint: the lines a template writes into a project's
/// `pubspec.yaml` or `analysis_options.yaml`, read where they are quoted.
///
/// **What broke when a package left the engine's number.** The plugin
/// template wrote `flutter3d_lints: ^1.0.0-rc.1` into every generated
/// plugin's analysis options, which no 0.x release of the lints satisfies,
/// so the analysis server could not load the plugin and nothing said so.
List<(String, String)> siblingPinsIn(String source, Set<String> packages) =>
    <(String, String)>[
      for (final m in RegExp(
        r'^\s*([a-z][a-z0-9_]*):\s*(\^[0-9][^\s\x27"]*)',
        multiLine: true,
      ).allMatches(source))
        if (packages.contains(m.group(1)) && !m.group(2)!.contains(r'$'))
          (m.group(1)!, m.group(2)!),
    ];

// ------------------------------------------------- platform channel names

/// Each platform channel name [source] opens a channel on that is not under
/// `dev.flutter3d/`.
///
/// **A channel name is a wire, and it cannot move once a 1.0 build answers
/// on it.** The cloud saves were on `flutter3d/cloud_saves` while every
/// other channel of the engine was `dev.flutter3d/…`: renaming it later is a
/// break for every native side that answers it. A name built from a variable
/// is not read; the literal is the one a native side copies.
List<String> channelNamesOutsideNamespaceIn(String source) => <String>[
  for (final m in RegExp(
    r'\b(?:MethodChannel|EventChannel|BasicMessageChannel|'
    r"OptionalMethodChannel)\s*\(\s*'([^'$]*)'",
  ).allMatches(codeOf(source)))
    if (!m.group(1)!.startsWith('dev.flutter3d/')) m.group(1)!,
];

// ------------------------------------- a native side that lacks a method

/// The 1-based lines of [source] that call a method on a platform channel
/// outside a `try` that catches `MissingPluginException`.
///
/// **A native side that lacks a method throws out of a call nobody
/// wrapped.** A package the engine pins at `^0.5.0` can meet a native side
/// without the handler for a method a later minor adds, and `invokeMethod`
/// then throws out of a call the game never guarded. Catching it in Dart is
/// only possible before the method exists, so every call catches it now.
///
/// Read by braces: a call counts as guarded when some `try {` before it
/// closes after it and the clause after its block is
/// `on MissingPluginException`.
List<int> unguardedPlatformCallsIn(String source) {
  final code = codeOf(source);
  final tries = <(int, int)>[
    for (final t in RegExp(r'\btry\s*\{').allMatches(code))
      if (_blockEnd(code, t.end - 1) case final int end
          when RegExp(
            r'^\s*on\s+MissingPluginException\b',
          ).hasMatch(code.substring(end + 1)))
        (t.end, end),
  ];
  return <int>[
    for (final call in RegExp(
      r'\.invoke(?:Map|List)?Method\s*[<(]',
    ).allMatches(code))
      if (!tries.any(((int, int) t) => t.$1 <= call.start && call.start < t.$2))
        '\n'.allMatches(code.substring(0, call.start)).length + 1,
  ];
}

/// The offset of the `}` closing the `{` at [open] in [code], or null.
int? _blockEnd(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    switch (code[i]) {
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) return i;
    }
  }
  return null;
}
