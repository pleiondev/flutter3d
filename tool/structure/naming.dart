/// The naming conventions of the 1.0 API (§E.1–E.5 and E.10 of
/// `tasks/1.0-api-review.md`, items 28 and 29 of `1.0-scope-additions.md`),
/// read off the API snapshots: what the structure rules in `rules.dart` that
/// keep them hold, and the proof each detector fires.
///
/// **Snapshots, not source**, for the reason `interfaceClassesIn` gives: the
/// snapshot is the promise, and a name behind a `src/` path nobody exports is
/// nobody's to keep. The one convention a snapshot cannot see — that a
/// number's doc comment names its unit — reads the source instead
/// ([undocumentedUnitsIn]).
///
/// Plain Dart over text, like `api.dart`: the scan runs before `pub get`.
library;

import 'api.dart';

/// A declaration and what is wrong with its name.
typedef NamingProblem = ({String subject, String what});

/// The words that spell a British identifier, as a fragment of a camelCase
/// name, with the American spelling each becomes. Docs may stay British; an
/// identifier is spelled the way Flutter and Dart spell theirs.
const Map<String, String> britishSpellings = <String, String>{
  'colour': 'color',
  'centre': 'center',
  'metre': 'meter',
  'behaviour': 'behavior',
  'licence': 'license',
  'armour': 'armor',
  'neighbour': 'neighbor',
  'tyre': 'tire',
  'favour': 'favor',
  'honour': 'honor',
  'flavour': 'flavor',
  'grey': 'gray',
  'normalis': 'normaliz',
  'quantis': 'quantiz',
  'randomis': 'randomiz',
  'specialis': 'specializ',
  'recognis': 'recogniz',
  'initialis': 'initializ',
  'serialis': 'serializ',
  'optimis': 'optimiz',
  'organis': 'organiz',
  'visualis': 'visualiz',
  'synchronis': 'synchroniz',
  'minimis': 'minimiz',
  'maximis': 'maximiz',
  'summaris': 'summariz',
  'customis': 'customiz',
  'prioritis': 'prioritiz',
  'stabilis': 'stabiliz',
  'materialis': 'materializ',
  'equalis': 'equaliz',
  'localis': 'localiz',
  'analyse': 'analyze',
  'cancelled': 'canceled',
  'cancelling': 'canceling',
  'travelled': 'traveled',
  'travelling': 'traveling',
  'labelled': 'labeled',
  'modelled': 'modeled',
  'signalling': 'signaling',
  'bevelled': 'beveled',
  'journalled': 'journaled',
  'analogue': 'analog',
  'catalogue': 'catalog',
  'dialogue': 'dialog',
  'fibre': 'fiber',
  'litre': 'liter',
  'defence': 'defense',
};

/// The camelCase words of [identifier], lower-cased: `sunColourSrgb` is
/// `sun`, `colour`, `srgb`; `HDRColour` is `hdr`, `colour`.
List<String> camelWords(String identifier) => <String>[
  for (final m in RegExp(
    r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+',
  ).allMatches(identifier.replaceAll(r'$', '')))
    m.group(0)!.toLowerCase(),
];

/// The British word in [identifier], or null.
///
/// Matched against whole camelCase words — a word's start for the verbs
/// (`normalis…`), anywhere in it for the longer nouns (`recentre`) — so
/// `EntityRegistry` is not a `tyre` and `materialIssues` is not a
/// `materialis…`.
String? britishWordIn(String identifier) {
  for (final word in camelWords(identifier)) {
    for (final british in britishSpellings.keys) {
      final verb = british.endsWith('is') || british.endsWith('ys');
      if (word == british ||
          word == '${british}s' ||
          (verb && word.startsWith(british) && word.length > british.length) ||
          (!verb && british.length >= 5 && word.contains(british))) {
        return british;
      }
    }
  }
  return null;
}

