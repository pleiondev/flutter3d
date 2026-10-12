/// What a change to a package's public API means for its version number, read
/// from two `.api` snapshots — and the two other things about the API a rule
/// has to read from text: a CHANGELOG's "Breaking" label and a deprecation's
/// message.
///
/// **Plain Dart over text, on purpose.** The snapshots are written by
/// `tool/api` with the analyzer, which needs a resolved workspace; this file
/// needs nothing, so the structure scan can classify a change and check a
/// label before `pub get` has run, and `tool/api` imports it to print the
/// same verdict it holds a pull request to. One classifier, two callers.
///
/// The format it reads is the one `tool/api/lib/api_snapshot.dart` writes:
///
/// ```text
/// # comment lines
///
/// library package:pkg/pkg.dart
///
/// abstract interface class Device            <- a declaration, one block
///   void draw(int count, {int first = 0})    <- its members, indented
///
/// int clamp(int value)                       <- a one-line declaration
///
/// export package:other/other.dart (whole library)
///   Name                                     <- what that re-export admits
///   Other from third                         <- declared one package further
/// ```
library;

/// How far a change moves the version.
enum Bump {
  /// Nothing a caller can see.
  none,

  /// An addition: a minor release (any release, before 1.0).
  minor,

  /// A break: a major release (a minor one, before 1.0).
  major,
}

/// One classified difference between two snapshots.
final class ApiChange {
  const ApiChange(this.library, this.subject, this.what, this.bump);

  /// The library it is in, as `package:name/file.dart`.
  final String library;

  /// The top-level name it is about — what a CHANGELOG entry has to name.
  final String subject;

  /// One line, for a person.
  final String what;

  /// What it does to the version.
  final Bump bump;

  @override
  String toString() =>
      '${bump == Bump.major ? 'breaking' : 'addition'}  $subject: $what';
}

// ----------------------------------------------------------------- parsing

/// One block of a snapshot: a header line and its indented lines.
final class ApiBlock {
  const ApiBlock(this.header, this.members);
  final String header;
  final List<String> members;
}

/// One library of a snapshot.
final class ApiLibrary {
  ApiLibrary(this.uri);
  final String uri;

  /// Declarations of the package itself, by name.
  final Map<String, ApiBlock> declarations = <String, ApiBlock>{};

  /// Re-exports, by the URI they re-export.
  final Map<String, ApiBlock> exports = <String, ApiBlock>{};
}

/// A snapshot's libraries, by URI.
Map<String, ApiLibrary> parseApi(String text) {
  final libraries = <String, ApiLibrary>{};
  ApiLibrary? current;
  final lines = text
      .split('\n')
      .where((String l) => !l.startsWith('#'))
      .toList(growable: false);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.startsWith(' ')) continue;
    if (line.startsWith('library ')) {
      final uri = line.substring('library '.length).trim();
      current = libraries[uri] = ApiLibrary(uri);
      continue;
    }
    final members = <String>[
      for (var j = i + 1; j < lines.length && lines[j].startsWith('  '); j++)
        lines[j].substring(2),
    ];
    final block = ApiBlock(line, members);
    final into = current ??= libraries[''] = ApiLibrary('');
    if (line.startsWith('export ')) {
      into.exports[line.split(' ')[1]] = block;
    } else {
      into.declarations[declarationName(line)] = block;
    }
  }
  return libraries;
}

/// The annotations a snapshot line starts with, and the rest of it.
({List<String> annotations, String rest}) splitAnnotations(String line) {
  final annotations = <String>[];
  var rest = line.trimLeft();
  while (rest.startsWith('@')) {
    final name = RegExp(r'^@[\w$.]+').firstMatch(rest)!.group(0)!;
    var end = name.length;
    if (end < rest.length && rest[end] == '(') {
      end = _closing(rest, end) + 1;
    }
    annotations.add(rest.substring(0, end));
    rest = rest.substring(end).trimLeft();
  }
  return (annotations: annotations, rest: rest);
}

final List<RegExp> _typeNames = <RegExp>[
  RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s+([\w$]+)',
  ),
  RegExp(r'^(?:base\s+)?mixin\s+([\w$]+)'),
  RegExp(r'^enum\s+([\w$]+)'),
  RegExp(r'^extension\s+type\s+(?:const\s+)?([\w$]+)'),
  RegExp(r'^extension\s+([\w$]+)'),
  RegExp(r'^typedef\s+([\w$]+)\s*[<=]'),
];

/// The name a top-level declaration line declares.
String declarationName(String header) {
  final bare = splitAnnotations(header).rest;
  for (final pattern in _typeNames) {
    final match = pattern.firstMatch(bare);
    if (match != null) return match.group(1)!;
  }
  return memberName(bare);
}

/// The name a member line (or a function or variable) declares: `foo` for a
/// method, getter or field, `foo=` for a setter, `Type.named` for a
/// constructor and `operator ==` for an operator.
String memberName(String line) {
  final bare = _withoutAbstract(splitAnnotations(line).rest);
  final operator = RegExp(r'\boperator\s*([^\s(]+)\s*\(').firstMatch(bare);
  if (operator != null) return 'operator ${operator.group(1)}';
  var text = bare;
  final assign = _topLevelAssignment(text);
  if (assign >= 0) text = text.substring(0, assign).trimRight();
  if (text.endsWith(')')) {
    text = text.substring(0, _opening(text, text.length - 1)).trimRight();
    if (text.endsWith('>')) {
      text = text.substring(0, _opening(text, text.length - 1)).trimRight();
    }
    final name = RegExp(r'([\w$.]+)$').firstMatch(text)?.group(1) ?? text;
    return RegExp(r'(^|\s)set\s+[\w$]+$').hasMatch(text) ? '$name=' : name;
  }
  return RegExp(r'([\w$]+)$').firstMatch(text)?.group(1) ?? text;
}

// ---------------------------------------------------------- classifying

/// Every difference between [before] and [after], classified.
///
/// Changes that move nothing a caller can see — a reworded deprecation, a
/// reordering — are not listed. What counts as a break is written out where
/// each one is decided, because that list is the contract `CONTRIBUTING.md`
/// describes: it is meant to be read.
List<ApiChange> classifyApi(String before, String after) {
  final old = parseApi(before);
  final now = parseApi(after);
  final changes = <ApiChange>[];
  for (final uri in <String>{...old.keys, ...now.keys}.toList()..sort()) {
    final a = old[uri];
    final b = now[uri];
    if (a == null) {
      changes.add(ApiChange(uri, uri, 'a new library', Bump.minor));
      continue;
    }
    if (b == null) {
      changes.add(ApiChange(uri, uri, 'the library is gone', Bump.major));
      continue;
    }
    if (isOutsideSemver(uri)) {
      // Decision 2 of 2026-10-12: the engine's packages ask for each other
      // within one minor, so what these libraries change is a minor's.
      final inside = <ApiChange>[];
      _classifyLibrary(a, b, inside);
      changes.addAll(<ApiChange>[
        for (final c in inside)
          c.bump == Bump.major
              ? ApiChange(
                  c.library,
                  c.subject,
                  '${c.what} (a library outside semver: a minor)',
                  Bump.minor,
                )
              : c,
      ]);
      continue;
    }
    _classifyLibrary(a, b, changes);
  }
  return changes;
}

/// Whether the library [uri] is one of the engine's own, outside semver:
/// `package:<p>/internal.dart` or `package:<p>/builtin.dart`. The engine's
/// packages read them and ask for each other within one minor, so a change
/// here is a minor's (CONTRIBUTING, "The API is a snapshot").
bool isOutsideSemver(String uri) =>
    RegExp(r'^package:\w+/(internal|builtin)\.dart$').hasMatch(uri);

/// The largest bump among [changes].
Bump requiredBump(Iterable<ApiChange> changes) => changes.fold(
  Bump.none,
  (Bump most, ApiChange c) => c.bump.index > most.index ? c.bump : most,
);

/// [changes] as a person reads them, grouped by library.
String describeApiChanges(List<ApiChange> changes) {
  if (changes.isEmpty) return 'no change a caller can see';
  final out = StringBuffer();
  String? library;
  for (final change in changes) {
    if (change.library != library) {
      library = change.library;
      out.writeln('library $library');
    }
    out.writeln('  $change');
  }
  out.write(switch (requiredBump(changes)) {
    Bump.major =>
      'A major release (a minor one before 1.0), and a '
          '"**Breaking:**" entry in CHANGELOG.md naming each broken name.',
    Bump.minor => 'A minor release at least (any release before 1.0).',
    Bump.none => 'No version decision.',
  });
  return out.toString();
}

void _classifyLibrary(ApiLibrary a, ApiLibrary b, List<ApiChange> out) {
  void add(String subject, String what, Bump bump) =>
      out.add(ApiChange(b.uri, subject, what, bump));

  final sealed = <String>{
    for (final e in b.declarations.entries)
      if (_modifiers(splitAnnotations(e.value.header).rest).contains('sealed'))
        e.key,
  };

  for (final name in <String>{
    ...a.declarations.keys,
    ...b.declarations.keys,
  }.toList()..sort()) {
    final was = a.declarations[name];
    final now = b.declarations[name];
    if (was == null) {
      // A new subtype of a sealed type is a case every exhaustive `switch`
      // over it is now missing.
      final parents = _supertypes(splitAnnotations(now!.header).rest);
      final broken = parents.where(sealed.contains);
      if (broken.isNotEmpty) {
        add(
          name,
          'new subtype of sealed ${broken.first}: every exhaustive switch over '
          'it is missing a case',
          Bump.major,
        );
      } else {
        add(name, 'new', Bump.minor);
      }
      continue;
    }
    if (now == null) {
      add(name, 'gone', Bump.major);
      continue;
    }
    _classifyDeclaration(name, was, now, add);
  }

  for (final uri in <String>{
    ...a.exports.keys,
    ...b.exports.keys,
  }.toList()..sort()) {
    final was = a.exports[uri];
    final now = b.exports[uri];
    if (was == null) {
      add(uri, 'newly re-exported', Bump.minor);
      continue;
    }
    if (now == null) {
      add(uri, 'no longer re-exported', Bump.major);
      continue;
    }
    _classifyExport(uri, was, now, add);
  }
}

