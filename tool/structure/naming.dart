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

/// The libraries of `sdk_names.txt` the collision rule does not read: a
/// game does not import them beside ours, so a name they share costs no
/// `hide`. The rule `a signature names only types a caller can import`
/// reads them, because a type from any of them is importable.
const Set<String> sdkLibrariesKnownOnly = <String>{
  'dart:isolate',
  'dart:ffi',
  'dart:developer',
  'dart:js_interop',
  'dart:collection',
  'dart:convert',
  'package:meta/meta.dart',
};

/// The names of [allowed] that a `package:flutter/` library or `dart:core`
/// in [sdk] exports: collisions the allowlist may not keep (A.8).
///
/// **A widget file imports Flutter beside the facade**, so a name
/// `widgets.dart`, `material.dart` or a library they are built from exports
/// is one that file reads as ambiguous, or silently as Flutter's. Only a
/// collision with a library a game imports to reach under Flutter
/// (`dart:ui`, `dart:io`) may be kept with a reason; `RenderView` and
/// `LicenseEntry` were kept against `rendering` and `foundation` until "a
/// game is seen importing both", which nothing could see.
List<String> flutterCollisionsAllowedIn(
  Iterable<String> allowed,
  Map<String, Set<String>> sdk,
) => <String>[
  for (final name in allowed)
    if (sdk.entries.any(
      (MapEntry<String, Set<String>> library) =>
          (library.key.startsWith('package:flutter/') ||
              library.key == 'dart:core') &&
          library.value.contains(name),
    ))
      name,
];

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
///
/// **`release` among them, as a synchronous `void release()` with nothing
/// to release but the object itself** — what a node holding GPU buffers
/// was given before it became `dispose`. A `release(texture)` hands back
/// something else, and a `Future<void> release()` lets go of a hold (a
/// pointer lock), and neither is counted.
const Set<String> teardownVerbs = <String>{
  'dispose',
  'close',
  'shutdown',
  'destroy',
  'teardown',
  'tearDown',
  'release',
};

/// Whether [line], a member named [short], ends its object's life by the
/// reading of [teardownVerbs]: every one of them does, and `release` only
/// as a synchronous method with no parameter.
bool _endsLife(String line, String short) {
  if (!teardownVerbs.contains(short)) return false;
  if (short != 'release') return true;
  final bare = splitAnnotations(line).rest;
  return RegExp(r'^(?:abstract\s+)?void\s+release\(\)\s*$').hasMatch(bare);
}

/// The two of [teardownVerbs] a type may keep.
const Set<String> standardTeardownVerbs = <String>{'dispose', 'close'};