/// Every identifier a snapshot declares or names in a signature — types,
/// members, parameters — outside its string literals.
Set<String> identifiersIn(String snapshot) => <String>{
  for (final line in snapshot.split('\n'))
    if (!line.startsWith('#'))
      for (final m in RegExp(
        r'[A-Za-z_$][\w$]*',
      ).allMatches(line.replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''")))
        m.group(0)!,
};

/// Each British-spelled identifier in [snapshot], with the word.
List<NamingProblem> britishIdentifiersIn(String snapshot) => <NamingProblem>[
  for (final id in identifiersIn(snapshot).toList()..sort())
    if (britishWordIn(id) case final word?)
      (
        subject: id,
        what:
            'spells `$word` the British way; an identifier is spelled '
            '`${britishSpellings[word]}`, as Flutter and Dart spell theirs',
      ),
];

// ------------------------------------------------------------------ verbs

/// The verbs that end an object's life. A type keeps one: `dispose`, or
/// `close` for a connection or a stream.
const Set<String> teardownVerbs = <String>{
  'dispose',
  'close',
  'shutdown',
  'destroy',
  'teardown',
  'tearDown',
};

/// The type-level problems with verbs in [snapshot]: a type with two
/// teardown verbs, a method named with `make`, `take` or `get`, and an
/// asynchronous `create` (one that returns a `Future` and is not the
/// `…Async` variant of a synchronous one).
List<NamingProblem> verbProblemsIn(String snapshot) {
  final out = <NamingProblem>[];
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final ending = <String>{};
      final lines = <String>[block.header, ...block.members];
      for (final line in lines) {
        final isHeader = identical(line, block.header);
        final bare = splitAnnotations(line).rest;
        if (!bare.contains('(')) continue;
        if (RegExp(r'(^|\s)(get|set)\s').hasMatch(bare.split('(').first)) {
          continue;
        }
        final name = memberName(line);
        final short = name.contains('.') ? name.split('.').last : name;
        final subject = isHeader ? short : '$type.$short';
        if (isHeader &&
            RegExp(
              r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
              r'(class|enum|mixin|extension|typedef)\b',
            ).hasMatch(bare)) {
          continue;
        }
        if (!isHeader && teardownVerbs.contains(short)) ending.add(short);
        if (RegExp(r'^(make|take|get)([A-Z_]|$)').hasMatch(short)) {
          out.add((
            subject: subject,
            what:
                'is named with `${RegExp(r'^(make|take|get)').firstMatch(short)!.group(1)}`: '
                'create (synchronous), open (a device or a session), load (an '
                'asset), decode (bytes), parse (text), or drain for a read that '
                'empties what it reads',
          ));
        }
        final returns = bare.substring(0, bare.indexOf(short)).trim();
        if (RegExp(r'^create([A-Z]|$)').hasMatch(short) &&
            !short.endsWith('Async') &&
            RegExp(r'(^|\s)Future<').hasMatch(returns)) {
          out.add((
            subject: subject,
            what:
                'is an asynchronous `create`: `create` is synchronous, a '
                'device or a session is opened (`open…`), bytes are decoded',
          ));
        }
      }
      if (ending.length > 1) {
        out.add((
          subject: type,
          what:
              'has ${ending.length} teardown verbs (${(ending.toList()..sort()).join(', ')}): '
              'keep `dispose`, or `close` for a connection or a stream',
        ));
      }
    }
  }
  return out;
}

// ------------------------------------------------------------------ units

/// The unit suffixes a public name may not carry: an angle is radians and a
/// time is seconds (docs/CONTRACTS.md), so a name that says otherwise is a
/// name whose number is in the wrong unit.
final RegExp unitSuffix = RegExp(
  r'(?:[a-z0-9](?:Deg|Degrees|Millis|Ms|Msec|Millisecond|Milliseconds)$)'
  r'|^(?:degrees|deg|millis|ms|msec)$',
);

/// Every declared name and parameter in [snapshot] with a unit suffix.
List<NamingProblem> unitSuffixesIn(String snapshot) => <NamingProblem>[
  for (final id in _declaredNamesIn(snapshot).toList()..sort())
    if (unitSuffix.hasMatch(id))
      (
        subject: id,
        what:
            'names a unit the engine does not use: an angle is radians and '
            'a time is seconds (docs/CONTRACTS.md); convert where the number '
            'comes in, and drop the suffix',
      ),
];