typedef _Add = void Function(String subject, String what, Bump bump);

/// What outside code may do with a type, read off its header.
typedef _Openness = ({
  String kind,
  bool implement,
  bool extend,
  bool mixIn,
  bool construct,
});

const Set<String> _classModifiers = <String>{
  'abstract',
  'base',
  'final',
  'interface',
  'sealed',
  'mixin',
};

Set<String> _modifiers(String bare) {
  final words = bare.split(' ');
  return <String>{for (final w in words.takeWhile(_classModifiers.contains)) w};
}

_Openness _openness(String bare) {
  final m = _modifiers(bare);
  final afterModifiers = bare.split(' ').skip(m.length).firstOrNull ?? '';
  if (afterModifiers == 'class') {
    final closed = m.contains('sealed');
    return (
      kind: 'class',
      implement: !closed && !m.contains('final') && !m.contains('base'),
      extend: !closed && !m.contains('final') && !m.contains('interface'),
      mixIn: m.contains('mixin'),
      construct: !closed && !m.contains('abstract'),
    );
  }
  if (m.contains('mixin')) {
    return (
      kind: 'mixin',
      implement: !m.contains('base'),
      extend: false,
      mixIn: true,
      construct: false,
    );
  }
  final kind = bare.startsWith('extension type')
      ? 'extension type'
      : RegExp(r'^(enum|extension|typedef)\b').firstMatch(bare)?.group(1) ??
            'member';
  return (
    kind: kind,
    implement: false,
    extend: false,
    mixIn: false,
    construct: false,
  );
}

void _classifyDeclaration(String name, ApiBlock a, ApiBlock b, _Add add) {
  final was = splitAnnotations(a.header);
  final now = splitAnnotations(b.header);
  final open = _openness(now.rest);

  if (was.rest != now.rest) {
    final before = _openness(was.rest);
    if (before.kind != open.kind) {
      add(name, 'was a ${before.kind}, is a ${open.kind}', Bump.major);
    } else if (open.kind == 'member' &&
        (_elided(was.rest) || _elided(now.rest)) &&
        was.rest.split(' = ').first == now.rest.split(' = ').first) {
      // A constant too long to list: nothing to compare, nothing claimed.
    } else if (open.kind == 'member') {
      _classifySignature(
        name,
        was.rest,
        now.rest,
        overridable: false,
        add: add,
      );
    } else {
      _classifyHeader(name, before, open, was.rest, now.rest, add);
    }
  }
  _classifyAnnotations(
    name,
    was.annotations,
    now.annotations,
    add,
    subtypable: open.implement || open.extend || open.mixIn,
  );

  String keyOf(String m) => m.startsWith('values:') ? 'values:' : memberName(m);
  final oldMembers = <String, String>{for (final m in a.members) keyOf(m): m};
  final newMembers = <String, String>{for (final m in b.members) keyOf(m): m};
  for (final key in <String>{
    ...oldMembers.keys,
    ...newMembers.keys,
  }.toList()..sort()) {
    final m0 = oldMembers[key];
    final m1 = newMembers[key];
    final label = key == 'values:' ? '$name values' : '$name.$key';
    if (key == 'values:') {
      if (m0 != m1) {
        add(
          name,
          'the values changed (${m0 ?? ''} -> ${m1 ?? ''}): a removed value '
          'breaks its users and an added one every exhaustive switch',
          Bump.major,
        );
      }
      continue;
    }
    if (m0 == null) {
      add(
        name,
        _addedMember(label, m1!, name, open),
        _addedBump(m1, name, open),
      );
      continue;
    }
    if (m1 == null) {
      add(name, '$label is gone', Bump.major);
      continue;
    }
    if (m0 == m1) continue;
    // A snapshot written before `this._x` carried its type: the type printed
    // now is no change.
    if (m0 == withoutPrivateFormalTypes(m1) && m0 != m1) continue;
    final x = splitAnnotations(m0);
    final y = splitAnnotations(m1);
    _classifyAnnotations(
      label,
      x.annotations,
      y.annotations,
      add,
      subtypable: open.implement || open.extend || open.mixIn,
      subject: name,
    );
    if (x.rest == y.rest) continue;
    if (_elided(x.rest) || _elided(y.rest)) {
      // A constant whose value is too long to list on either side: the
      // snapshot cannot say whether the value moved, and does not pretend to.
      final cut = ' = ';
      final a = x.rest.split(cut).first;
      final b = y.rest.split(cut).first;
      if (a == b) continue;
    }
    final staticOrNew =
        y.rest.startsWith('static ') || _isConstructor(key, name);
    final xa = _withoutAbstract(x.rest);
    final ya = _withoutAbstract(y.rest);
    if (xa == ya) {
      // Only `abstract` moved: a body taken away is a member every subclass
      // now has to write.
      final nowAbstract = y.rest.startsWith('abstract ');
      add(
        name,
        nowAbstract ? '$label lost its body' : '$label gained a body',
        nowAbstract && (open.extend || open.mixIn) ? Bump.major : Bump.minor,
      );
      continue;
    }
    _classifySignature(
      label,
      xa,
      ya,
      overridable:
          !staticOrNew && (open.implement || open.extend || open.mixIn),
      add: (String _, String what, Bump bump) => add(name, what, bump),
    );
  }
}

/// [line] with the type before each `this._x` dropped, as snapshots printed
/// a private initializing formal before they named its type:
/// `T(Sink<String> this._sink)` is `T(this._sink)`.
String withoutPrivateFormalTypes(String line) => line.replaceAllMapped(
  RegExp(
    r'([(\[{,]\s*(?:required\s+|covariant\s+)*)'
    r'(?:[\w$.]+(?:<[^()]*?>)?\??\s+)(this\._[\w$]+)',
  ),
  (Match m) => '${m[1]}${m[2]}',
);

/// A constant listed as `= …` because its value is too long to list.
bool _elided(String line) => line.endsWith(' = …');

bool _isConstructor(String key, String type) =>
    key == type || key.startsWith('$type.');

String _addedMember(String label, String line, String type, _Openness open) {
  final bump = _addedBump(line, type, open);
  if (bump == Bump.minor) return '$label is new';
  return open.implement
      ? '$label is new on a type outside code may implement: every '
            'implementer has to add it'
      : '$label is new and abstract on a type outside code may extend: every '
            'subclass has to write it';
}

/// **The one place a new member is a break.** A type outside code may
/// `implement` gains a member every implementer now lacks, whatever its body
/// here says — `implements` inherits no bodies. A type that may only be
/// extended gains one only if it has no body. Statics and constructors are
/// never inherited, so they are always additions.
Bump _addedBump(String line, String type, _Openness open) {
  final bare = splitAnnotations(line).rest;
  if (bare.startsWith('static ') || _isConstructor(memberName(line), type)) {
    return Bump.minor;
  }
  if (open.implement) return Bump.major;
  if ((open.extend || open.mixIn) && bare.startsWith('abstract ')) {
    return Bump.major;
  }
  return Bump.minor;
}

void _classifyHeader(
  String name,
  _Openness before,
  _Openness after,
  String was,
  String now,
  _Add add,
) {
  final lost = <String>[
    if (before.implement && !after.implement) 'implemented',
    if (before.extend && !after.extend) 'extended',
    if (before.mixIn && !after.mixIn) 'mixed in',
    if (before.construct && !after.construct) 'constructed',
  ];
  if (lost.isNotEmpty) {
    add(name, 'can no longer be ${lost.join(' or ')} ($now)', Bump.major);
  }
  final tailWas = _tail(was);
  final tailIs = _tail(now);
  if (tailWas == tailIs) {
    if (lost.isEmpty) add(name, 'opened up ($now)', Bump.minor);
    return;
  }
  final c0 = _clauses(tailWas);
  final c1 = _clauses(tailIs);
  final grew =
      c0.head == c1.head &&
      c0.superclass == c1.superclass &&
      c0.on == c1.on &&
      c1.mixins.containsAll(c0.mixins) &&
      c1.interfaces.containsAll(c0.interfaces);
  if (!grew) {
    add(name, 'the declaration changed: $was -> $now', Bump.major);
  } else if (after.implement) {
    add(
      name,
      'gained a supertype on a type outside code may implement: every '
      'implementer has to add its members ($now)',
      Bump.major,
    );
  } else {
    add(name, 'gained a supertype ($now)', Bump.minor);
  }
}

/// Annotations that restrict a caller when they arrive.
const Set<String> _restrictingCallers = <String>{
  '@visibleForTesting',
  '@protected',
  '@internal',
  '@experimental',
};

/// Annotations that restrict only a subclass or an implementer when they
/// arrive — so on a type nobody outside may extend or implement, nobody.
const Set<String> _restrictingSubtypes = <String>{
  '@visibleForOverriding',
  '@nonVirtual',
  '@mustCallSuper',
  '@mustBeOverridden',
  '@sealed',
  '@immutable',
};

void _classifyAnnotations(
  String label,
  List<String> was,
  List<String> now,
  _Add add, {
  required bool subtypable,
  String? subject,
}) {
  String nameOf(String a) => RegExp(r'^@[\w$.]+').firstMatch(a)!.group(0)!;
  final before = was.map(nameOf).toSet();
  final after = now.map(nameOf).toSet();
  final who = subject ?? label;
  bool restricts(String a) =>
      _restrictingCallers.contains(a) ||
      subtypable && _restrictingSubtypes.contains(a);
  for (final a in after.difference(before)) {
    if (a == '@Deprecated' || a == '@deprecated') {
      add(who, '$label is deprecated', Bump.minor);
    } else if (restricts(a)) {
      add(who, '$label is now $a', Bump.major);
    }
  }
  for (final a in before.difference(after)) {
    if (restricts(a) || a.toLowerCase() == '@deprecated') {
      add(who, '$label is no longer $a', Bump.minor);
    }
  }
}

