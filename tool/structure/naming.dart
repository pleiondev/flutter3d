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

import 'dart:convert';

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

/// Each British word an MCP snapshot ([mcp], an `api/<package>.mcp`) names
/// as a tool, an argument, a property of an argument's or an answer's
/// schema, or a value an enum argument takes, as `server/tool/word`.
///
/// **A tool's argument is an identifier an agent types**, and the snapshot
/// of the Dart API was the only one this read, so `paint.stroke` took a
/// `colour` while its Dart side took a `color`. An `alias` line is an old
/// name kept so that callers written before keep working, and is not read;
/// a British argument kept beside its American one for the same reason is
/// listed in `britishSpellingAllowed`.
List<NamingProblem> britishSchemaWordsIn(String mcp) {
  final out = <NamingProblem>[];
  var server = '';
  var tool = '';
  void word(String w) {
    if (britishWordIn(w) case final british?) {
      out.add((
        subject: '$server/$tool/$w',
        what:
            'spells `$british` the British way; a tool\'s argument is '
            'spelled `${britishSpellings[british]}`, as the Dart API is. Keep '
            'the old word beside the new one, so callers keep working',
      ));
    }
  }

  void walk(Object? schema) {
    if (schema is Map<String, Object?>) {
      if (schema['properties'] case final Map<String, Object?> properties) {
        for (final MapEntry(:key, :value) in properties.entries) {
          word(key);
          walk(value);
        }
      }
      if (schema['enum'] case final List<Object?> values) {
        for (final value in values.whereType<String>()) {
          word(value);
        }
      }
      walk(schema['items']);
      walk(schema['additionalProperties']);
    }
  }

  for (final line in mcp.split('\n')) {
    if (line.startsWith('server ')) {
      server = line.substring(7).trim();
      tool = '';
    } else if (line.startsWith('tool ')) {
      tool = line.substring(5).trim();
      word(tool.split('.').last);
    } else if (RegExp(r'^  (arg|out) ').firstMatch(line) case final m?) {
      final rest = line.substring(m.end);
      final brace = rest.indexOf('{');
      if (brace < 0) continue;
      if (m.group(1) == 'arg') word(rest.split(' ').first);
      try {
        walk(jsonDecode(rest.substring(brace)));
      } on FormatException {
        continue;
      }
    }
  }
  return out;
}

// ------------------------------------------------------------- collisions

/// The names each library of `tool/structure/sdk_names.txt` exports, by its
/// URI: a `[uri]` line opens a library, then one name a line; `#` starts a
/// comment.
Map<String, Set<String>> sdkNamesFrom(String text) {
  final out = <String, Set<String>>{};
  Set<String>? current;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      current = out[line.substring(1, line.length - 1)] = <String>{};
    } else {
      current?.add(line);
    }
  }
  return out;
}

/// Each type [snapshot] declares under a name one of the [sdk] libraries
/// exports too (A.8): a game that imports both reads an ambiguous name, or
/// silently the other one, and needs a `hide` to say which.
///
/// **Types only**, the declarations a caller names in a signature or a
/// constructor call: a class, an enum, a mixin, an extension type or a
/// typedef. A member is reached through its type, and a top-level function
/// of the same name as Flutter's is rare enough to be read in review.
List<NamingProblem> nameCollisionsIn(
  String snapshot,
  Map<String, Set<String>> sdk,
) {
  final out = <NamingProblem>[];
  final seen = <String>{};
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final bare = splitAnnotations(block.header).rest;
      if (!RegExp(
        r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
        r'(class|enum|mixin|typedef|extension type)\s',
      ).hasMatch(bare)) {
        continue;
      }
      if (!seen.add(type)) continue;
      final where = <String>[
        for (final MapEntry(key: uri, value: names) in sdk.entries)
          if (names.contains(type)) uri,
      ];
      if (where.isEmpty) continue;
      out.add((
        subject: type,
        what:
            'is also a name ${where.map((String u) => '`$u`').join(' and ')} '
            'exports: a program that imports both has to `hide` one. Name '
            'it for what it is in this engine, with a rename migration',
      ));
    }
  }
  return out;
}

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
  final inner = parameterListOf(line);
  if (inner == null) return const <SignatureParameter>[];
  final out = <SignatureParameter>[];
  var named = false;
  var depth = 0;
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

/// Whether the signature on [line] has optional positional parameters
/// (`[…]` at the top of its parameter list).
bool hasOptionalPositional(String line) {
  final inner = parameterListOf(line);
  if (inner == null) return false;
  var depth = 0;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (depth == 0 && c == '[') return true;
    if ('(<{'.contains(c)) depth++;
    if (')>}'.contains(c) && !(c == '>' && i > 0 && inner[i - 1] == '=')) {
      depth--;
    }
  }
  return false;
}