/// Names [snapshot] declares: types, members, and every parameter of every
/// signature, without types or default values.
Set<String> _declaredNamesIn(String snapshot) {
  final out = <String>{};
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      out.add(type);
      for (final line in <String>[block.header, ...block.members]) {
        final name = memberName(line);
        out.add(name.contains('.') ? name.split('.').last : name);
        for (final p in parametersOf(line)) {
          out.add(p.name);
        }
      }
    }
  }
  return out..removeWhere((String s) => s.isEmpty);
}

/// One parameter of a signature.
typedef SignatureParameter = ({String name, String type, bool named});

/// The parameters of the signature on [line], or none for a field.
List<SignatureParameter> parametersOf(String line) {
  final bare = splitAnnotations(
    line,
  ).rest.replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
  // The parameter list is the outermost parentheses after the declared
  // name, so a record return type or a `Function(...)` type before it is
  // skipped.
  final name = memberName(line);
  final short = name.contains('.') ? name.split('.').last : name;
  var at = -1;
  for (final m in RegExp(
    '\\b${RegExp.escape(short)}\\s*(<[^()]*>)?\\(',
  ).allMatches(bare)) {
    at = m.end - 1;
  }
  if (at < 0) return const <SignatureParameter>[];
  var depth = 0;
  var end = -1;
  for (var i = at; i < bare.length; i++) {
    final c = bare[i];
    if ('([{<'.contains(c)) depth++;
    if (')]}>'.contains(c) && !(c == '>' && i > 0 && bare[i - 1] == '=')) {
      depth--;
    }
    if (depth == 0) {
      end = i;
      break;
    }
  }
  if (end < 0) return const <SignatureParameter>[];
  final inner = bare.substring(at + 1, end);
  final out = <SignatureParameter>[];
  var named = false;
  depth = 0;
  var current = StringBuffer();
  void flush() {
    var text = current.toString().trim();
    current = StringBuffer();
    if (text.isEmpty) return;
    final assign = text.indexOf(RegExp(r'\s=\s|=(?!=)'));
    if (assign >= 0) text = text.substring(0, assign).trim();
    text = text.replaceFirst(RegExp(r'^(required|covariant|final)\s+'), '');
    final m = RegExp(
      r'^(.*?)(?:this\.|super\.)?([A-Za-z_$][\w$]*)$',
    ).firstMatch(text);
    if (m == null) return;
    out.add((name: m.group(2)!, type: m.group(1)!.trim(), named: named));
  }

  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (depth == 0 && c == '{') {
      flush();
      named = true;
      continue;
    }
    if (depth == 0 && (c == '[' || c == ']' || c == '}')) {
      flush();
      continue;
    }
    if ('(<'.contains(c)) depth++;
    if (')>'.contains(c) && !(c == '>' && i > 0 && inner[i - 1] == '=')) {
      depth--;
    }
    if (depth == 0 && c == ',') {
      flush();
      continue;
    }
    current.write(c);
  }
  flush();
  return out;
}

// --------------------------------------------------------------- booleans

/// The words a boolean getter may start with: it reads as a question, as
/// Effective Dart asks. A third-person verb (`castsShadow`, `affects…`)
/// reads as one too, and is matched by its `s`.
final RegExp booleanPrefix = RegExp(
  r'^(is|has|can|uses|supports|should|does|did|was|were|will|must|needs|'
  r'debug)([A-Z0-9_]|$)',
);

bool _readsAsQuestion(String name) {
  if (booleanPrefix.hasMatch(name)) return true;
  final first = camelWords(name).firstOrNull ?? '';
  return first.length > 2 && first.endsWith('s') && !first.endsWith('ss');
}

/// The state words a mutable `bool` field may not be called bare: one
/// convention for each (`isAlive`, `isPaused`, `isVisible`, `isDisposed`).
const Set<String> boolStateWords = <String>{
  'alive',
  'dead',
  'paused',
  'visible',
  'hidden',
  'disposed',
  'playing',
  'connected',
  'running',
  'finished',
  'busy',
  'active',
};