/// A signature that changed: an addition only when the new one is the old
/// one with optional parameters added, and nobody outside overrides it —
/// an override written against the old list no longer matches the new one.
void _classifySignature(
  String label,
  String was,
  String now, {
  required bool overridable,
  required _Add add,
}) {
  if (!overridable && onlyGrewOptionalParameters(was, now)) {
    add(label, '$label gained an optional parameter ($now)', Bump.minor);
    return;
  }
  add(label, '$label changed: $was -> $now', Bump.major);
}

/// Whether [now] is [was] with optional parameters added and nothing else.
bool onlyGrewOptionalParameters(String was, String now) {
  if (!was.endsWith(')') || !now.endsWith(')')) return false;
  final o0 = _opening(was, was.length - 1);
  final o1 = _opening(now, now.length - 1);
  if (was.substring(0, o0) != now.substring(0, o1)) return false;
  final p0 = _parameters(was.substring(o0 + 1, was.length - 1));
  final p1 = _parameters(now.substring(o1 + 1, now.length - 1));
  if (p0.positional.join(',') != p1.positional.join(',')) return false;
  if (p0.optional.length > p1.optional.length) return false;
  for (var i = 0; i < p0.optional.length; i++) {
    if (p0.optional[i] != p1.optional[i]) return false;
  }
  if (!p1.named.containsAll(p0.named)) return false;
  if (p0.optional.isNotEmpty && p1.named.isNotEmpty) return false;
  return p1.named
      .difference(p0.named)
      .every((String n) => !n.startsWith('required '));
}

({List<String> positional, List<String> optional, Set<String> named})
_parameters(String inner) {
  final items = _splitTop(inner);
  final positional = <String>[];
  final optional = <String>[];
  final named = <String>{};
  for (final item in items) {
    if (item.startsWith('[')) {
      optional.addAll(_splitTop(item.substring(1, item.length - 1)));
    } else if (item.startsWith('{')) {
      named.addAll(_splitTop(item.substring(1, item.length - 1)));
    } else {
      positional.add(item);
    }
  }
  return (positional: positional, optional: optional, named: named);
}

void _classifyExport(String uri, ApiBlock a, ApiBlock b, _Add add) {
  String key(String line) =>
      line.startsWith('export ') ? line : line.split(' ').first;
  final old = <String, String>{for (final m in a.members) key(m): m};
  final now = <String, String>{for (final m in b.members) key(m): m};
  for (final k in old.keys.where((String k) => !now.containsKey(k))) {
    add(
      k.startsWith('export ') ? uri : k,
      'no longer re-exported through $uri',
      Bump.major,
    );
  }
  for (final k in now.keys.where((String k) => !old.containsKey(k))) {
    add(
      k.startsWith('export ') ? uri : k,
      'newly re-exported through $uri',
      Bump.minor,
    );
  }
  if (a.members.isEmpty && b.members.isEmpty && a.header != b.header) {
    // Outside the repository, so only the combinators can be compared.
    final s0 = _combinatorNames(a.header, 'show');
    final s1 = _combinatorNames(b.header, 'show');
    final h0 = _combinatorNames(a.header, 'hide') ?? const <String>{};
    final h1 = _combinatorNames(b.header, 'hide') ?? const <String>{};
    final narrower =
        (s0 == null && s1 != null) ||
        (s0 != null && s1 != null && s0.difference(s1).isNotEmpty) ||
        h1.difference(h0).isNotEmpty;
    add(
      uri,
      '${narrower ? 'narrower' : 'wider'} re-export: ${b.header}',
      narrower ? Bump.major : Bump.minor,
    );
  }
}

Set<String>? _combinatorNames(String header, String word) {
  final match = RegExp(
    '\\b$word ([\\w\$, ]+?)(?= show | hide | \\(|\$)',
  ).firstMatch(header);
  return match?.group(1)!.split(',').map((String s) => s.trim()).toSet();
}

// ----------------------------------------------------------------- header

String _tail(String bare) =>
    bare.split(' ').skip(_modifiers(bare).length).join(' ');

({
  String head,
  String superclass,
  Set<String> mixins,
  Set<String> interfaces,
  String on,
})
_clauses(String tail) {
  const words = <String>[' extends ', ' with ', ' implements ', ' on '];
  final cuts = <(int, String)>[
    for (final w in words)
      if (_topLevelIndexOf(tail, w) case final i when i >= 0) (i, w),
  ]..sort(((int, String) x, (int, String) y) => x.$1.compareTo(y.$1));
  String part(String word) {
    for (var i = 0; i < cuts.length; i++) {
      if (cuts[i].$2 != word) continue;
      final end = i + 1 < cuts.length ? cuts[i + 1].$1 : tail.length;
      return tail.substring(cuts[i].$1 + word.length, end).trim();
    }
    return '';
  }

  Set<String> list(String word) =>
      _splitTop(part(word)).where((String s) => s.isNotEmpty).toSet();
  return (
    head: cuts.isEmpty ? tail : tail.substring(0, cuts.first.$1),
    superclass: part(' extends '),
    mixins: list(' with '),
    interfaces: list(' implements '),
    on: part(' on '),
  );
}

/// The type names a declaration line extends, implements or mixes in.
Set<String> _supertypes(String bare) {
  final c = _clauses(_tail(bare));
  return <String>{
    for (final t in <String>[c.superclass, ...c.mixins, ...c.interfaces, c.on])
      if (t.isNotEmpty) RegExp(r'^[\w$.]+').firstMatch(t)?.group(0) ?? t,
  };
}

/// A member line without the `abstract ` the snapshot marks a bodiless
/// member with. Only member lines are passed here, never a type's header.
String _withoutAbstract(String bare) =>
    bare.startsWith('abstract ') ? bare.substring('abstract '.length) : bare;

// ------------------------------------------------------------------- text

const String _opens = '([{<';
const String _closes = ')]}>';

/// The index of the bracket closing the one at [open], skipping strings.
int _closing(String s, int open) {
  var depth = 0;
  String? quote;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
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
    } else if (_opens.contains(c) && !(c == '<' && _isOperatorAt(s, i))) {
      depth++;
    } else if (_closes.contains(c) && !(c == '>' && _isArrowAt(s, i))) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return s.length - 1;
}

/// The index of the bracket opening the one at [close], walking back.
int _opening(String s, int close) {
  var depth = 0;
  for (var i = close; i >= 0; i--) {
    final c = s[i];
    if (_closes.contains(c) && !(c == '>' && _isArrowAt(s, i))) {
      depth++;
    } else if (_opens.contains(c) && !(c == '<' && _isOperatorAt(s, i))) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return 0;
}

/// Whether the `>` at [i] is not a bracket: the end of `=>`, or part of an
/// operator's name (`operator >`, `operator >=`, `operator >>`).
bool _isArrowAt(String s, int i) =>
    (i > 0 && s[i - 1] == '=') || _isOperatorAt(s, i);

/// Whether the `<` or `>` at [i] is part of an operator's name.
bool _isOperatorAt(String s, int i) {
  var j = i;
  while (j > 0 && '<>= '.contains(s[j - 1])) {
    j--;
  }
  return s.substring(0, j).endsWith('operator');
}

/// [s] split at commas outside brackets and strings.
List<String> _splitTop(String s) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
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
    } else if (_opens.contains(c)) {
      depth++;
    } else if (_closes.contains(c) && !(c == '>' && _isArrowAt(s, i))) {
      depth--;
    } else if (c == ',' && depth == 0) {
      out.add(s.substring(start, i).trim());
      start = i + 1;
    }
  }
  final last = s.substring(start).trim();
  if (last.isNotEmpty) out.add(last);
  return out;
}

int _topLevelIndexOf(String s, String needle) {
  var depth = 0;
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
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
    } else if (_opens.contains(c)) {
      depth++;
    } else if (_closes.contains(c) && !(c == '>' && _isArrowAt(s, i))) {
      depth--;
    } else if (depth == 0 && s.startsWith(needle, i)) {
      return i;
    }
  }
  return -1;
}

/// The ` = ` that starts a variable's initialiser, outside any brackets.
int _topLevelAssignment(String s) {
  final i = _topLevelIndexOf(s, ' = ');
  return i;
}

// -------------------------------------------------------------- versions

/// A version's three numbers; pre-release and build parts are ignored.
typedef Version = ({int major, int minor, int patch});

/// [text] as a [Version], or null when it is not one.
Version? parseVersion(String text) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(text.trim());
  if (m == null) return null;
  return (
    major: int.parse(m.group(1)!),
    minor: int.parse(m.group(2)!),
    patch: int.parse(m.group(3)!),
  );
}

int compareVersions(Version a, Version b) => a.major != b.major
    ? a.major.compareTo(b.major)
    : a.minor != b.minor
    ? a.minor.compareTo(b.minor)
    : a.patch.compareTo(b.patch);

/// Whether going from [released] to [current] is enough of a release for
/// [needed]. Before 1.0 the minor is the breaking digit, as pub reads it.
bool bumpIsEnough(Bump needed, Version released, Version current) {
  final breaking = released.major == 0
      ? current.major > 0 || current.minor > released.minor
      : current.major > released.major;
  final adding = released.major == 0
      ? compareVersions(current, released) > 0
      : current.major > released.major ||
            current.minor > released.minor && current.major == released.major;
  return switch (needed) {
    Bump.none => true,
    Bump.minor => adding,
    Bump.major => breaking,
  };
}

/// The pre-release identifiers of a version [text]: `['rc', '1']` for
/// `1.0.0-rc.1`, empty for a release. A build part after `+` is not one.
List<String> preReleaseOf(String text) {
  final core = text.trim().split('+').first;
  final dash = core.indexOf('-');
  return dash < 0 ? const <String>[] : core.substring(dash + 1).split('.');
}