/// The type-level problems with verbs in [snapshot]: a type with two
/// teardown verbs, or one that is not [standardTeardownVerbs] (a lone
/// `shutdown` was never flagged), a method named with `make`, `take` or
/// `get`, an asynchronous `create` (one that returns a `Future` and is not
/// the `…Async` variant of a synchronous one), and a synchronous `open`.
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
        if (!isHeader && _endsLife(line, short)) ending.add(short);
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
        if (RegExp(r'^open([A-Z]|$)').hasMatch(short) &&
            parameterListOf(line) != null &&
            !RegExp(r'(^|\W)(Future|FutureOr|Stream)<').hasMatch(returns)) {
          out.add((
            subject: subject,
            what:
                'is a synchronous `open`: a device, a session or a file is '
                'opened, which waits; what is made at once is `create`d, and '
                'a permissive variant says so in its name',
          ));
        }
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
      if (ending.length == 1 && !standardTeardownVerbs.contains(ending.first)) {
        out.add((
          subject: '$type.${ending.first}',
          what:
              'ends the object\'s life with `${ending.first}`: the verb is '
              '`dispose`, or `close` for a connection or a stream',
        ));
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

// ------------------------------------------------------- registrations

/// The public members and functions in [snapshot] that answer a
/// `Registration` asynchronously: `Future<Registration>`,
/// `FutureOr<Registration>`, or either nullable.
///
/// **A registration is synchronous.** A plugin's `install` is, and a
/// registration it cannot await raced the plugin being switched off, lost
/// its errors to nobody, and left a node in a frame whose plugin was gone.
/// What loads behind a registration is the registration's to follow: the
/// node is in the frame at once and pending until its load is done.
List<NamingProblem> asyncRegistrationsIn(String snapshot) {
  final returnsLater = RegExp(r'(^|[\s(])(Future|FutureOr)<Registration\??>\s');
  final out = <NamingProblem>[];
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      for (final line in <String>[block.header, ...block.members]) {
        final isHeader = identical(line, block.header);
        final bare = splitAnnotations(line).rest;
        if (!bare.contains('(')) continue;
        if (isHeader &&
            RegExp(
              r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
              r'(class|enum|mixin|extension|typedef)\b',
            ).hasMatch(bare)) {
          continue;
        }
        final name = memberName(line);
        final short = name.contains('.') ? name.split('.').last : name;
        final at = bare.indexOf('$short(');
        if (at < 0) continue;
        if (!returnsLater.hasMatch('${bare.substring(0, at)} ')) continue;
        out.add((
          subject: isHeader ? short : '$type.$short',
          what:
              'answers its `Registration` later: a registration returns at '
              'once, and what it loads is followed by the registry — the '
              'thing registered stays pending until the load is done',
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
///
/// **Microseconds too.** A frame-time budget a caller sets is a `Duration`;
/// four budgets had become `int` microseconds while the rule read only
/// milliseconds. A measurement the engine reports may stay integral
/// microseconds (a pass's GPU time), and is listed in `unitSuffixAllowed`.
final RegExp unitSuffix = RegExp(
  r'(?:[a-z0-9](?:Deg|Degrees|Millis|Ms|Msec|Millisecond|Milliseconds|Micros|'
  r'Microseconds)$)'
  r'|^(?:degrees|deg|millis|ms|msec|micros|microseconds)$',
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

/// Each record a public result carries in [snapshot]: a record typedef, and
/// a field, getter, method or function of any public type whose type or
/// return type is an inline record, as `Name` or `Type.member` (A.1, S11).
///
/// **A result grows too.** A hit that later wants a material, a seat that
/// later wants a region, a start that later wants a warning: each is a
/// record nobody can add a field to, wherever it is returned. The rule for
/// implementable types ([recordsInContractsIn]) read only what an outside
/// author writes; this reads what every caller reads. A parameter's record
/// is the caller's to build and is not read here. The maths tuples that
/// have as many parts as their space are listed in `recordInResultAllowed`.
List<NamingProblem> recordsInResultsIn(String snapshot) {
  final out = <NamingProblem>[];
  final seen = <String>{};
  void add(String subject) {
    if (!seen.add(subject)) return;
    out.add((
      subject: subject,
      what:
          'is a record in what a caller reads: a record never gains a field, '
          'so the result is frozen at the shape it has. Make it a final '
          'class with named fields (a recordToClass migration), or say in '
          '`recordInResultAllowed` why it never grows',
    ));
  }

  bool returnsRecord(String line) {
    final bare = splitAnnotations(
      line,
    ).rest.replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
    final name = memberName(line);
    final short = name.contains('.') ? name.split('.').last : name;
    final at = RegExp(
      '(?:^|[\\s>?)])(?:get\\s+|set\\s+)?${RegExp.escape(short)}'
      r'(?:\s*<[^()]*>)?\s*(?:\(|=|$)',
    ).firstMatch(bare);
    if (at == null) return false;
    final type = bare.substring(0, at.start + 1).trim();
    return type.isNotEmpty && namesRecord(type, const <String>{});
  }

  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final header = splitAnnotations(block.header).rest;
      if (RegExp(r'^typedef [\w$]+(?:<[^=]*>)? = \(').hasMatch(header)) {
        add(type);
        continue;
      }
      if (RegExp(
        r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
        r'(class|enum|mixin|extension|extension type)\s',
      ).hasMatch(header)) {
        for (final line in block.members) {
          if (RegExp(r'^\s*set\s').hasMatch(splitAnnotations(line).rest)) {
            continue;
          }
          if (returnsRecord(line)) {
            final name = memberName(line);
            add('$type.${name.contains('.') ? name.split('.').last : name}');
          }
        }
      } else if (!header.startsWith('typedef ') && returnsRecord(header)) {
        add(type);
      }
    }
  }
  return out;
}

/// Each public plain `class` in [snapshot] (S5, decision 3): one with no
/// `final`, `base`, `sealed` or `interface`.
///
/// **A plain class is an interface by accident.** Code outside may
/// `implements` it, so under the classifier a member it gains in a minor is
/// a break, and a new option on a widget is a major release. A class says
/// what it is for: `final` where nobody outside should extend it (a widget,
/// a value), `base` where an outside author extends it (a Flame component a
/// game subclasses). The interface rule read only `interface class`.
List<NamingProblem> plainClassesIn(String snapshot) {
  final out = <NamingProblem>[];
  final seen = <String>{};
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final bare = splitAnnotations(block.header).rest;
      if (!RegExp(r'^(?:abstract\s+)?class\s').hasMatch(bare)) continue;
      if (!seen.add(type)) continue;
      out.add((
        subject: type,
        what:
            'is a plain class, which code outside may implement, so no member '
            'can be added in a minor: make it `final` (nobody outside extends '
            'it) or `base` (an outside author extends it), with a '
            'subclassModifier migration',
      ));
    }
  }
  return out;
}

/// Each open set in [snapshot] that lacks the shape `DeviceFeature` has: a
/// `final class` with `static const` members of its own type must also
/// carry `values` and `byName` (CONTRIBUTING, "The API is a snapshot").
///
/// **One shape, so a tool reads every set the same way.** A set that names
/// its lookup `named`, `fromWireName` or nothing at all makes every writer
/// of a settings file or a tool argument learn it set by set.
List<NamingProblem> openSetShapeIn(String snapshot) {
  final out = <NamingProblem>[];
  final seen = <String>{};
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final bare = splitAnnotations(block.header).rest;
      if (!RegExp(r'^final\s+class\s').hasMatch(bare)) continue;
      final constants = block.members.where(
        (String m) => RegExp(
          '^static\\s+const\\s+${RegExp.escape(type)}\\s',
        ).hasMatch(splitAnnotations(m).rest),
      );
      if (constants.length < 2) continue;
      final names = <String>{for (final m in block.members) memberName(m)};
      final missing = <String>[
        if (!names.contains('values')) '`values`',
        if (!names.contains('byName')) '`byName`',
      ];
      if (missing.isEmpty || !seen.add(type)) continue;
      out.add((
        subject: type,
        what:
            'is an open set with no ${missing.join(' and ')}: a set of '
            'constants carries `values`, `name` and `byName`, as '
            '`DeviceFeature` does',
      ));
    }
  }
  return out;
}

// ------------------------------------------------------- what a type names

/// The capitalized identifiers the declaration or member on [line] names as
/// types: its return type, its parameters' types, its supertypes and type
/// bounds, and the type of a constant a default value reads. Not its
/// annotations, its string literals, the rest of a default value or a
/// constant's value, which a caller never has to write.
Set<String> typesNamedIn(String line) {
  var bare = splitAnnotations(
    line,
  ).rest.replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
  if (bare.startsWith('values:')) return <String>{};
  // A constant's value, and a top-level `=` of a typedef kept.
  if (!bare.startsWith('typedef ')) {
    final assign = RegExp(r'^[^(]*?[\w$>?)\]]\s+[\w$]+\s*=\s').firstMatch(bare);
    if (assign != null) bare = bare.substring(0, assign.end - 2);
  }
  // Default values inside a parameter list. A typedef's `=` is its body,
  // a function type, which can hold none: everything after it is a type
  // a caller writes. Of a default, only the type of a constant it reads
  // (`mask = CollisionLayers.world`) stays: that is the vocabulary a caller
  // writes to pass anything else.
  if (!bare.startsWith('typedef ')) {
    bare = bare.replaceAllMapped(
      RegExp(r'\s=\s*(?:const\s+)?[^,)}\]]*(?:\([^)]*\))?'),
      (Match m) => <String>[
        for (final c in RegExp(
          r'(?<![\w$.])([A-Z][\w$]*)\.[a-z_$]',
        ).allMatches(m.group(0)!))
          ' ${c.group(1)}',
      ].join(),
    );
  }
  return <String>{
    for (final m in RegExp(
      r'(?<![\w$])(?:[a-z_$][\w$]*\.)?([A-Z][\w$]*)',
    ).allMatches(bare))
      m.group(1)!,
  };
}