/// The text between the parentheses of the signature on [line], or null
/// for a field.
String? parameterListOf(String line) {
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
  if (at < 0) return null;
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
  if (end < 0) return null;
  return bare.substring(at + 1, end);
}

// ------------------------------------------------- records in contracts

/// The names [snapshot] declares as a record typedef
/// (`typedef Answer = ({bool did, String says});`).
Set<String> recordTypedefsIn(String snapshot) => <String>{
  for (final m in RegExp(
    r'^typedef ([A-Za-z_$][\w$]*)(?:<[^=]*>)? = \(',
    multiLine: true,
  ).allMatches(snapshot))
    m.group(1)!,
};

/// Whether [line], a member of a snapshot, names a record type: an inline
/// one (`({Vector3 normal, double depth})?`, `List<(int, int)>`) or one of
/// [typedefs].
///
/// An inline record is a parenthesis that does not follow a name, so a
/// parameter list (`touch(`) and a function type (`Function(`) are not
/// read as one.
bool namesRecord(String line, Set<String> typedefs) {
  final bare = splitAnnotations(
    line,
  ).rest.replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
  // A default value is the caller's business, not the type's.
  final code = bare.replaceAll(RegExp(r'=\s*[^,)}\]]*'), '');
  for (var i = 0; i < code.length; i++) {
    if (code[i] != '(') continue;
    var j = i - 1;
    while (j >= 0 && code[j] == ' ') {
      j--;
    }
    // `operator [](`, `operator []=(`: an operator's parameter list.
    if (RegExp(r'operator\s*\S+$').hasMatch(code.substring(0, j + 1))) {
      continue;
    }
    if (j >= 0 && RegExp(r'[\w$>?]').hasMatch(code[j])) {
      // A keyword before it (`abstract (int, int) get pair`) is no name.
      final word = RegExp(r'([\w$]+)\s*$').firstMatch(code.substring(0, i));
      if (!_recordKeywords.contains(word?.group(1))) continue;
    }
    return true;
  }
  for (final name in typedefs) {
    if (RegExp(
      '(?<![\\w\$.])${RegExp.escape(name)}(?![\\w\$])',
    ).hasMatch(code)) {
      return true;
    }
  }
  return false;
}

/// Words a record type can follow in a declaration.
const Set<String> _recordKeywords = <String>{
  'abstract',
  'static',
  'final',
  'const',
  'external',
  'covariant',
  'required',
  'late',
  'factory',
};

/// The members of the types an outside author implements or extends in
/// [snapshot] that name a record, as `Type.member` (A.1, A.5).
///
/// **A record cannot gain a field.** A result that grows — an answer that
/// later wants a picture, a hit that later wants a material — has to be a
/// class with named, defaulted fields; a record in an abstract member's
/// signature freezes what every implementation returns or takes for the
/// life of the major. The types read are the ones a minor's new member
/// would reach: `abstract base`, `base mixin`, `interface` and plain
/// `abstract` classes.
List<NamingProblem> recordsInContractsIn(
  String snapshot,
  Set<String> typedefs,
) {
  final out = <NamingProblem>[];
  final seen = <String>{};
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final header = splitAnnotations(block.header).rest;
      if (!RegExp(
        r'^(abstract base (mixin )?class|base mixin|abstract interface class|'
        r'interface class|abstract class|abstract mixin class) ',
      ).hasMatch(header)) {
        continue;
      }
      for (final line in block.members) {
        if (!namesRecord(line, typedefs)) continue;
        final name = memberName(line);
        final short = name.contains('.') ? name.split('.').last : name;
        final subject = '$type.$short';
        if (!seen.add(subject)) continue;
        out.add((
          subject: subject,
          what:
              'is a member of a type an outside author implements, and '
              'names a record: a record never gains a field, so what it '
              'carries is frozen for every implementation. Make it a final '
              'class with named fields (a recordToClass migration), or say '
              'in `recordInContractAllowed` why it never grows',
        ));
      }
    }
  }
  return out;
}

// ---------------------------------------------------- growing constructors