/// Two version texts in semver's order, which [Version] alone cannot give:
/// a pre-release sorts below its release, so `1.0.0-rc.1` < `1.0.0`, and
/// `rc.2` < `rc.10`, numerically. Null when either is not a version.
int? compareVersionTexts(String a, String b) {
  final x = parseVersion(a);
  final y = parseVersion(b);
  if (x == null || y == null) return null;
  final numbers = compareVersions(x, y);
  if (numbers != 0) return numbers;
  final xPre = preReleaseOf(a);
  final yPre = preReleaseOf(b);
  if (xPre.isEmpty || yPre.isEmpty) {
    return (xPre.isEmpty ? 1 : 0) - (yPre.isEmpty ? 1 : 0);
  }
  for (var i = 0; i < xPre.length && i < yPre.length; i++) {
    final c = switch ((int.tryParse(xPre[i]), int.tryParse(yPre[i]))) {
      (final int l, final int r) => l.compareTo(r),
      (int(), null) => -1,
      (null, int()) => 1,
      _ => xPre[i].compareTo(yPre[i]),
    };
    if (c != 0) return c;
  }
  return xPre.length.compareTo(yPre.length);
}

/// [bumpIsEnough] for version texts, with semver's one exception: a
/// pre-release promises nothing, so any later version is enough after one.
/// `1.0.0` may change what `1.0.0-rc.1` had, which a break still has to
/// label in the CHANGELOG; what it may not do is stay `1.0.0-rc.1`.
bool bumpIsEnoughFrom(Bump needed, String released, String current) {
  if (needed == Bump.none) return true;
  final then = parseVersion(released);
  final now = parseVersion(current);
  if (then == null || now == null) return true;
  if (preReleaseOf(released).isNotEmpty) {
    return compareVersionTexts(current, released)! > 0;
  }
  return bumpIsEnough(needed, then, now);
}

/// Whether `^asked` admits [declared], by pub's caret rule: below 1.0.0 the
/// minor is the breaking number, so `^0.4.0` reaches 0.4.x and stops at 0.5;
/// from 1.0.0 the major is, so `^1.2.0` reaches 1.x from 1.2 up. The floor
/// is semver's: `^1.0.0` does not admit `1.0.0-rc.1`, which sorts below it,
/// and `^1.0.0-rc.1` admits the `1.0.0` after it. Text that is not a version
/// admits only itself.
bool caretAdmits(String asked, String declared) {
  final a = parseVersion(asked);
  final d = parseVersion(declared);
  if (a == null || d == null) return asked == declared;
  final sameLine = a.major == 0
      ? d.major == 0 && d.minor == a.minor
      : d.major == a.major;
  return sameLine && compareVersionTexts(declared, asked)! >= 0;
}

// ------------------------------------------------------------- changelog

/// The label a CHANGELOG entry carries when the release breaks something.
///
/// An entry — a bullet or a paragraph — whose bold thesis begins with it:
/// `- **Breaking: `Device.draw` takes a count.** Callers pass …`, or
/// `**Breaking:** …`. One label, spelled one way, so a reader scanning a
/// changelog and a rule reading it look for the same thing.
const String breakingLabel = '**Breaking:';

/// The first `## ` section of [changelog]: its heading and its text.
({String heading, String text}) topSection(String changelog) {
  final lines = changelog.split('\n');
  final start = lines.indexWhere((String l) => l.startsWith('## '));
  if (start < 0) return (heading: '', text: '');
  final end = lines.indexWhere((String l) => l.startsWith('## '), start + 1);
  return (
    heading: lines[start].substring(3).trim(),
    text: lines.sublist(start + 1, end < 0 ? lines.length : end).join('\n'),
  );
}

/// The entries of a changelog section that carry [breakingLabel], each as
/// one string.
List<String> breakingEntries(String section) {
  final entries = <String>[];
  final current = <String>[];
  void flush() {
    if (current.isEmpty) return;
    final text = current.join(' ');
    final thesis = text.startsWith('- ') ? text.substring(2) : text;
    if (thesis.trimLeft().startsWith(breakingLabel)) entries.add(text);
    current.clear();
  }

  for (final line in section.split('\n')) {
    if (line.trim().isEmpty || line.startsWith('- ')) flush();
    if (line.trim().isNotEmpty) current.add(line.trim());
  }
  flush();
  return entries;
}

/// The subjects among [breaks] that no breaking entry of [section] names.
///
/// A name counts as named when it is written as code: `` `Device` ``,
/// `` `Device.draw` ``, `` `Device(` `` or `` `Device<T>` ``. A removed
/// library counts when its file name appears.
List<String> unnamedBreaks(Iterable<ApiChange> breaks, String section) {
  final text = breakingEntries(section).join('\n');
  return <String>{
    for (final c in breaks)
      if (c.bump == Bump.major)
        if (!_names(text, c.subject)) c.subject,
  }.toList()..sort();
}

bool _names(String text, String subject) {
  if (subject.contains(':')) {
    return text.contains(subject.split('/').last);
  }
  return RegExp('`${RegExp.escape(subject)}[`.(<]').hasMatch(text);
}

// ----------------------------------------------------------- deprecation

/// The sentence a deprecation message ends with.
///
/// `@Deprecated('Use X instead. Deprecated in 1.0.0, removed in 2.0.0.')`.
/// The replacement is a sentence beginning `Use ` (or `No replacement`,
/// followed by why); the versions are the last sentence, in this order and
/// these words, so a script can find every deprecation due in a release.
final RegExp deprecationVersions = RegExp(
  r'Deprecated in (\d+\.\d+\.\d+), removed in (\d+\.\d+\.\d+)\.$',
);

/// What is wrong with a deprecation [message] in a package now at
/// [current], or null when nothing is.
String? deprecationProblem(String message, Version current) {
  final m = deprecationVersions.firstMatch(message.trim());
  if (m == null) {
    return 'does not end "Deprecated in X.Y.Z, removed in N.0.0."';
  }
  if (!RegExp(r'(^|\. )(Use |No replacement)').hasMatch(message)) {
    return 'names no replacement: say "Use …." or "No replacement: why."';
  }
  final since = parseVersion(m.group(1)!)!;
  final removed = parseVersion(m.group(2)!)!;
  if (removed.minor != 0 || removed.patch != 0) {
    return 'is removed in ${m.group(2)}, which is not a major release';
  }
  if (removed.major <= since.major) {
    return 'is removed in ${m.group(2)}, before the next major after '
        '${m.group(1)}';
  }
  if (compareVersions(current, removed) >= 0) {
    return 'was due for removal in ${m.group(2)} and the package is at '
        '${current.major}.${current.minor}.${current.patch}';
  }
  return null;
}

/// Every `@Deprecated(…)` in [source], as (line, message or null when the
/// argument is not a string literal), plus every bare `@deprecated`, which
/// carries no message at all.
List<({int line, String? message})> deprecationsIn(String source) {
  final found = <({int line, String? message})>[];
  final lines = source.split('\n');
  final offsets = <int>[];
  var at = 0;
  for (final l in lines) {
    offsets.add(at);
    at += l.length + 1;
  }
  int lineOf(int offset) {
    var i = 0;
    while (i + 1 < offsets.length && offsets[i + 1] <= offset) {
      i++;
    }
    return i + 1;
  }

  final code = lines
      .map((String l) => l.trimLeft().startsWith('//') ? ' ' * l.length : l)
      .join('\n');
  for (final match in RegExp(r'@Deprecated\(').allMatches(code)) {
    final open = match.end - 1;
    final close = _closing(code, open);
    found.add((
      line: lineOf(match.start),
      message: _stringLiterals(code.substring(open + 1, close)),
    ));
  }
  for (final match in RegExp(r'@deprecated\b').allMatches(code)) {
    found.add((line: lineOf(match.start), message: null));
  }
  return found;
}

/// The value of adjacent string literals, or null when [text] is anything
/// else.
String? _stringLiterals(String text) {
  final literal = RegExp(
    r"""\s*(r?)('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")\s*,?""",
  );
  final out = StringBuffer();
  var at = 0;
  while (at < text.length) {
    final m = literal.matchAsPrefix(text, at);
    if (m == null) {
      return text.substring(at).trim().isEmpty ? out.toString() : null;
    }
    final body = m.group(2)!.substring(1, m.group(2)!.length - 1);
    out.write(
      m.group(1)!.isNotEmpty
          ? body
          : body.replaceAllMapped(RegExp(r'\\(.)'), (Match e) => e.group(1)!),
    );
    at = m.end;
  }
  return out.toString();
}

// ------------------------------------------------- the shape of a type

/// Every type a snapshot declares as an `interface class`, abstract or not,
/// once each however many of its libraries declare it.
///
/// Decision 5 of `tasks/1.0-api-review.md`: a type somebody outside
/// implements is an `abstract base class` with default bodies, because a
/// member added to an interface in a minor release breaks every one of its
/// implementations, and a member added to a base class with a body breaks
/// none.
Set<String> interfaceClassesIn(String snapshot) => <String>{
  for (final library in parseApi(snapshot).values)
    for (final entry in library.declarations.entries)
      if (_isInterfaceClass(splitAnnotations(entry.value.header).rest))
        entry.key,
};

bool _isInterfaceClass(String bare) {
  final m = _modifiers(bare);
  return m.contains('interface') &&
      bare.split(' ').skip(m.length).firstOrNull == 'class';
}

/// Every type a snapshot declares as an `enum` or a `sealed` class, with
/// which of the two it is, once each however many of its libraries declare
/// it.
///
/// These are the closed sets: a value added to an enum, or a subtype added
/// to a sealed class, breaks every exhaustive `switch` written against it,
/// so neither can grow in a minor release.
Map<String, String> closedSetsIn(String snapshot) => <String, String>{
  for (final library in parseApi(snapshot).values)
    for (final entry in library.declarations.entries)
      entry.key: ?_closedSetKind(splitAnnotations(entry.value.header).rest),
};