/// The type parameters [line] declares (`<T extends Object, E>`), which name
/// no type of anybody's: the list after the name a header declares
/// (`class Box<T>`, `typedef Handler<T> =`), and after a method's or a
/// generic function type's name (`read<E>(`, `Function<T>(`).
///
/// **Only those.** A generic argument (`Stream<ContactEvent>`, `List<E>`)
/// names a type, and reading every `<Name>` as a declaration hid the types
/// a facade's members name only as arguments.
Set<String> typeParametersIn(String line) {
  final text = splitAnnotations(line).rest;
  final out = <String>{};
  void declared(int open) {
    var depth = 0;
    var start = open + 1;
    final parts = <String>[];
    for (var i = open; i < text.length; i++) {
      final c = text[i];
      if (c == '<') depth++;
      if (c == '>') depth--;
      if (depth == 1 && c == ',') {
        parts.add(text.substring(start, i));
        start = i + 1;
      }
      if (depth == 0) {
        parts.add(text.substring(start, i));
        break;
      }
    }
    for (final part in parts) {
      final name = RegExp(r'^\s*([A-Z][\w$]*)').firstMatch(part)?.group(1);
      if (name != null) out.add(name);
    }
  }

  // The header's own: the first `<` after the name a declaration keyword
  // introduces.
  final header = RegExp(
    r'^(?:[a-z]+\s+)*?(?:class|mixin|typedef|enum|type|extension)\s+[\w$]+<',
  ).firstMatch(text);
  if (header != null) declared(header.end - 1);
  // A method's or a function type's own: a name, its list, then `(`.
  for (final m in RegExp(r'[\w$]+<').allMatches(text)) {
    final open = m.end - 1;
    var depth = 0;
    var close = -1;
    for (var i = open; i < text.length; i++) {
      if (text[i] == '<') depth++;
      if (text[i] == '>') depth--;
      if (depth == 0) {
        close = i;
        break;
      }
    }
    if (close > 0 && text.substring(close + 1).startsWith('(')) {
      declared(open);
    }
  }
  return out;
}

/// The names the main library of the facade [facade] lets a caller write,
/// read off its snapshot: its own declarations and every name its
/// re-exports admit.
Set<String> facadeNames(String snapshot, String facade) {
  final library = parseApi(snapshot)['package:$facade/$facade.dart'];
  if (library == null) return <String>{};
  return <String>{
    ...library.declarations.keys,
    for (final export in library.exports.values)
      for (final m in export.members)
        if (!m.startsWith('export ')) m.split(' ').first,
  };
}

/// The types of ours the API reachable through [facade] names and the
/// facade does not export (S1): from its own declarations and every type it
/// re-exports, through each signature, to the next type, until nothing new
/// is reached.
///
/// [declarations] is every published package's type declarations by name
/// (a name declared in two packages keeps both blocks). A subject is the
/// missing type; `what` names the first signature found to name it.
///
/// **A type nobody can name is a dependency nobody declared.** A facade
/// whose `add*` returns a `Registration` it does not export sends its user
/// to the package underneath, and that import becomes part of what they
/// wrote against the release.
///
/// [extensions], when given, are the extensions the facade could export: the
/// ones the libraries it re-exports from declare. An extension elsewhere (a
/// package the facade does not stand on) is that package's to export.
List<NamingProblem> facadeGapsIn({
  required String facade,
  required Set<String> exported,
  required Map<String, List<ApiBlock>> declarations,
  Set<String>? extensions,
  Map<String, Set<String>>? homes,
}) {
  final out = <NamingProblem>[];
  final reached = <String>{...exported};
  final queue = <String>[...exported];
  final reported = <String>{};
  final subtypes = subtypesIn(declarations);
  bool home(String a, String b) =>
      homes == null ||
      (homes[a] ?? const <String>{}).any(
        (String p) => homes[b]?.contains(p) ?? false,
      );
  while (queue.isNotEmpty) {
    final type = queue.removeLast();
    // Downward, from a type the facade exports: the variants of a sealed
    // base and the stock implementations its package gives a base are what
    // fills it, and a caller writes them (`SaveFound`, `SteadyLight`).
    if (exported.contains(type)) {
      for (final sub in subtypes[type] ?? const <String>[]) {
        if (!home(sub, type)) continue;
        if (!exported.contains(sub) && reported.add(sub)) {
          out.add((
            subject: sub,
            what:
                'is a subtype of `$type`, which `package:$facade` exports, '
                'declared in its package, and `package:$facade` does not '
                'export it: export it (or give `$type` a factory for it), or '
                'say in `facadeGapAllowed` why a caller never writes it',
          ));
        }
        if (reached.add(sub)) queue.add(sub);
      }
    }
    for (final block in declarations[type] ?? const <ApiBlock>[]) {
      final generics = typeParametersIn(block.header);
      for (final line in <String>[block.header, ...block.members]) {
        final own = <String>{...generics, ...typeParametersIn(line)};
        for (final named in typesNamedIn(line)) {
          if (own.contains(named) || !declarations.containsKey(named)) {
            continue;
          }
          if (!exported.contains(named) && reported.add(named)) {
            final member = identical(line, block.header)
                ? type
                : '$type.${memberName(line).split('.').last}';
            out.add((
              subject: named,
              what:
                  'is named by `$member`, which `package:$facade` exports, '
                  'and `package:$facade` does not export it: export it, or '
                  'say in `facadeGapAllowed` why a caller never writes it',
            ));
          }
          if (reached.add(named)) queue.add(named);
        }
      }
    }
  }
  // An extension on a type the facade exports is part of that type's API
  // to a caller, who calls its members as the type's own: without it the
  // members are not there at all.
  for (final MapEntry(key: name, value: blocks) in declarations.entries) {
    for (final block in blocks) {
      final on = RegExp(
        r'^extension\s+[\w$]+(?:<[^>]*>)?\s+on\s+([A-Z][\w$]*)',
      ).firstMatch(block.header)?.group(1);
      if (on == null || !exported.contains(on)) continue;
      if (extensions != null && !extensions.contains(name)) continue;
      if (exported.contains(name) || !reported.add(name)) continue;
      out.add((
        subject: name,
        what:
            'extends `$on`, which `package:$facade` exports, and '
            '`package:$facade` does not export it, so its members are '
            'missing from the type there: export it, or say in '
            '`facadeGapAllowed` why a caller never calls them',
      ));
    }
  }
  return out;
}