/// The boolean problems in [snapshot]: a `bool` getter that does not read
/// as a question, a mutable `bool` field named with a bare state word, and
/// a positional `bool` parameter. A settings field stays bare (`enabled`),
/// which is why a `final bool` field is not read here.
List<NamingProblem> booleanProblemsIn(String snapshot) {
  final out = <NamingProblem>[];
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      for (final line in <String>[block.header, ...block.members]) {
        final isHeader = identical(line, block.header);
        final bare = splitAnnotations(
          line,
        ).rest.replaceFirst(RegExp(r'^(abstract|static|external)\s+'), '');
        // A settings type's switches stay bare (`enabled`), as its fields do.
        final settingsLike = RegExp(
          r'(Settings|Theme|Descriptor)$',
        ).hasMatch(type);
        final getter = RegExp(r'^bool\??\s+get\s+([\w$]+)$').firstMatch(bare);
        if (getter != null &&
            !settingsLike &&
            !_readsAsQuestion(getter.group(1)!)) {
          out.add((
            subject: '$type.${getter.group(1)}',
            what:
                'is a `bool` getter that does not read as a question: start it '
                'with is, has, can, uses, supports, did or was',
          ));
        }
        final field = RegExp(
          r'^(?:late\s+)?bool\??\s+([\w$]+)$',
        ).firstMatch(bare);
        if (field != null &&
            !settingsLike &&
            boolStateWords.contains(field.group(1))) {
          out.add((
            subject: '$type.${field.group(1)}',
            what:
                'is a mutable `bool` named with a bare state word: '
                '`is${field.group(1)![0].toUpperCase()}${field.group(1)!.substring(1)}`, '
                'read-only where only the type itself sets it',
          ));
        }
        if (RegExp(r'(^|\s)set\s').hasMatch(bare.split('(').first)) continue;
        if (RegExp(r'Function\s*\(').hasMatch(bare.split('(').first)) continue;
        for (final p in parametersOf(line)) {
          if (p.named) continue;
          if (!RegExp(r'^bool\??$').hasMatch(p.type)) continue;
          final name = memberName(line);
          out.add((
            subject: isHeader ? name : '$type.${name.split('.').last}',
            what:
                'takes `${p.name}` as a positional `bool`: name it, so a call '
                'says what `true` means',
          ));
        }
      }
    }
  }
  return out;
}

// -------------------------------------------------------------- constants

/// Every public constant in [snapshot] named with a `k` prefix.
List<NamingProblem> kConstantsIn(String snapshot) {
  final out = <NamingProblem>[];
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      for (final line in <String>[block.header, ...block.members]) {
        final bare = splitAnnotations(line).rest;
        if (!RegExp(r'^(static\s+)?(const|final)\s').hasMatch(bare)) continue;
        final name = memberName(line);
        if (!RegExp(r'^k[A-Z]').hasMatch(name)) continue;
        out.add((
          subject: identical(line, block.header) ? name : '$type.$name',
          what:
              'is a constant named with `k`: lowerCamelCase, as Effective '
              'Dart asks (`${name[1].toLowerCase()}${name.substring(2)}`)',
        ));
      }
    }
  }
  return out;
}

// --------------------------------------------------------------- settings

/// The suffixes a settings-like type may not use: one suffix, `Settings`,
/// and `Descriptor` only in the HAL.
final RegExp settingsSuffix = RegExp(r'(Options|Config|Tuning|Params|Spec)$');