String? _closedSetKind(String bare) {
  if (bare.startsWith('enum ')) return 'enum';
  final m = _modifiers(bare);
  if (m.contains('sealed') &&
      bare.split(' ').skip(m.length).firstOrNull == 'class') {
    return 'sealed';
  }
  return null;
}

/// Every type a snapshot declares, with the names it extends, implements and
/// mixes in, without their type arguments.
Map<String, Set<String>> supertypesIn(String snapshot) {
  final out = <String, Set<String>>{};
  for (final library in parseApi(snapshot).values) {
    for (final entry in library.declarations.entries) {
      final bare = splitAnnotations(entry.value.header).rest;
      if (!RegExp(r'^(?:\w+\s+)*class\s').hasMatch(bare)) continue;
      (out[entry.key] ??= <String>{}).addAll(_supertypes(bare));
    }
  }
  return out;
}

/// The exception types `dart:core`, `dart:async` and `dart:io` declare: a
/// type that reaches one of these is an exception.
const Set<String> kSdkExceptions = <String>{
  'Exception',
  'FormatException',
  'IOException',
  'TimeoutException',
  'FileSystemException',
  'HttpException',
  'SocketException',
  'IsolateSpawnException',
  'DeferredLoadException',
};

/// Each exception in [hierarchy] (from [supertypesIn], over every snapshot)
/// that breaks decision 4 of `tasks/1.0-api-review.md`, with why: one that
/// does not reach [root], one named `…Error`, which is kept for `Error`, or
/// (decision H) one under [root] not named `…Exception` — a `…Refused`, a
/// `…Failure`, a `…Trap` — unless [namedOtherwise] lists it.
///
/// [root] itself is the one type allowed to implement `Exception` directly.
List<(String, String)> exceptionsOutsideTheRoot(
  Map<String, Set<String>> hierarchy, {
  String root = 'Flutter3dException',
  Set<String> namedOtherwise = const <String>{},
}) {
  final isException = <String, bool>{};
  final reachesRoot = <String, bool>{};
  bool walk(String type, Map<String, bool> memo, bool Function(String) hit) {
    if (memo[type] case final known?) return known;
    memo[type] = false; // a cycle in a broken snapshot answers no
    final answer =
        hit(type) ||
        (hierarchy[type] ?? const <String>{}).any(
          (String s) => walk(s, memo, hit),
        );
    return memo[type] = answer;
  }

  return <(String, String)>[
    for (final type in hierarchy.keys.toList()..sort())
      if (walk(
        type,
        isException,
        kSdkExceptions.contains,
      )) ...<(String, String)>[
        if (!walk(type, reachesRoot, (String t) => t == root))
          (
            type,
            'is an exception that does not extend $root: catch-all code that '
                'reports what the engine refused never sees it. Extend one of '
                'the families in flutter3d_plugin_api (Flutter3dFormatException, '
                'CapabilityException, PluginException, ResourceException)',
          ),
        if (type.endsWith('Error'))
          (
            type,
            'is an exception named like an Error. `…Error` is kept for '
                'programmer mistakes that extend Error; name it `…Exception`',
          )
        else if (!type.endsWith('Exception') &&
            !namedOtherwise.contains(type) &&
            walk(type, reachesRoot, (String t) => t == root))
          (
            type,
            'is an exception not named `…Exception` (decision H): a type that '
                'is thrown says so in its name, so `on …Exception` reads as '
                'what it catches. Rename it, with a rename migration',
          ),
      ],
  ];
}

// ----------------------------------------------------------------- proofs