/// Each name the main library of a package in [underneath] lets a caller
/// write that the facade [facade] re-exports it with a `show` list leaving
/// that name out (S2): a public name of the library underneath that is not
/// the facade's.
///
/// [facadeSnapshot] is the facade's snapshot; [underneath] maps a package to
/// its snapshot. A library the facade does not re-export from, or
/// re-exports whole, has nothing to leave out.
///
/// **A name added underneath lands outside the facade unseen.**
/// `lowerMaterialCompute` was added to the core with the guide naming it
/// beside `parseMaterial`, and the facade's hand-kept list took the one and
/// not the other: nothing asked, and the closure cannot see a name that no
/// exported signature names.
List<NamingProblem> facadeLeftOutIn({
  required String facade,
  required String facadeSnapshot,
  required Map<String, String> underneath,
}) {
  final library = parseApi(facadeSnapshot)['package:$facade/$facade.dart'];
  if (library == null) return const <NamingProblem>[];
  // A name the library underneath re-exports from further down may reach
  // the facade through that package's own list.
  final admitted = facadeNames(facadeSnapshot, facade);
  final out = <NamingProblem>[];
  for (final MapEntry(key: package, value: snapshot) in underneath.entries) {
    final uri = 'package:$package/$package.dart';
    final export = library.exports[uri];
    if (export == null || !export.header.contains(' show ')) continue;
    for (final name in facadeNames(snapshot, package).toList()..sort()) {
      if (admitted.contains(name)) continue;
      out.add((
        subject: name,
        what:
            'is public in `$uri`, which `package:$facade` re-exports with a '
            '`show` list that leaves it out: add it to the list, or say in '
            '`facadeLeavesOut` why a caller of the facade never writes it',
      ));
    }
  }
  return out;
}

/// The direct subtypes of each type in [declarations], by the supertype's
/// name: every type whose header names it after `extends`, `implements` or
/// `with`.
Map<String, List<String>> subtypesIn(Map<String, List<ApiBlock>> declarations) {
  final out = <String, List<String>>{};
  for (final MapEntry(key: name, value: blocks) in declarations.entries) {
    for (final block in blocks) {
      final header = splitAnnotations(block.header).rest;
      final clause = RegExp(
        r'\s(?:extends|implements|with)\s+(.*)$',
      ).firstMatch(header);
      if (clause == null) continue;
      // A type argument (`extends Base<Kind>`) names no supertype.
      var supers = clause.group(1)!;
      while (supers.contains('<')) {
        supers = supers.replaceAll(RegExp(r'<[^<>]*>'), '');
      }
      for (final m in RegExp(r'(?<![\w$.])([A-Z][\w$]*)').allMatches(supers)) {
        final list = out[m.group(1)!] ??= <String>[];
        if (!list.contains(name)) list.add(name);
      }
    }
  }
  return out;
}

/// The packages whose main library declares each type, read off
/// [snapshots] by package.
///
/// **The main library only.** A package's other libraries are entry points
/// of their own for a reader of their own (`testing.dart`'s fakes,
/// `trace.dart`'s recording device), and a facade over the main library
/// does not owe them.
Map<String, Set<String>> typeHomesIn(Map<String, String> snapshots) {
  final homes = <String, Set<String>>{};
  for (final MapEntry(key: package, value: snapshot) in snapshots.entries) {
    for (final library in parseApi(snapshot).values) {
      if (library.uri != 'package:$package/$package.dart') continue;
      for (final name in library.declarations.keys) {
        (homes[name] ??= <String>{}).add(package);
      }
    }
  }
  return homes;
}

/// Every type a snapshot declares, by name: a class, an enum, a mixin, an
/// extension type, a typedef or a named extension, in every library it is
/// listed in.
Map<String, List<ApiBlock>> typeDeclarationsIn(Iterable<String> snapshots) {
  final out = <String, List<ApiBlock>>{};
  for (final snapshot in snapshots) {
    for (final library in parseApi(snapshot).values) {
      for (final MapEntry(key: name, value: block)
          in library.declarations.entries) {
        final bare = splitAnnotations(block.header).rest;
        if (!RegExp(
          r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
          r'(class|enum|mixin|typedef|extension type|extension)\s',
        ).hasMatch(bare)) {
          continue;
        }
        final blocks = out[name] ??= <ApiBlock>[];
        if (!blocks.any((ApiBlock b) => b.header == block.header)) {
          blocks.add(block);
        }
      }
    }
  }
  return out;
}

/// Each type [snapshot]'s signatures name that no published snapshot
/// declares and no library of [sdk] exports (A.5, S1, S13): a third-party
/// type in the contract, or one of the package's own types that no library
/// exports, so nobody can name it. [known] is every type the published
/// snapshots declare.
List<NamingProblem> unimportableTypesIn(
  String snapshot,
  Set<String> known,
  Map<String, Set<String>> sdk,
) {
  final everywhere = <String>{
    // The language's own, which no library declares.
    'Never',
    for (final names in sdk.values) ...names,
  };
  final out = <NamingProblem>[];
  final seen = <String>{};
  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final generics = typeParametersIn(block.header);
      for (final line in <String>[block.header, ...block.members]) {
        final own = <String>{...generics, ...typeParametersIn(line)};
        for (final named in typesNamedIn(line)) {
          if (own.contains(named) ||
              known.contains(named) ||
              everywhere.contains(named) ||
              !seen.add(named)) {
            continue;
          }
          final member = identical(line, block.header)
              ? type
              : '$type.${memberName(line).split('.').last}';
          out.add((
            subject: named,
            what:
                'is named by `$member` and is neither ours to import nor the '
                'SDK\'s: a third-party type makes its major ours (wrap it, or '
                'list it in `thirdPartyTypeAllowed` with why it belongs in the '
                'contract), and a type of ours no library exports cannot be '
                'named at all (export it)',
          ));
        }
      }
    }
  }
  return out;
}