/// Each constructor in [snapshot] that takes optional positional
/// parameters (`Type(a, [b])`), as `Type.Type` or `Type.named` (E.5).
///
/// **A positional list cannot grow by name.** A minor that wants one more
/// argument after `[b]` can only add a third position, which a caller then
/// passes by counting, and an optional positional and a named parameter
/// cannot sit in one list: the constructor is frozen at the shape it has.
/// A named parameter is added with a default and breaks nobody.
List<NamingProblem> optionalPositionalConstructorsIn(String snapshot) {
  final out = <NamingProblem>[];
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      for (final line in block.members) {
        final bare = splitAnnotations(line).rest;
        final m = RegExp(
          '^(?:const\\s+)?(?:factory\\s+)?${RegExp.escape(type)}'
          r'(?:\.([A-Za-z_$][\w$]*))?\(',
        ).firstMatch(bare);
        if (m == null || !hasOptionalPositional(line)) continue;
        out.add((
          subject: '$type.${m.group(1) ?? type}',
          what:
              'takes optional positional parameters, which a minor can never '
              'add a named one beside: make them named, with a parameters '
              'migration',
        ));
      }
    }
  }
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

  // Spelling in a tool's schema.
  final schema = britishSchemaWordsIn(
    'server s\n  alias paintColour -> paint.color\n\ntool paint.recolour\n'
    '  says Paint a colour.\n'
    '  arg colour required {"type":"array"}\n'
    '  arg samples {"items":{"properties":{"centre":{"type":"array"}},'
    '"type":"object"},"type":"array"}\n'
    '  arg to {"enum":["boundsCentre","worldOrigin"],"type":"string"}\n'
    '  arg color {"type":"array"}\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'British spelling in a tool schema',
    schema.containsAll(<String>{
      's/paint.recolour/recolour',
      's/paint.recolour/colour',
      's/paint.recolour/centre',
      's/paint.recolour/boundsCentre',
    }),
    'a tool, an argument, a nested property and an enum value spelled British',
  );
  quiet(
    'British spelling in a tool schema',
    schema.length == 4,
    'an alias, a description, `color` and `worldOrigin`',
    'an alias keeps an old name on purpose, and a sentence is not a name',
  );

  // Collisions with the SDK.
  final sdk = sdkNamesFrom(
    '# names\n[package:flutter/material.dart]\nKey\nMaterialType\n\n'
    '[dart:core]\nMatch\n',
  );
  final collisions = nameCollisionsIn(
    '${lib}final class Key\n  final double time\n\n'
    'typedef MaterialType = ExpressionType;\n\n'
    'final class Keyframe\n  final Key key\n\nabstract final class Match\n',
    sdk,
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'name collisions',
    collisions.containsAll(<String>{'Key', 'MaterialType', 'Match'}),
    'a class, a typedef and an abstract class named as Flutter and Dart '
        'name theirs',
  );
  quiet(
    'name collisions',
    collisions.length == 3,
    '`Keyframe`, and a member whose type is `Key`',
    'only a declared type is a name a caller imports',
  );

  // Records in what an outside author implements.
  const recordApi =
      '${lib}typedef Answer = ({bool did, String says});\n\n'
      'abstract base class Sink\n'
      '  abstract Future<Answer> deliver(Upload upload)\n'
      '  abstract ({Vector3 normal, double depth})? touch(Vector3 at)\n'
      '  void take(List<(int, int)> pairs)\n'
      '  abstract double operator [](int index)\n'
      '  void Function(int) get onStep\n'
      '  Answer2 other(int x)\n\n'
      'final class Plain\n  Answer answer()\n';
  final records = recordsInContractsIn(
    recordApi,
    recordTypedefsIn(recordApi),
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'records in contracts',
    records.containsAll(<String>{'Sink.deliver', 'Sink.touch', 'Sink.take'}),
    'a record typedef, an inline record after `abstract`, a record in a '
        'type argument',
  );
  quiet(
    'records in contracts',
    records.length == 3,
    'an operator, a function type, a name that only starts like a typedef, '
        'a final class',
    'a parameter list is not a record, and a final class is nobody\'s to '
        'implement',
  );

  // Constructors that cannot grow.
  final positional = optionalPositionalConstructorsIn(
    '${lib}final class ToolName\n'
    '  const ToolName(this.name, [this.hints = const <String>{}])\n'
    '  factory ToolName.parse(String text, [int at = 0])\n'
    '  void rename(String to, [bool loud = false])\n\n'
    'final class Pair\n  const Pair(this.a, this.b, {this.c = const [1]})\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'optional positional constructors',
    positional.containsAll(<String>{'ToolName.ToolName', 'ToolName.parse'}),
    'a constructor and a factory with an optional positional list',
  );
  quiet(
    'optional positional constructors',
    positional.length == 2,
    'a method, and a list literal inside a named default',
    'only a constructor is frozen by its positions here',
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