/// The proof that every detector in this file fires on what breaks its rule
/// and stays quiet on what only looks like it, as (detector, what went
/// wrong). Empty when all of them work. `proveDetectorsWork` runs it first.
///
/// The fixtures are invented names on purpose: the snapshots are real files
/// the rules read, and a proof written against one would be a claim about it.
List<(String, String)> proveApiDetectorsWork() {
  final broken = <(String, String)>[];
  const lib = 'library package:p/p.dart\n';
  Bump verdict(String before, String after) =>
      requiredBump(classifyApi('$lib\n$before', '$lib\n$after'));
  void expect(String what, Bump got, Bump want, String fixture) {
    if (got != want) broken.add((what, 'said ${got.name} for $fixture'));
  }

  // Breaks.
  expect(
    'api classifier',
    verdict('final class Ab\n', ''),
    Bump.major,
    'a declaration removed',
  );
  expect(
    'api classifier',
    verdict(
      'abstract interface class Ab\n  void f()\n',
      'abstract interface class Ab\n  void f()\n  void g()\n',
    ),
    Bump.major,
    'a member added to an interface outside code implements',
  );
  expect(
    'api classifier',
    verdict(
      'abstract base class Ab\n  void f()\n',
      'abstract base class Ab\n  abstract void g()\n  void f()\n',
    ),
    Bump.major,
    'a bodiless member added to a base class outside code extends',
  );
  expect(
    'api classifier',
    verdict('class Ab\n', 'final class Ab\n'),
    Bump.major,
    'a class made final',
  );
  expect(
    'api classifier',
    requiredBump(
      classifyApi(
        'library package:p/internal.dart\n\nfinal class Ab\n  void f()\n',
        'library package:p/internal.dart\n\nfinal class Ab\n',
      ),
    ),
    Bump.minor,
    'a member gone from a library outside semver, which a minor may change',
  );
  expect(
    'api classifier',
    verdict(
      'final class Ab\n  Ab(Sink<String> this._s)\n',
      'final class Ab\n  Ab(Sink<int> this._s)\n',
    ),
    Bump.major,
    'the type of a private field a constructor sets changed',
  );
  expect(
    'api classifier',
    verdict(
      'final class Ab\n  Ab(this._s, {required this.n})\n',
      'final class Ab\n  Ab(Map<String, int> this._s, {required this.n})\n',
    ),
    Bump.none,
    'a snapshot from before private formals carried their type, against one '
        'after',
  );
  expect(
    'api classifier',
    verdict('enum Ab\n  values: x, y\n', 'enum Ab\n  values: x, y, z\n'),
    Bump.major,
    'an enum value added: a switch over it is no longer exhaustive',
  );
  expect(
    'api classifier',
    verdict(
      'sealed class Ab\n\nfinal class Cd extends Ab\n',
      'sealed class Ab\n\nfinal class Cd extends Ab\n\n'
          'final class Ef extends Ab\n',
    ),
    Bump.major,
    'a new subtype of a sealed class',
  );
  expect(
    'api classifier',
    verdict(
      'final class Ab\n  void f(int x)\n',
      'final class Ab\n  void f(int y)\n',
    ),
    Bump.major,
    'a parameter renamed',
  );
  expect(
    'api classifier',
    verdict(
      'final class Ab\n  void f()\n',
      'final class Ab\n  @visibleForTesting void f()\n',
    ),
    Bump.major,
    'a member made @visibleForTesting',
  );
  expect(
    'api classifier',
    verdict(
      'export package:q/q.dart (whole library)\n  Ab\n  Cd\n',
      'export package:q/q.dart (whole library)\n  Ab\n',
    ),
    Bump.major,
    'a re-exported name dropped',
  );
  expect(
    'api classifier',
    verdict(
      'base class Ab\n  void f({int x = 1})\n',
      'base class Ab\n  void f({int x = 1, int y = 2})\n',
    ),
    Bump.major,
    'an optional parameter added to a method outside code may override',
  );

  // Additions, and what moves nothing.
  expect(
    'api classifier',
    verdict(
      'final class Ab\n  void f()\n',
      'final class Ab\n  void f()\n  void g()\n',
    ),
    Bump.minor,
    'a member added to a final class',
  );
  expect(
    'api classifier',
    verdict(
      'abstract interface class Ab\n  void f()\n',
      'abstract interface class Ab\n  static const int k = 1\n  void f()\n',
    ),
    Bump.minor,
    'a static added to an interface: statics are not inherited',
  );
  expect(
    'api classifier',
    verdict(
      'final class Ab\n  void f(int a, {int x = 1})\n',
      'final class Ab\n  void f(int a, {int x = 1, int y = 2})\n',
    ),
    Bump.minor,
    'an optional parameter added to a method nobody outside overrides',
  );
  expect(
    'api classifier',
    verdict(
      'final class Ab\n  void f(int a, {int x = 1})\n',
      'final class Ab\n  void f(int a, {int x = 1, required int y})\n',
    ),
    Bump.major,
    'a required parameter added, which every caller has to pass',
  );
  expect(
    'api classifier',
    verdict(
      "final class Ab\n  @Deprecated('Old.') void f()\n",
      "final class Ab\n  @Deprecated('Reworded.') void f()\n",
    ),
    Bump.none,
    'a deprecation message reworded',
  );
  expect(
    'api classifier',
    verdict('final class Ab\n', '@immutable final class Ab\n'),
    Bump.none,
    '@immutable on a class nobody outside may extend',
  );
  expect(
    'api classifier',
    verdict(
      'const Map<String, int> table = …\n',
      'const Map<String, int> table = …\n',
    ),
    Bump.none,
    'a constant too long to list, on both sides',
  );
  expect(
    'api classifier',
    verdict('final class Ab\n', 'class Ab\n'),
    Bump.minor,
    'a final class opened up',
  );

  // Names, which every pairing of an old line with a new one rests on.
  const names = <String, String>{
    'set width(double value)': 'width=',
    'double get width': 'width',
    'bool operator ==(Object other)': 'operator ==',
    'const Ab.named({int x = (1 + 2)})': 'Ab.named',
    'static const Ab k = Ab(1, f: g(2))': 'k',
    '(int, int) pair<T>(T value)': 'pair',
    '@Deprecated(\'Use (x).\') void f()': 'f',
    'abstract void Function(int) get callback': 'callback',
  };
  for (final entry in names.entries) {
    final got = memberName(entry.key);
    if (got != entry.value) {
      broken.add(('api member names', 'read "${entry.key}" as "$got"'));
    }
  }

  // Versions.
  const v100 = (major: 1, minor: 0, patch: 0);
  if (bumpIsEnough(Bump.major, v100, (major: 1, minor: 1, patch: 0))) {
    broken.add(('api versions', 'called 1.1.0 enough for a break from 1.0.0'));
  }
  if (!bumpIsEnough(Bump.major, v100, (major: 2, minor: 0, patch: 0))) {
    broken.add(('api versions', 'refused 2.0.0 for a break from 1.0.0'));
  }
  if (bumpIsEnough(Bump.minor, v100, (major: 1, minor: 0, patch: 1))) {
    broken.add(('api versions', 'called a patch enough for an addition'));
  }
  if (!bumpIsEnough(
    Bump.major,
    (major: 0, minor: 9, patch: 0),
    (major: 0, minor: 10, patch: 0),
  )) {
    broken.add(('api versions', 'refused 0.10.0 for a break from 0.9.0'));
  }

  // Pre-releases, in semver's order: read as their three numbers they were
  // the release they precede, so a `^1.0.0` looked like it admitted
  // `1.0.0-rc.1` and `v1.0.0-rc.1` tied with `v1.0.0` as the newest tag.
  for (final (lower, higher) in const <(String, String)>[
    ('1.0.0-rc.1', '1.0.0'),
    ('0.9.0', '1.0.0-rc.1'),
    ('1.0.0-rc.1', '1.0.0-rc.2'),
    ('1.0.0-rc.9', '1.0.0-rc.10'),
    ('1.0.0-rc', '1.0.0-rc.1'),
    ('1.0.0-1', '1.0.0-rc'),
  ]) {
    if ((compareVersionTexts(lower, higher) ?? 0) >= 0 ||
        (compareVersionTexts(higher, lower) ?? 0) <= 0) {
      broken.add(('pre-release order', 'did not put $lower below $higher'));
    }
  }
  if (compareVersionTexts('1.0.0+1', '1.0.0') != 0) {
    broken.add(('pre-release order', 'read a build number as a pre-release'));
  }
  for (final (asked, declared, admits) in const <(String, String, bool)>[
    ('1.0.0-rc.1', '1.0.0-rc.1', true),
    ('1.0.0-rc.1', '1.0.0', true),
    ('1.0.0-rc.1', '1.4.2', true),
    ('1.0.0', '1.0.0-rc.1', false),
    ('1.0.0-rc.1', '2.0.0', false),
    ('0.4.0', '0.4.1', true),
    ('0.4.0', '0.5.0', false),
    ('1.2.0', '1.1.9', false),
  ]) {
    if (caretAdmits(asked, declared) != admits) {
      broken.add((
        'caret',
        '${admits ? 'refused' : 'admitted'} $declared under ^$asked',
      ));
    }
  }
  if (!bumpIsEnoughFrom(Bump.major, '1.0.0-rc.1', '1.0.0')) {
    broken.add(('api versions', 'refused 1.0.0 for a break from 1.0.0-rc.1'));
  }
  if (bumpIsEnoughFrom(Bump.minor, '1.0.0-rc.1', '1.0.0-rc.1')) {
    broken.add(('api versions', 'called an unmoved pre-release enough'));
  }
  if (bumpIsEnoughFrom(Bump.major, '1.0.0', '1.1.0')) {
    broken.add(('api versions', 'called 1.1.0 enough for a break from 1.0.0'));
  }

  // The CHANGELOG label.
  const section =
      '\n- **Breaking: `Ab.f` takes a count.** Callers pass one.\n\n'
      '- **Not breaking: `Cd` is new.**\n\n'
      '**Breaking:** `Ef` is gone; use\n  `Gh`.\n';
  final breaks = <ApiChange>[
    const ApiChange('package:p/p.dart', 'Ab', 'changed', Bump.major),
    const ApiChange('package:p/p.dart', 'Ef', 'gone', Bump.major),
    const ApiChange('package:p/p.dart', 'Cd', 'gone', Bump.major),
  ];
  final unnamed = unnamedBreaks(breaks, section);
  if (unnamed.length != 1 || unnamed.single != 'Cd') {
    broken.add((
      'changelog label',
      'found $unnamed unnamed, where only `Cd` is outside a Breaking entry',
    ));
  }
  if (breakingEntries('\n- **Fixed:** a break in the loader.\n').isNotEmpty) {
    broken.add(('changelog label', 'read the word "break" as the label'));
  }

  // Deprecations.
  const v090 = (major: 0, minor: 9, patch: 0);
  const good = 'Use g(). Deprecated in 1.0.0, removed in 2.0.0.';
  if (deprecationProblem(good, v090) != null) {
    broken.add(('deprecation message', 'refused "$good"'));
  }
  for (final bad in <String>[
    'Use g() instead.',
    'Deprecated in 1.0.0, removed in 2.0.0.',
    'Use g(). Deprecated in 1.0.0, removed in 1.5.0.',
    'Use g(). Deprecated in 1.0.0, removed in 1.0.0.',
  ]) {
    if (deprecationProblem(bad, v090) == null) {
      broken.add(('deprecation message', 'accepted "$bad"'));
    }
  }
  if (deprecationProblem(good, (major: 2, minor: 0, patch: 0)) == null) {
    broken.add(('deprecation message', 'accepted one overdue for removal'));
  }
  final found = deprecationsIn(
    "/// Not this: @Deprecated('x')\n"
    'class Ab {\n'
    '  @Deprecated(\n'
    "    'Use g(). '\n"
    "    'Deprecated in 1.0.0, removed in 2.0.0.',\n"
    '  )\n'
    '  void f() {}\n'
    '  @deprecated\n'
    '  void h() {}\n'
    '}\n',
  );
  if (found.length != 2 ||
      found.first.line != 3 ||
      found.first.message != good ||
      found.last.message != null) {
    broken.add((
      'deprecation scan',
      'read $found from one dated deprecation, one bare @deprecated and a '
          'doc comment',
    ));
  }

  // Hooks that take a list. The traps are the four headers a hook can have
  // besides `abstract base class`, a callback a factory takes, a typedef, a
  // deprecated method, and the shapes that are fine: one parameter, a
  // getter, a callback of one, a final class, a record typedef. Mutation:
  // drop `isHookHeader`'s mixin arms and the mixin classes and the mixins
  // go quiet; drop the function-type scan and the factory and the typedef
  // do.
  final hooks = wideHooksIn(
    '${lib}abstract base class Ab\n'
    '  abstract void f(int a, int b)\n'
    '  abstract void g(int a)\n'
    '  int get h\n'
    '  const factory Ab.of({required int Function(Object? d, int v) read, void Function(int a) one})\n'
    '  @Deprecated(\'x\') void old(int a, {int b})\n'
    'abstract base mixin class Cd\n'
    '  void e(int a, int b, int c)\n'
    'base mixin Ef\n'
    '  void k(int a, [int b])\n'
    '  void spawn(void Function(Object w, int e) build)\n'
    'abstract mixin class Op\n'
    '  void q(int a, int b)\n'
    'mixin Rs on Ab\n'
    '  bool t(int a, int b)\n'
    'final class Gh\n'
    '  void m(int a, int b)\n'
    '  void each(void Function(int a, int b) visit)\n'
    '  const Gh({this.on, required void Function(Map<String, Object?> a) run})\n'
    '  final void Function(int a, int b)? on\n'
    '  final void Function(OpContext c)? fine\n'
    'typedef Ij = void Function(int a, int b)\n'
    'typedef Kl = void Function(int a)\n'
    'typedef Mn = ({int a, int b})\n'
    'abstract base class Pq\n'
    '  abstract void c(PqContext context)\n'
    '  abstract void s(List<String> names)\n',
  );
  final wide = <String>{
    for (final w in hooks.wide)
      w.member.isEmpty ? w.type : '${w.type}.${w.member}',
  };
  const fires = <String>{
    'Ab.f',
    'Ab.of',
    'Ab.old',
    'Cd.e',
    'Ef.k',
    'Ef.spawn',
    'Op.q',
    'Rs.t',
    'Ij',
    'Gh.on',
  };
  for (final name in fires.difference(wide)) {
    broken.add(('hook shape', 'did not fire on $name: read $wide'));
  }
  for (final name in wide.difference(fires)) {
    broken.add((
      'hook shape',
      'fired on $name, which takes one parameter, is no method, is no hook '
          'or is a final class\'s method',
    ));
  }
  if (!hooks.seen.containsAll(<String>{'Ab', 'Ab.g', 'Cd', 'Ef', 'Kl'}) ||
      hooks.seen.contains('Gh')) {
    broken.add((
      'hook shape',
      'saw ${hooks.seen}, where every hook, its methods and every typedef '
          'are seen and a final class is not',
    ));
  }
  // One value, not a context. Mutation: read every one-parameter hook as
  // fine again, and `Ab.g`, `Kl`, `Gh.run` and `Pq.s` go quiet; read a
  // context's name as a value, and `Pq.c` and `Gh.fine` fire.
  final values = <String>{
    for (final v in hooks.value)
      v.member.isEmpty ? v.type : '${v.type}.${v.member}',
  };
  const valued = <String>{'Ab.g', 'Kl', 'Gh.run', 'Pq.s', 'Ab.of'};
  if (!values.containsAll(valued) || values.length != valued.length) {
    broken.add((
      'hook values',
      'read $values, where $valued are handed one value and a context or a '
          'method of a final class is not',
    ));
  }

  // Interfaces. Mutation: drop the `interface` test and every base class is
  // reported; match the word anywhere and a member named `interfaceName` is.
  final interfaces = interfaceClassesIn(
    '${lib}abstract interface class Ab\n  void f()\n'
    'interface class Cd\n'
    'abstract base class Ef\n  String get interfaceName\n'
    'sealed class Gh\n'
    'library package:p/q.dart\nabstract interface class Ab\n',
  );
  if (!interfaces.containsAll(<String>{'Ab', 'Cd'})) {
    broken.add((
      'interface classes',
      'missed one of an abstract and a plain interface class: $interfaces',
    ));
  }
  if (interfaces.length != 2) {
    broken.add((
      'interface classes',
      'found $interfaces, where a base class, a sealed class and a member '
          'named interfaceName are not interfaces and a name declared in two '
          'libraries is one type',
    ));
  }

  // Closed sets. Mutation: drop the `class` test and a `sealed mixin` is
  // reported; match `sealed` anywhere and a member named `sealedAt` is; read
  // `enum` without the space and `enumerate` is.
  final closedSets = closedSetsIn(
    '${lib}enum Ab\n  values: a, b\n'
    'sealed class Cd\n'
    'abstract base class Ef\n  bool get sealedAt\n'
    'final class Gh\n  static const List<Gh> values\n'
    'sealed mixin Ij\n'
    'enumerate Kl\n'
    'library package:p/q.dart\nenum Ab\n  values: a, b\n',
  );
  if (closedSets.length != 2 ||
      closedSets['Ab'] != 'enum' ||
      closedSets['Cd'] != 'sealed') {
    broken.add((
      'closed sets',
      'found $closedSets, where only an enum and a sealed class are closed '
          'sets, a class with constants and a base class are not, and a '
          'name declared in two libraries is one type',
    ));
  }

  // Exceptions. The traps are the chain (a leaf two steps below the root),
  // an SDK exception that is not `Exception` itself, and an `Error` that is
  // not an exception at all.
  final outside = exceptionsOutsideTheRoot(
    supertypesIn(
      '${lib}abstract base class Flutter3dException implements Exception\n'
      'abstract base class Flutter3dFormatException extends Flutter3dException\n'
      'final class GoodException extends Flutter3dFormatException\n'
      'final class LooseException implements Exception\n'
      'final class ParseException extends FormatException\n'
      'final class OddError extends Flutter3dFormatException\n'
      'final class FineError extends Error\n'
      'final class Plain<T extends Object>\n'
      'final class LevelRefused extends Flutter3dFormatException\n'
      'final class KnownTrap extends Flutter3dFormatException\n',
    ),
    namedOtherwise: const <String>{'KnownTrap'},
  );
  final flagged = <String>{for (final (name, _) in outside) name};
  for (final name in <String>[
    'LooseException',
    'ParseException',
    'OddError',
    'LevelRefused',
  ]) {
    if (!flagged.contains(name)) {
      broken.add(('exception root', 'did not fire on $name'));
    }
  }
  for (final name in <String>[
    'Flutter3dException',
    'Flutter3dFormatException',
    'GoodException',
    'FineError',
    'Plain',
    'KnownTrap',
  ]) {
    if (flagged.contains(name)) {
      broken.add((
        'exception root',
        'fired on $name, which is the root, under it, or not an exception',
      ));
    }
  }

  // The plugin API's number. The traps are a registry in another package
  // (read), another type there (not read), and the number itself. Mutation:
  // read every change of every package, and the new `Ab` of `q` counts;
  // read no registry outside `whole`, and `Cd`'s new member does not.
  final grown = pluginApiChanges(
    released: <String, String>{
      'p':
          '${lib}final class PluginApiVersion\n'
          '  static const PluginApiVersion current = PluginApiVersion(1, 0)\n',
      'q': '${lib}abstract base class Cd extends PluginRegistry\n  void a()\n',
    },
    current: <String, String>{
      'p':
          '${lib}final class PluginApiVersion\n'
          '  static const PluginApiVersion current = PluginApiVersion(1, 0)\n'
          'final class Ef\n',
      'q':
          '${lib}abstract base class Cd extends PluginRegistry\n  void a()\n'
          '  void b()\nfinal class Ab\n',
    },
    whole: const <String>{'p'},
  );
  final grownNames = <String>{for (final c in grown) c.subject};
  if (!grownNames.containsAll(<String>{'Ef', 'Cd'}) ||
      grownNames.contains('Ab')) {
    broken.add((
      'plugin API growth',
      'read $grownNames, where a new type of a whole package and a registry '
          'elsewhere grew and another type elsewhere does not count',
    ));
  }
  if (pluginApiVersionIn(
        '${lib}final class PluginApiVersion\n'
        '  static const PluginApiVersion current = PluginApiVersion(1, 2)\n',
      ) !=
      '1.2') {
    broken.add(('plugin API growth', 'did not read `current` as 1.2'));
  }
  return broken;
}