/// The settings problems in [snapshot] of [package]: a type with another
/// suffix, a `Descriptor` outside the HAL, and a `…Settings` class that is
/// not `final`, has no `const` constructor, or has a `copyWith` that misses
/// a field its constructor sets or a `clear…` flag for a nullable one.
List<NamingProblem> settingsProblemsIn(String snapshot, String package) {
  final out = <NamingProblem>[];
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final bare = splitAnnotations(block.header).rest;
      final isClass = RegExp(
        r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s',
      ).hasMatch(bare);
      final isTypeLike =
          isClass || RegExp(r'^(extension type|typedef|enum)\s').hasMatch(bare);
      if (!isTypeLike) continue;
      if (settingsSuffix.hasMatch(type)) {
        out.add((
          subject: type,
          what:
              'uses the suffix `${settingsSuffix.firstMatch(type)!.group(1)}`: a '
              'settings type is `…Settings` (a HAL type `…Descriptor`)',
        ));
      }
      if (type.endsWith('Descriptor') && package != 'flutter3d_hardware') {
        out.add((
          subject: type,
          what: 'is a `…Descriptor` outside the HAL: call it `…Settings`',
        ));
      }
      if (!isClass || !type.endsWith('Settings')) continue;
      final modifiers = bare.substring(0, bare.indexOf('class ')).trim();
      if (!RegExp(r'\b(final|base|sealed)\b').hasMatch(modifiers)) {
        out.add((
          subject: type,
          what: 'is not `final`: a settings class is a value, not a base',
        ));
      }
      final constructor = block.members.where(
        (String m) =>
            RegExp('^(const\\s+)?$type\\(').hasMatch(splitAnnotations(m).rest),
      );
      if (constructor.isEmpty) continue;
      final ctor = constructor.first;
      if (!splitAnnotations(ctor).rest.startsWith('const ')) {
        out.add((subject: type, what: 'has no `const` constructor'));
      }
      final fieldTypes = <String, String>{
        for (final m in block.members)
          if (RegExp(
                r'^final\s+(.+)\s+([\w$]+)$',
              ).firstMatch(splitAnnotations(m).rest)
              case final f?)
            f.group(2)!: f.group(1)!,
      };
      final sets = <String>[
        for (final p in parametersOf(ctor))
          if (p.named && fieldTypes.containsKey(p.name)) p.name,
      ];
      final copy = block.members.where(
        (String m) => memberName(m) == 'copyWith',
      );
      if (copy.isEmpty) {
        out.add((subject: type, what: 'has no `copyWith`'));
        continue;
      }
      final takes = <String>{for (final p in parametersOf(copy.first)) p.name};
      final missing = <String>[
        for (final f in sets)
          if (!takes.contains(f)) f,
      ];
      if (missing.isNotEmpty) {
        out.add((
          subject: '$type.copyWith',
          what: 'cannot set ${missing.map((String f) => '`$f`').join(', ')}',
        ));
      }
      final unclearable = <String>[
        for (final f in sets)
          if (fieldTypes[f]!.endsWith('?') &&
              !takes.contains('clear${f[0].toUpperCase()}${f.substring(1)}'))
            f,
      ];
      if (unclearable.isNotEmpty) {
        out.add((
          subject: '$type.copyWith',
          what:
              'cannot reset ${unclearable.map((String f) => '`$f`').join(', ')} '
              'to null: a nullable field takes a `clear…` flag '
              '(docs/CONTRACTS.md, "Names")',
        ));
      }
    }
  }
  return out;
}

// ----------------------------------------------------------- units in docs

/// The words that name a unit in a doc comment, or say the number has none.
final RegExp unitWords = RegExp(
  r'\b(metres?|meters?|m/s|m²|m³|kilomet|centimet|millimet|seconds?|'
  r'per second|a second|milliseconds?|microseconds?|radians?|degrees?|°|'
  r'lux|candela|lumens?|EV|kilograms?|kg|newtons?|pascals?|joules?|watts?|'
  // SI symbols a doc writes in its own unit: `Pa`, `Pa·s`, `K`, `1/K`,
  // `J/kg`, `W/(m·K)`, `N/m`, `Ω·m`, rayl.
  r'Pa|K|J|W|N|kelvins?|ohms?|rayls?|'
  r'hertz|Hz|decibels?|dB|pixels?|texels?|frames?|steps?|samples?|bytes?|'
  r'bits?|cells?|tiles?|fraction|ratio|share|factor|multiplier|scale|'
  r'percent|%|nought to one|zero to one|0 to 1|0\.\.1|unitless|'
  r'dimensionless|no unit|weight|count|times|exponent|power|gain|linear|'
  r'sRGB|world units?|units?|NDC|clip space|UV|of the|out of)\b',
  caseSensitive: false,
);