/// The types [source] throws by name (`throw FooException(…)`,
/// `throw const Foo.named(…)`, `Error.throwWithStackTrace(Foo(…), trace)`),
/// public ones only: a private type is caught by nobody outside, which is
/// its own decision.
///
/// **A thrown type is API whether or not a library exports it.** A caller
/// catches it by name (E.6), and `GpuDeviceException` was thrown, named as
/// the target of a rename, and exported by nobody.
Set<String> thrownTypesIn(String source) => <String>{
  for (final m in RegExp(
    r'(?:\bthrow\s+|\bError\.throwWithStackTrace\(\s*)'
    r'(?:const\s+)?(?:[a-z_]\w*\.)?([A-Z][\w$]*)\s*[(.<]',
  ).allMatches(source.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')))
    m.group(1)!,
};

// -------------------------------------------------------- null as an error

/// The verbs that read or make something, whose failure is an error and
/// not an absence (E.7): a reader of a document, bytes or text, a loader,
/// an upload.
final RegExp readingVerb = RegExp(
  r'^(fromJson|from[A-Z]\w*|decode\w*|parse\w*|read\w*|load\w*|upload\w*)$',
);

/// Each static or top-level reader in [snapshot] that answers null, as
/// `Type.member` or `function` (E.7).
///
/// **Null cannot say why.** A reader that answers null for a malformed
/// document leaves its caller with "something went wrong" and nothing to
/// show a person, and a caller that forgot the check reads on with a null
/// it did not expect. One that throws the package's typed exception says
/// which field and where. A reader whose null means "not there" (an
/// absent key, a kind a newer build wrote that this one skips) says so in
/// its doc and in `nullAsErrorAllowed`; `try…` names are the Dart idiom for
/// that and are not read.
List<NamingProblem> nullAsErrorIn(String snapshot) {
  final out = <NamingProblem>[];
  final seen = <String>{};
  void check(String line, String? type) {
    final bare = splitAnnotations(line).rest;
    final m = RegExp(
      r'^(?:static\s+)?(?:Future<|FutureOr<)?([\w$<>, ?]+?\?)>?\s+'
      r'([A-Za-z_$][\w$]*)(?:<[^(]*>)?\(',
    ).firstMatch(bare);
    if (m == null) return;
    if (type != null && !bare.startsWith('static ')) return;
    final name = m.group(2)!;
    if (!readingVerb.hasMatch(name)) return;
    final subject = type == null ? name : '$type.$name';
    if (!seen.add(subject)) return;
    out.add((
      subject: subject,
      what:
          'reads or makes something and answers null when it cannot, which '
          'says nothing about why: throw the package\'s typed exception '
          '(a `nullToThrow` migration), or, where null means absent, say so '
          'in its doc and in `nullAsErrorAllowed`',
    ));
  }

  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final header = splitAnnotations(block.header).rest;
      if (RegExp(
        r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
        r'(class|enum|mixin|extension|extension type)\s',
      ).hasMatch(header)) {
        for (final member in block.members) {
          check(member, type);
        }
      } else {
        check(block.header, null);
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
///
/// **Methods and functions too.** A method's positional list freezes the same
/// way (`play([int? index])` beside `playLayer(int, {wrap, speed, …})`), and
/// the first version of this rule read constructors only. The one idiom a
/// method keeps is the output parameter of the vector maths it wraps
/// (`readPosition([Vector3? out])`): a list whose every optional parameter is
/// one of [outputParameterNames] is not read.
List<NamingProblem> optionalPositionalsIn(String snapshot) {
  final out = <NamingProblem>[];
  final seen = <String>{};
  void check(String line, String? type, bool isHeader) {
    if (!hasOptionalPositional(line)) return;
    final bare = splitAnnotations(line).rest;
    final optional = optionalPositionalNamesOf(line);
    if (optional.isNotEmpty && optional.every(outputParameterNames.contains)) {
      return;
    }
    final name = memberName(line);
    final short = name.contains('.') ? name.split('.').last : name;
    final constructor =
        type != null &&
        RegExp(
          '^(?:const\\s+)?(?:factory\\s+)?${RegExp.escape(type)}'
          r'(?:\.[A-Za-z_$][\w$]*)?\(',
        ).hasMatch(bare);
    final subject = type == null || isHeader
        ? short
        : '$type.${constructor && short == type ? type : short}';
    if (!seen.add(subject)) return;
    out.add((
      subject: subject,
      what:
          'takes optional positional parameters, which a minor can never '
          'add a named one beside: make them named, with a parameters '
          'migration',
    ));
  }

  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: type, value: block)
        in library.declarations.entries) {
      final header = splitAnnotations(block.header).rest;
      if (RegExp(
        r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
        r'(class|enum|mixin|extension|extension type)\s',
      ).hasMatch(header)) {
        for (final line in block.members) {
          check(line, type, false);
        }
      } else if (!header.startsWith('typedef ')) {
        check(block.header, null, true);
      }
    }
  }
  return out;
}

/// The names an optional positional parameter may have and still be read as
/// the maths idiom it is: where to write a result, so a hot loop allocates
/// nothing.
const Set<String> outputParameterNames = <String>{'out', 'into'};

/// The names of the optional positional parameters of the signature on
/// [line].
List<String> optionalPositionalNamesOf(String line) {
  final inner = parameterListOf(line);
  if (inner == null) return const <String>[];
  final open = inner.indexOf('[');
  if (open < 0) return const <String>[];
  return <String>[
    for (final p in parametersOf('f(${inner.substring(open + 1)})')) p.name,
  ];
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

  // Collisions an allowlist may keep. Mutation: read only `material.dart`,
  // and a name `rendering` exports (`RenderView`) is kept again.
  final keptAgainstFlutter = flutterCollisionsAllowedIn(
    <String>['RenderView', 'LicenseEntry', 'Scene', 'Link'],
    <String, Set<String>>{
      'package:flutter/material.dart': <String>{'Scaffold'},
      'package:flutter/rendering.dart': <String>{'RenderView'},
      'package:flutter/foundation.dart': <String>{'LicenseEntry'},
      'dart:ui': <String>{'Scene'},
      'dart:io': <String>{'Link'},
    },
  );
  fires(
    'collisions kept against Flutter',
    keptAgainstFlutter.contains('RenderView') &&
        keptAgainstFlutter.contains('LicenseEntry'),
    'a name `rendering` and one `foundation` exports, kept with a reason',
  );
  quiet(
    'collisions kept against Flutter',
    keptAgainstFlutter.length == 2,
    'names only `dart:ui` and `dart:io` export',
    'a game reaches those through a prefix, and the reason may stand',
  );

  // Spelling, in the shader ABI as in the Dart snapshot: a stage, a member
  // and a sampler named with underscores are read word by word.
  final abiBritish = britishIdentifiersIn(
    '# a comment about colour is not a name\n'
    'entry SceneColourCopy fragment\n'
    'stage Pbr block LayerInfo member scene_colour 272 16 1 Vector4\n'
    'stage Pbr sampler scene_colour_texture\n'
    'stage Pbr sampler scene_color_texture\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'British spelling in the shader ABI',
    abiBritish.containsAll(<String>{
      'SceneColourCopy',
      'scene_colour',
      'scene_colour_texture',
    }),
    'an entry, a member and a sampler spelled British',
  );
  quiet(
    'British spelling in the shader ABI',
    abiBritish.length == 3,
    'a comment and an American sampler',
    'a comment is prose, and `color` is the American word',
  );

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

  // Null as an error.
  final nulls = nullAsErrorIn(
    '${lib}final class Blackboard\n'
    '  static Blackboard? fromJson(Object? data)\n'
    '  static Blackboard? tryParse(String text)\n'
    '  Blackboard? read(int at)\n'
    '  static int? byName(String name)\n\n'
    'Future<TextureHandle?> uploadEncodedImage(Uint8List bytes)\n\n'
    'TextureHandle uploadRgba8(Rgba8Image image)\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'null as an error',
    nulls.containsAll(<String>{'Blackboard.fromJson', 'uploadEncodedImage'}),
    'a static fromJson and a top-level upload that answer null',
  );
  quiet(
    'null as an error',
    nulls.length == 2,
    'a tryParse, an instance read, a byName and an upload that throws',
    'a try name and a lookup answer null by their idiom, and an instance '
        'member is its object\'s business',
  );

  // Constructors that cannot grow.
  final positional = optionalPositionalsIn(
    '${lib}final class ToolName\n'
    '  const ToolName(this.name, [this.hints = const <String>{}])\n'
    '  factory ToolName.parse(String text, [int at = 0])\n'
    '  void rename(String to, [bool loud = false])\n'
    '  Vector3 readPosition([Vector3? out])\n'
    '  Matrix4 worldMatrixOf(int index, [Matrix4? into])\n'
    '  static const VertexLayout plain = VertexLayout([position])\n\n'
    'final class Pair\n  const Pair(this.a, this.b, {this.c = const [1]})\n\n'
    'void lockLandscape([Playing? playing])\n\n'
    'typedef Hook = void Function([int at]);\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'optional positionals',
    positional.containsAll(<String>{
      'ToolName.ToolName',
      'ToolName.parse',
      'ToolName.rename',
      'lockLandscape',
    }),
    'a constructor, a factory, a method and a function with an optional '
        'positional list',
  );
  quiet(
    'optional positionals',
    positional.length == 4,
    'an `out` and an `into`, a constant\'s list literal, a list literal inside '
        'a named default',
    'a result written into the caller\'s vector is the maths idiom, and a '
        'value is not a signature',
  );

  // Verbs.
  final verbs = verbProblemsIn(
    '${lib}final class Lock\n  Future<void> close()\n  void dispose()\n'
    '  Offset takeDelta()\n  static Future<Lock> create()\n'
    '  Future<Pipe> createPipelineAsync()\n  int get getter\n\n'
    'final class Server\n  Future<void> shutdown()\n'
    '  static Server openLocal(int port)\n'
    '  static Future<Server> open(int port)\n'
    '  Stream<int> openEvents()\n\n'
    'final class Sink\n  void close()\n\n'
    'final class GlowNode extends RenderNode\n  void release()\n\n'
    'final class Upload extends RenderNode\n  void dispose()\n'
    '  void release()\n\n'
    'final class Pool\n  void release(TextureHandle texture)\n\n'
    'final class PointerLock\n  Future<void> release()\n\n'
    'Registry openRegistryFor(Object rules)\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'verbs',
    verbs.containsAll(<String>{
      'Lock',
      'Lock.takeDelta',
      'Lock.create',
      'Server.shutdown',
      'Server.openLocal',
      'openRegistryFor',
      'GlowNode.release',
      'Upload',
    }),
    'two teardown verbs, a lone shutdown, a take-prefixed method, an '
        'asynchronous create, a synchronous open on a type and at the top, '
        'a node that ends its life with `release`, and `release` beside '
        '`dispose`',
  );
  quiet(
    'verbs',
    !verbs.contains('Lock.createPipelineAsync') &&
        !verbs.contains('Lock.getter') &&
        !verbs.contains('Server.open') &&
        !verbs.contains('Server.openEvents') &&
        !verbs.any((String v) => v.startsWith('Sink')) &&
        !verbs.any((String v) => v.startsWith('Pool')) &&
        !verbs.any((String v) => v.startsWith('PointerLock')),
    'createPipelineAsync, a getter whose name starts with get, an open that '
        'waits, an open stream, a lone close, a release of something else, '
        'a release that waits',
    'the …Async variant of a synchronous create is the HAL\'s, a getter is no '
        'verb, `close` is a standard teardown, and a `release` that hands '
        'back another object or lets go of a hold ends nothing\'s life',
  );

  // Registrations that answer later.
  final later = asyncRegistrationsIn(
    '${lib}final class Steps extends RenderStepRegistry\n'
    '  Future<Registration> addComputeStep(ComputeStep step, {RenderAnchor? at})\n'
    '  FutureOr<Registration?> placeHook(SkinningHook hook)\n'
    '  Registration addNode(RenderNode node)\n'
    '  Future<void> whenPlaced()\n'
    '  Future<Registrations> loadAll()\n\n'
    'Future<Registration> registerLater(String name)\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'asynchronous registrations',
    later.containsAll(<String>{
      'Steps.addComputeStep',
      'Steps.placeHook',
      'registerLater',
    }),
    'a member answering Future<Registration>, one answering a nullable '
        'FutureOr, and a top-level function',
  );
  quiet(
    'asynchronous registrations',
    later.length == 3,
    'a synchronous registration, a wait that answers nothing, and a type '
        'whose name only starts with Registration',
    'a registration returned at once is the rule kept, and waiting for '
        'what loads behind one is what a registry offers beside it',
  );

  // Units.
  final units = unitSuffixesIn(
    '${lib}final class Cone\n  const Cone({this.halfAngleDegrees = 25.0})\n'
    '  final double sunElevationDeg\n  void observe(int step, double ms)\n'
    '  final double fovY\n  final double reloadSeconds\n'
    '  final int budgetMicros\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'unit suffixes',
    units.containsAll(<String>{
      'halfAngleDegrees',
      'sunElevationDeg',
      'ms',
      'budgetMicros',
    }),
    'a parameter in degrees, a field in degrees, a parameter in milliseconds, '
        'a budget in microseconds',
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

  // Records in results.
  final results = recordsInResultsIn(
    '${lib}typedef PartySeat = ({String host, int seat});\n\n'
    'typedef Hook = void Function(int at);\n\n'
    'final class Native\n'
    '  ({Vector3 point, double depth})? hit(Vector3 from)\n'
    '  (int, int) get cell\n'
    '  final List<(String, int)> pairs\n'
    '  void take(({int a, int b}) pair)\n'
    '  final void Function(int) onStep\n'
    '  set pair((int, int) value)\n\n'
    '(int, int) cellOf(Vector3 at)\n\n'
    'Native native()\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'records in results',
    results.containsAll(<String>{
      'PartySeat',
      'Native.hit',
      'Native.cell',
      'Native.pairs',
      'cellOf',
    }),
    'a record typedef, an inline record a method returns, a getter, a field '
        'and a function',
  );
  quiet(
    'records in results',
    results.length == 5,
    'a function typedef, a record parameter, a callback field, a setter, a '
        'class result',
    'what a caller builds is not what a caller reads',
  );

  // What a facade's API names and the facade does not export.
  const core =
      'library package:core/core.dart\n\n'
      'final class Engine\n'
      '  Registration addStep(RenderNode node, {int limit = Layers.most, '
      'Fallback fallback = const Fallback(), int depth = Hidden()})\n'
      '  @Deprecated(\'Use Hidden\') void old()\n'
      '  static const Engine none = Engine._(Hidden())\n\n'
      'abstract base class RenderNode\n'
      '  RenderAnchor get defaultAnchor\n'
      '  void setup<T extends Shape>(FrameGraphBuilder builder, T shape)\n\n'
      'final class Registration\n\nfinal class RenderAnchor\n\n'
      'final class FrameGraphBuilder\n  void declare(ResourceDesc desc)\n\n'
      'final class ResourceDesc\n\nfinal class Fallback\n\n'
      'final class Hidden\n\nfinal class Shape\n\n'
      'typedef Handler<T extends Shape> = void Function(Delivered<T> event)\n\n'
      'final class Delivered<T>\n\n'
      'final class Bus\n'
      '  Stream<Contact> get contacts\n'
      '  Map<String, List<Phase>> phases<E extends Shape>(E of)\n\n'
      'final class Contact\n\nfinal class Phase\n\n'
      'extension EngineLooks on Engine\n  int get looks\n\n'
      'extension HiddenLooks on Hidden\n\n'
      'final class Layers\n\n'
      'sealed class Answer\n\n'
      'final class Yes extends Answer\n\n'
      'final class Glow extends RenderNode implements Comparable<Answer>\n';
  const outside =
      'library package:other/other.dart\n\n'
      'final class Theirs extends RenderNode\n';
  const facadeApi =
      'library package:face/face.dart\n\n'
      'export package:core/core.dart show Answer, Bus, Engine, Handler, '
      'RenderNode\n'
      '  Answer\n  Bus\n  Engine\n  Handler\n  RenderNode\n';
  final gaps = facadeGapsIn(
    facade: 'face',
    exported: facadeNames(facadeApi, 'face'),
    declarations: typeDeclarationsIn(<String>[core, outside, facadeApi]),
    homes: typeHomesIn(<String, String>{
      'core': core,
      'other': outside,
      'face': facadeApi,
    }),
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'facade closure',
    gaps.containsAll(<String>{
      'Registration',
      'RenderAnchor',
      'FrameGraphBuilder',
      'ResourceDesc',
      'Shape',
      'Fallback',
    }),
    'a return type, a getter\'s type, a parameter, a bound, and a type named '
        'only by a type the facade does not export',
  );
  // Mutation: read a typedef's `=` as a default value, as before, and
  // `Delivered` goes quiet; read every `<Name>` as a type parameter, and
  // `Contact` and `Phase` do.
  fires(
    'facade closure',
    gaps.containsAll(<String>{'Delivered', 'Contact', 'Phase', 'EngineLooks'}),
    'a type a typedef\'s function type names, a type named only as a '
        'generic argument (`Stream<Contact>`, `List<Phase>`), and an '
        'extension on an exported type',
  );
  // Mutation: drop the downward step, and `Yes` and `Glow` go quiet; drop
  // what a default reads, and `Layers` does.
  fires(
    'facade closure',
    gaps.containsAll(<String>{'Yes', 'Glow', 'Layers'}),
    'a variant of an exported sealed base, a stock implementation its '
        'package gives an exported base, and the type of a constant a '
        'default value reads (`limit = Layers.most`)',
  );
  quiet(
    'facade closure',
    gaps.length == 13,
    'an annotation, a constant\'s value, a default value that only '
        'constructs, a type parameter, a method\'s own (`<E extends Shape>`) '
        'included, a type argument of a supertype, and a subtype another '
        'package declares',
    'a caller never writes those, or the facade never stood on them',
  );

  // A facade's show list against the library under it.
  final leftOut = facadeLeftOutIn(
    facade: 'face',
    facadeSnapshot:
        'library package:face/face.dart\n\n'
        'export package:core/core.dart show Engine, parseThing\n'
        '  Engine\n  parseThing\n'
        'export package:whole/whole.dart (whole library)\n'
        '  Whole\n',
    underneath: <String, String>{
      'core':
          'library package:core/core.dart\n\n'
          'final class Engine\n\nfinal class Kernel\n\n'
          'Thing parseThing(String source)\n\n'
          'Kernel lowerThing(Thing thing)\n\n'
          'export package:deep/deep.dart show Whole\n  Whole from deep\n\n'
          'library package:core/other.dart\n\nfinal class Elsewhere\n',
      'whole': 'library package:whole/whole.dart\n\nfinal class Whole\n',
    },
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'facade show list',
    leftOut.containsAll(<String>{'Kernel', 'lowerThing'}),
    'a class and a function the library under the facade declares',
  );
  quiet(
    'facade show list',
    leftOut.length == 2,
    'a name on the list, one admitted through another export, one in '
        'another library of the package, and a library re-exported whole',
    'the facade admits those, or never stood on them',
  );

  // Types nobody can import.
  final unimportable = unimportableTypesIn(
    'library package:p/p.dart\n\n'
    'final class SoLoudBackend\n'
    '  SoLoudBackend({SoLoud? soloud, Duration fade = const Duration()})\n'
    '  void sign(pc.RSAPrivateKey key, List<Widget> children)\n'
    '  Future<Map<String, E>> read<E>(Engine engine)\n',
    <String>{'SoLoudBackend', 'Engine'},
    <String, Set<String>>{
      'dart:core': <String>{'Duration', 'List', 'Map', 'String'},
      'dart:async': <String>{'Future'},
      'package:flutter/material.dart': <String>{'Widget'},
    },
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'unimportable types',
    unimportable.containsAll(<String>{'SoLoud', 'RSAPrivateKey'}),
    'a third-party type, and one behind an import prefix',
  );
  quiet(
    'unimportable types',
    unimportable.length == 2,
    'the SDK\'s, ours, and a type parameter',
    'a caller imports those from where they live',
  );

  // Thrown types.
  final thrown = thrownTypesIn(
    '  if (x) throw GpuDeviceException(what, message);\n'
    '  throw const FormatException.named(\'bad\');\n'
    '  throw StateError(\'no\');\n'
    '  /// throw DocException(1)\n'
    '  // throw CommentException(1)\n'
    '  throw _Private();\n'
    '  throw error;\n'
    '  throw p.PrefixedException(1);\n',
  );
  fires(
    'thrown types',
    thrown.containsAll(<String>{
      'GpuDeviceException',
      'FormatException',
      'StateError',
      'PrefixedException',
    }),
    'a throw, a const throw of a named constructor, and one through a prefix',
  );
  quiet(
    'thrown types',
    thrown.length == 4,
    'a doc comment, a comment, a private type, a rethrown variable',
    'none of those is a type a caller catches by a public name',
  );

  // Plain classes.
  final plain = plainClassesIn(
    '${lib}class HudPanel extends StatelessWidget\n\n'
    'abstract class Shape\n\n'
    'final class Value\n\nbase class Component3d\n\n'
    'abstract base class Hook\n\nsealed class Result\n\n'
    'abstract interface class Marker\n\nmixin class Listener\n\n'
    'abstract final class Kinds\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'plain classes',
    plain.containsAll(<String>{'HudPanel', 'Shape'}),
    'a plain class and a plain abstract class',
  );
  quiet(
    'plain classes',
    plain.length == 2,
    'final, base, abstract base, sealed, interface, mixin and abstract final '
        'classes',
    'each says how it may be extended',
  );

  // The shape of an open set.
  final sets = openSetShapeIn(
    '${lib}final class TonemapCurve\n'
    '  static const TonemapCurve aces = TonemapCurve._(\'aces\')\n'
    '  static const TonemapCurve neutral = TonemapCurve._(\'neutral\')\n'
    '  final String name\n\n'
    'final class DeviceFeature\n'
    '  static DeviceFeature byName(String name)\n'
    '  static const DeviceFeature compute = DeviceFeature._(\'compute\')\n'
    '  static const DeviceFeature wireframe = DeviceFeature._(\'wireframe\')\n'
    '  static const List<DeviceFeature> values = <DeviceFeature>[]\n\n'
    'final class Palette\n'
    '  static const Palette light = Palette()\n\n'
    'final class RenderAnchor\n'
    '  static RenderAnchor named(String name)\n'
    '  static const RenderAnchor opaque = RenderAnchor._(\'opaque\')\n'
    '  static const RenderAnchor post = RenderAnchor._(\'post\')\n'
    '  static const List<RenderAnchor> values = <RenderAnchor>[]\n',
  ).map((NamingProblem p) => p.subject).toSet();
  fires(
    'open set shape',
    sets.containsAll(<String>{'TonemapCurve', 'RenderAnchor'}),
    'a set with neither `values` nor `byName`, and one whose lookup is '
        '`named`',
  );
  quiet(
    'open set shape',
    sets.length == 2,
    '`DeviceFeature`, and a class with one constant',
    'the first is the shape, and one preset is not a set',
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