/// The name and the parameter count of [member], a member line of a
/// snapshot, when it is an instance method a subclass could override —
/// null for a getter, a setter, an operator, a constructor, a factory, a
/// static member or a field.
({String name, int parameters})? hookMethodIn(String member) {
  var line = member.trim();
  if (line.startsWith('static ') ||
      line.startsWith('factory ') ||
      line.startsWith('const ') ||
      line.startsWith('final ') ||
      line.startsWith('late ') ||
      line.startsWith('external ') ||
      line.startsWith('@')) {
    return null;
  }
  if (line.startsWith('abstract ')) line = line.substring('abstract '.length);
  final open = line.indexOf('(');
  if (open < 0) return null;
  var head = line.substring(0, open).trim();
  // A generic method's type parameters, `register<T extends Object>`, are
  // not part of its name.
  if (head.endsWith('>')) {
    var depth = 0;
    for (var i = head.length - 1; i >= 0; i--) {
      if (head[i] == '>') depth++;
      if (head[i] == '<') depth--;
      if (depth == 0) {
        head = head.substring(0, i).trim();
        break;
      }
    }
  }
  if (head.contains(' get ') ||
      head.contains(' set ') ||
      head.startsWith('set ') ||
      head.contains('operator')) {
    return null;
  }
  final words = head.split(RegExp(r'\s+'));
  // A constructor has no return type: its head is its class's name alone.
  if (words.length < 2) return null;
  final name = words.last;
  // The parameter list, to its matching close.
  var depth = 0;
  var close = -1;
  for (var i = open; i < line.length; i++) {
    final c = line[i];
    if (c == '(' || c == '[' || c == '{' || c == '<') depth++;
    if (c == ')' || c == ']' || c == '}' || c == '>') depth--;
    if (depth == 0) {
      close = i;
      break;
    }
  }
  if (close < 0) return null;
  return (
    name: name,
    parameters: _parameterCount(line.substring(open + 1, close)),
  );
}

/// The number of parameters in [inside], the text between a parameter
/// list's parentheses.
int _parameterCount(String inside) {
  // Parameters at the top level, the `{` and `[` that open the optional
  // ones read as a group rather than as a nesting: a brace that starts a
  // slot is the group's, one inside a default value is the value's.
  var count = 0;
  var depth = 0;
  var group = false;
  final token = StringBuffer();
  for (var i = 0; i < inside.length; i++) {
    final c = inside[i];
    if (depth == 0 &&
        !group &&
        (c == '{' || c == '[') &&
        token.toString().trim().isEmpty) {
      group = true;
      continue;
    }
    if (depth == 0 && group && (c == '}' || c == ']')) {
      group = false;
      continue;
    }
    if ('(<{['.contains(c)) depth++;
    if (')>}]'.contains(c)) depth--;
    if (c == ',' && depth == 0) {
      if (token.toString().trim().isNotEmpty) count++;
      token.clear();
      continue;
    }
    token.write(c);
  }
  if (token.toString().trim().isNotEmpty) count++;
  return count;
}

/// The parameter count of every function type written in [text], a
/// snapshot line, in the order they appear: `T? Function(Object? data, int
/// version)` is 2, and a function type nested in another's parameters is
/// counted too.
List<int> functionTypeArities(String text) => <int>[
  for (final f in functionTypesIn(text)) f.parameters,
];

/// Every function type written in [text], a snapshot line, in the order
/// they appear: its parameter count, the type of its parameter when it has
/// exactly one (null otherwise), and the name it is declared under, the
/// field, getter or parameter that holds it (`''` where nothing names it, a
/// return type or a type argument).
List<({int parameters, String? only, String name})> functionTypesIn(
  String text,
) {
  final found = <({int parameters, String? only, String name})>[];
  for (final match in RegExp(r'(?<![\w$])Function\s*\(').allMatches(text)) {
    final open = match.end - 1;
    final close = _closingOf(text, open);
    if (close < 0) continue;
    final inside = text.substring(open + 1, close);
    final parameters = _parameterCount(inside);
    found.add((
      parameters: parameters,
      only: parameters == 1 ? parameterTypeOf(inside) : null,
      name: _nameAfter(text, close + 1),
    ));
  }
  return found;
}

/// The index of the bracket that closes the one at [open] in [text], or -1.
int _closingOf(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    final c = text[i];
    if ('(<{['.contains(c)) depth++;
    if (')>}]'.contains(c)) depth--;
    if (depth == 0) return i;
  }
  return -1;
}

/// The name declared after a function type that ends before [from]: the
/// next identifier, past a `?`, a `get` and any function type the first one
/// is the return type of. `''` where a `,`, a `)` or a `>` comes first.
String _nameAfter(String text, int from) {
  var i = from;
  while (i < text.length) {
    final c = text[i];
    if (c == '?' || c == ' ') {
      i++;
      continue;
    }
    final word = RegExp(r'^[A-Za-z_$][\w$]*').stringMatch(text.substring(i));
    if (word == null) return '';
    if (word == 'Function') {
      final open = text.indexOf('(', i);
      final close = open < 0 ? -1 : _closingOf(text, open);
      if (close < 0) return '';
      i = close + 1;
      continue;
    }
    if (word == 'get') {
      i += word.length;
      continue;
    }
    // A constructor's `this._name` is a private named parameter: a caller
    // passes it as `name`.
    if (word == 'this' && text.startsWith('.', i + word.length)) {
      final field = RegExp(
        r'^[A-Za-z_$][\w$]*',
      ).stringMatch(text.substring(i + word.length + 1));
      if (field == null) return '';
      return field.startsWith('_') ? field.substring(1) : field;
    }
    return word;
  }
  return '';
}