/// The public `double` fields and getters of a library's source whose doc
/// comment names no unit, by name. Item 29: every number a caller passes or
/// reads says what it is measured in.
///
/// Source rather than snapshot, because a snapshot carries no docs. A field
/// with no doc at all counts too: it says nothing about its unit either.
List<String> undocumentedUnitsIn(String source) {
  final out = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(
      r'^  (?:final |late final |late |static const |static final )?'
      r'double\??\s+(?:get\s+)?([a-z][\w$]*)\s*(?:;|=>|=|\{)',
    ).firstMatch(lines[i]);
    if (m == null) continue;
    final doc = StringBuffer();
    for (var j = i - 1; j >= 0; j--) {
      final t = lines[j].trimLeft();
      if (t.startsWith('///')) {
        doc.write(' ${t.substring(3)}');
      } else if (t.startsWith('@') || t.startsWith("'") || t.startsWith(')')) {
        // An annotation, and the lines a long one's arguments wrap onto.
        continue;
      } else {
        break;
      }
    }
    if (!unitWords.hasMatch(doc.toString())) out.add(m.group(1)!);
  }
  return out;
}

// --------------------------------------------------------------- proofs

/// Proves every detector above fires, and stays quiet on what only looks
/// alike — each case a mutation of what the rule keeps.
List<(String, String)> proveNamingDetectorsWork() {
  final broken = <(String, String)>[];
  void fires(String what, bool ok, String on) {
    if (!ok) broken.add((what, 'did not fire on: $on'));
  }

  void quiet(String what, bool ok, String on, String why) {
    if (!ok) broken.add((what, 'fired on $on — $why'));
  }

  const lib = 'library package:p/p.dart\n\n';

  // Spelling.
  final british = britishIdentifiersIn(
    "${lib}final class SkyColour\n  final Vector3 sunColour\n"
    "  void recentreAbove(double centre)\n  static const String s = 'colour'\n"
    '  bool get isCancelled\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'British spelling',
    british.containsAll(<String>{
      'SkyColour',
      'sunColour',
      'recentreAbove',
      'centre',
      'isCancelled',
    }),
    'a type, a field, a method, a parameter and a getter spelled British',
  );
  quiet(
    'British spelling',
    !british.contains('colour') &&
        britishWordIn('EntityRegistry') == null &&
        britishWordIn('materialIssues') == null &&
        britishWordIn('checkerboard') == null,
    "a word in a string, `EntityRegistry`, `materialIssues`, `checkerboard`",
    'a wire word is not an identifier, and a word inside another is not one',
  );

  // Verbs.
  final verbs = verbProblemsIn(
    '${lib}final class Lock\n  Future<void> close()\n  void dispose()\n'
    '  Offset takeDelta()\n  static Future<Lock> create()\n'
    '  Future<Pipe> createPipelineAsync()\n  int get getter\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'verbs',
    verbs.containsAll(<String>{'Lock', 'Lock.takeDelta', 'Lock.create'}),
    'two teardown verbs, a take-prefixed method, an asynchronous create',
  );
  quiet(
    'verbs',
    !verbs.contains('Lock.createPipelineAsync') &&
        !verbs.contains('Lock.getter'),
    'createPipelineAsync, and a getter whose name starts with get',
    'the …Async variant of a synchronous create is the HAL\'s, and a getter is no verb',
  );

  // Units.
  final units = unitSuffixesIn(
    '${lib}final class Cone\n  const Cone({this.halfAngleDegrees = 25.0})\n'
    '  final double sunElevationDeg\n  void observe(int step, double ms)\n'
    '  final double fovY\n  final double reloadSeconds\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'unit suffixes',
    units.containsAll(<String>{'halfAngleDegrees', 'sunElevationDeg', 'ms'}),
    'a parameter in degrees, a field in degrees, a parameter in milliseconds',
  );
  quiet(
    'unit suffixes',
    !units.contains('fovY') && !units.contains('reloadSeconds'),
    '`fovY` and `reloadSeconds`',
    'radians and seconds are the engine\'s units and may be named',
  );

  // Booleans.
  final bools = booleanProblemsIn(
    '${lib}final class Node\n  bool get visible\n  bool get isGrounded\n'
    '  bool get castsShadow\n  bool alive\n  final bool doubleSided\n'
    '  void setDepthWrite(bool enabled)\n  void flag({bool orElse = false})\n'
    '  set visible(bool value)\n'
    '  final bool Function(int) test\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'booleans',
    bools.containsAll(<String>{
      'Node.visible',
      'Node.alive',
      'Node.setDepthWrite',
    }),
    'a bare getter, a bare mutable state field, a positional bool',
  );
  quiet(
    'booleans',
    !bools.contains('Node.isGrounded') &&
        !bools.contains('Node.castsShadow') &&
        !bools.contains('Node.doubleSided') &&
        !bools.contains('Node.flag') &&
        !bools.contains('Node.test') &&
        bools.length == 3,
    'isGrounded, castsShadow, a final settings field, a named bool, a setter',
    'those read as questions, configure, or cannot be named',
  );

  // Constants.
  final ks = kConstantsIn(
    "${lib}const int kF3dVersion = 2\nconst String paletteLight = 'light'\n"
    'final class Lightmap\n  static const double kScale = 8.0\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'k constants',
    ks.contains('kF3dVersion') && ks.contains('Lightmap.kScale'),
    'a top-level and a static k constant',
  );
  quiet(
    'k constants',
    !ks.contains('paletteLight') && ks.length == 2,
    'a lowerCamelCase constant',
    'only the prefix is the problem',
  );

  // Settings.
  final settings = settingsProblemsIn(
    '${lib}final class FogSettings\n'
        '  FogSettings copyWith({double? density})\n'
        '  const FogSettings({this.density = 0.1, this.color, this.near = 1.0})\n'
        '  final LinearColor? color\n  final double density\n  final double near\n\n'
        'class LooseSettings\n  LooseSettings({this.a = 1})\n  final int a\n\n'
        'final class GoodSettings\n'
        '  GoodSettings copyWith({LinearColor? tint, bool clearTint = false})\n'
        '  const GoodSettings({this.tint})\n  final LinearColor? tint\n\n'
        'final class AiTuning\n\nfinal class BufferDescriptor\n',
    'p',
  ).map((NamingProblem p) => '${p.subject}: ${p.what}').toList();
  bool says(String subject, String words) => settings.any(
    (String s) => s.startsWith('$subject:') && s.contains(words),
  );
  fires(
    'settings',
    says('FogSettings.copyWith', '`color`, `near`') &&
        says('LooseSettings', 'not `final`') &&
        says('LooseSettings', 'no `const`') &&
        says('LooseSettings', 'no `copyWith`') &&
        says('AiTuning', 'suffix') &&
        says('BufferDescriptor', 'outside the HAL'),
    'a copyWith missing fields, a loose class, a Tuning, a Descriptor outside the HAL',
  );
  quiet(
    'settings',
    !settings.any((String s) => s.startsWith('GoodSettings')),
    'a final const class whose copyWith clears its nullable field',
    'it is what the rule asks for',
  );

  // Units in docs.
  final undocumented = undocumentedUnitsIn(
    '  /// How far, in metres.\n  final double reach;\n\n'
    '  /// How hard it pulls.\n  final double strength;\n\n'
    '  final double bare;\n\n  /// Seconds between shots.\n'
    '  double get cooldown => 1.0;\n  final double _private;\n',
  );
  fires(
    'units in docs',
    undocumented.contains('strength') && undocumented.contains('bare'),
    'a doc with no unit and no doc at all',
  );
  quiet(
    'units in docs',
    !undocumented.contains('reach') &&
        !undocumented.contains('cooldown') &&
        undocumented.length == 2,
    'metres and seconds named, and a private field',
    'a doc that names its unit is what the rule asks for',
  );
  return broken;
}