/// The type of the one parameter written in [inside], the text between a
/// parameter list's parentheses: `Map<String, Object?>` for `Map<String,
/// Object?> arguments`, `int` for a bare `int`, `Foo` for `{required Foo
/// foo}`. A default value and the `?` of a nullable type are dropped.
String parameterTypeOf(String inside) {
  var text = inside.trim();
  if (text.startsWith('{') || text.startsWith('[')) {
    text = text.substring(1, text.length - 1).trim();
  }
  final assign = text.indexOf('=');
  if (assign >= 0) text = text.substring(0, assign).trim();
  text = text.replaceFirst(RegExp(r'^(required|covariant)\s+'), '');
  if (text.startsWith('this.') || text.startsWith('super.')) return text;
  // The name is the last word at the top level; a type written alone, as a
  // function type's parameters may be, is all type.
  var depth = 0;
  var lastSpace = -1;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if ('(<{['.contains(c)) depth++;
    if (')>}]'.contains(c)) depth--;
    if (c == ' ' && depth == 0) lastSpace = i;
  }
  final type = lastSpace < 0 ? text : text.substring(0, lastSpace).trim();
  return type.endsWith('?') ? type.substring(0, type.length - 1) : type;
}

/// Whether [type], a parameter's type as [parameterTypeOf] reads it, is a
/// value that cannot gain members: a number, a string, a flag, a
/// collection, bytes, a vector, `Object`, a type parameter, a record or a
/// function. A hook handed one of these can never be handed more without a
/// second parameter, where a type of the engine's own (`LoopContext`,
/// `Activation`, `Mind`) grows by members.
bool isValueParameterType(String type) {
  final bare = type.trim();
  if (bare.startsWith('(') || bare.contains('Function')) return true;
  final name = RegExp(r'^[\w$]+').stringMatch(bare) ?? bare;
  return _valueTypeNames.contains(name) || RegExp(r'^[A-Z]$').hasMatch(name);
}

const Set<String> _valueTypeNames = <String>{
  'int',
  'double',
  'num',
  'bool',
  'String',
  'Object',
  'dynamic',
  'List',
  'Map',
  'Set',
  'Iterable',
  'Uint8List',
  'Uint16List',
  'Uint32List',
  'Int32List',
  'Float32List',
  'Float64List',
  'ByteData',
  'Duration',
  'DateTime',
  'Uri',
  'Vector2',
  'Vector3',
  'Vector4',
  'Matrix3',
  'Matrix4',
  'Quaternion',
  'Aabb3',
};

/// Whether [header], a snapshot's declaration line, declares a type an
/// outside author extends or mixes in: an `abstract base class`, an
/// `abstract base mixin class`, an `abstract mixin class`, a `base mixin`
/// or a `mixin`.
bool isHookHeader(String header) =>
    header.startsWith('abstract base class ') ||
    header.startsWith('abstract base mixin class ') ||
    header.startsWith('abstract mixin class ') ||
    header.startsWith('base mixin ') ||
    header.startsWith('mixin ');

/// The name a member line declares: `spawn` for `void spawn(...)`, `of` for
/// `const factory SnapshotPart.of(...)`, the class's own name for its
/// unnamed constructor.
String memberNameIn(String member) {
  var head = splitAnnotations(member).rest;
  final open = head.indexOf('(');
  if (open >= 0) head = head.substring(0, open);
  head = head.trim();
  if (head.endsWith('>')) {
    var depth = 0;
    for (var i = head.length - 1; i >= 0; i--) {
      if (head[i] == '>') depth++;
      if (head[i] == '<') depth--;
      if (depth == 0) {
        head = head.substring(0, i).trim();
        break;
      }
    }
  }
  final last = head.split(RegExp(r'\s+')).last;
  return last.contains('.') ? last.substring(last.lastIndexOf('.') + 1) : last;
}

/// Whether [member], a member line of a class an outside author does not
/// extend, can hold a callback an outside author writes: a constructor or
/// a factory, whose parameters a caller fills, or a field or getter of a
/// function type. A method's own callback parameters are the engine's to
/// call back with; they are not read.
bool holdsCallback(String member) {
  var line = splitAnnotations(member).rest;
  for (final word in <String>[
    'static ',
    'external ',
    'covariant ',
    'late ',
    'final ',
    'const ',
  ]) {
    if (line.startsWith(word)) line = line.substring(word.length);
  }
  if (line.startsWith('factory ')) return true;
  final open = line.indexOf('(');
  if (open < 0) return false;
  var head = line.substring(0, open).trim();
  if (head.endsWith('>')) {
    var depth = 0;
    for (var i = head.length - 1; i >= 0; i--) {
      if (head[i] == '>') depth++;
      if (head[i] == '<') depth--;
      if (depth == 0) {
        head = head.substring(0, i).trim();
        break;
      }
    }
  }
  final words = head.split(RegExp(r'\s+'));
  return words.length == 1 || words.last == 'Function';
}

/// Every place [snapshot] hands an outside author a list of parameters,
/// and every place it hands one a single value:
///
/// - [wide]: a method of a hook type ([isHookHeader]) that takes more than
///   one parameter, and a function type with more than one in any member of
///   a hook type (the `decode` of `ComponentCodec.of`, the callback of a
///   `spawn`), in a public typedef, or in a field, getter or constructor of
///   any other class (`OfferedTool.run`, a listener's `overTime`).
/// - [value]: the same places taking exactly one parameter, where that
///   parameter is a value that cannot gain members
///   ([isValueParameterType]): `PluginSource.read(String)`, a callback of a
///   bare `Map`.
///
/// A hook type's member is keyed by its type and member name; a callback
/// another class holds by its type and the field, getter or parameter
/// holding it; a typedef by its name. [seen] is every key either list
/// could name, so an allowance that names nothing can be told apart.
({
  Set<String> seen,
  List<({String type, String member, int parameters, bool callback})> wide,
  List<({String type, String member, String parameter, bool callback})> value,
})
wideHooksIn(String snapshot) {
  final seen = <String>{};
  final wide =
      <({String type, String member, int parameters, bool callback})>[];
  final value =
      <({String type, String member, String parameter, bool callback})>[];
  // [keyedBy] names every callback of [member] where it is given (`''` for
  // the type alone), and each callback's own field, getter or parameter
  // names it where it is not.
  void callbacks(String type, String member, {String? keyedBy}) {
    for (final f in functionTypesIn(member)) {
      final name = keyedBy ?? f.name;
      final key = name.isEmpty ? type : '$type.$name';
      if (f.parameters > 1) {
        seen.add(key);
        wide.add((
          type: type,
          member: name,
          parameters: f.parameters,
          callback: true,
        ));
      } else if (f.only case final only? when isValueParameterType(only)) {
        seen.add(key);
        value.add((type: type, member: name, parameter: only, callback: true));
      }
    }
  }

  for (final library in parseApi(snapshot).values) {
    for (final MapEntry(key: name, value: block)
        in library.declarations.entries) {
      final header = block.header;
      if (header.startsWith('typedef ')) {
        seen.add(name);
        // A typedef's own function type, and the callbacks it takes, are
        // all keyed by its name.
        callbacks(name, header, keyedBy: '');
        continue;
      }
      if (isHookHeader(header)) {
        seen.add(name);
        for (final member in block.members) {
          final rest = splitAnnotations(member).rest;
          final method = hookMethodIn(rest);
          if (method != null && method.name != 'Function') {
            seen.add('$name.${method.name}');
            if (method.parameters > 1) {
              wide.add((
                type: name,
                member: method.name,
                parameters: method.parameters,
                callback: false,
              ));
            } else if (method.parameters == 1) {
              final open = rest.indexOf('(');
              final close = _closingOf(rest, open);
              final only = parameterTypeOf(rest.substring(open + 1, close));
              // A function it takes is read below, as a callback.
              if (isValueParameterType(only) && !only.contains('Function')) {
                value.add((
                  type: name,
                  member: method.name,
                  parameter: only,
                  callback: false,
                ));
              }
            }
          }
          // A hook type's callbacks are keyed by the member taking them,
          // as `ComponentCodec.of`; a field's by the field.
          final taking = memberNameIn(member);
          callbacks(
            name,
            member,
            keyedBy: taking == 'Function' ? null : taking,
          );
        }
        continue;
      }
      if (!RegExp(r'(^|\s)class\s').hasMatch(header)) continue;
      for (final member in block.members) {
        if (holdsCallback(member)) callbacks(name, member);
      }
    }
  }
  return (seen: seen, wide: wide, value: value);
}

// ------------------------------------------------------ the plugin API's number

/// `PluginApiVersion.current` as [snapshot], `flutter3d_plugin_api`'s,
/// declares it: `1.0`, or null where it declares none.
String? pluginApiVersionIn(String snapshot) => switch (RegExp(
  r'static const PluginApiVersion current = PluginApiVersion\((\d+), (\d+)\)',
).firstMatch(snapshot)) {
  final Match m => '${m[1]}.${m[2]}',
  null => null,
};

/// What grew, or broke, in the surface a plugin is written against between
/// [released] and [current], snapshots by package: every change in the
/// packages [whole] names, and elsewhere every change to a type a plugin is
/// handed from its host, a registry (`extends …Registry`), named in
/// [current]'s snapshot.
List<ApiChange> pluginApiChanges({
  required Map<String, String> released,
  required Map<String, String> current,
  required Set<String> whole,
}) {
  final changes = <ApiChange>[];
  for (final MapEntry(key: package, value: now) in current.entries) {
    final was = released[package];
    if (was == null) continue;
    final all = classifyApi(was, now).where((c) => c.bump != Bump.none);
    if (whole.contains(package)) {
      changes.addAll(all);
      continue;
    }
    final registries = <String>{
      for (final library in parseApi(now).values)
        for (final MapEntry(key: name, value: block)
            in library.declarations.entries)
          if (RegExp(r'\bextends\s+\w*Registry\b').hasMatch(block.header)) name,
    };
    changes.addAll(all.where((c) => registries.contains(c.subject)));
  }
  return changes;
}
