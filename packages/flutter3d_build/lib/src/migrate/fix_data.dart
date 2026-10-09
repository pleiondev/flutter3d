/// `lib/fix_data.yaml` for each package, written from the migration tables:
/// the part of a migration `dart fix` can carry out on its own.
///
/// **What it can carry.** A data-driven fix matches an element by its name,
/// its kind and the libraries it was reachable through, and applies changes
/// to every reference: a rename, a replacement by another element (whose
/// library it imports), a parameter added, removed or renamed. That is the
/// `rename`, `moved` and `parameters` kinds of a table. The kind and the
/// libraries are not in the table — they are in the release's API snapshot
/// (`tool/api/baseline/<tag>/`), which this reads, so an entry stays one
/// line of intent and the fix still names a `class` as a class.
///
/// **Where each transform goes.** In the package that declares the element
/// now — the new home of a moved name — so it reaches every project that can
/// see the element: the analyzer reads `fix_data.yaml` from every package a
/// project resolves.
library;

import 'table.dart';

/// One library of an API snapshot, as far as a fix needs it.
final class SnapshotLibrary {
  SnapshotLibrary(this.uri);
  final String uri;

  /// Declarations by name: (header, member lines).
  final Map<String, (String, List<String>)> declarations =
      <String, (String, List<String>)>{};

  /// Re-exports by URI: (header, admitted names).
  final Map<String, (String, List<String>)> exports =
      <String, (String, List<String>)>{};

  /// Whether [name] is reachable through this library.
  bool shows(String name) {
    if (declarations.containsKey(name)) return true;
    for (final (header, names) in exports.values) {
      if (names.contains(name)) return true;
      final show = RegExp(r' show ([\w$, ]+)').firstMatch(header);
      if (show != null &&
          show
              .group(1)!
              .split(',')
              .map((String s) => s.trim())
              .contains(name)) {
        return true;
      }
    }
    return false;
  }
}

/// A snapshot's libraries, by URI — the format `tool/api` writes.
Map<String, SnapshotLibrary> parseSnapshot(String text) {
  final out = <String, SnapshotLibrary>{};
  SnapshotLibrary? current;
  final lines = text
      .split('\n')
      .where((String l) => !l.startsWith('#'))
      .toList(growable: false);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.startsWith(' ')) continue;
    if (line.startsWith('library ')) {
      final uri = line.substring('library '.length).trim();
      current = out[uri] = SnapshotLibrary(uri);
      continue;
    }
    final members = <String>[
      for (var j = i + 1; j < lines.length && lines[j].startsWith('  '); j++)
        lines[j].substring(2),
    ];
    final library = current;
    if (library == null) continue;
    if (line.startsWith('export ')) {
      library.exports[line.split(' ')[1]] = (
        line,
        <String>[for (final m in members) m.split(' ').first],
      );
    } else {
      library.declarations[_declared(line)] = (line, members);
    }
  }
  return out;
}

String _bare(String line) {
  var rest = line.trimLeft();
  while (rest.startsWith('@')) {
    var depth = 0;
    var i = 0;
    for (; i < rest.length; i++) {
      final c = rest[i];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) {
          i++;
          break;
        }
      }
      if (c == ' ' && depth == 0) break;
    }
    rest = rest.substring(i).trimLeft();
  }
  return rest;
}

String _declared(String header) {
  final bare = _bare(header);
  for (final p in <RegExp>[
    RegExp(
      r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s+([\w$]+)',
    ),
    RegExp(r'^(?:base\s+)?mixin\s+([\w$]+)'),
    RegExp(r'^enum\s+([\w$]+)'),
    RegExp(r'^extension\s+type\s+(?:const\s+)?([\w$]+)'),
    RegExp(r'^extension\s+([\w$]+)'),
    RegExp(r'^typedef\s+([\w$]+)'),
  ]) {
    final m = p.firstMatch(bare);
    if (m != null) return m.group(1)!;
  }
  return _memberName(bare);
}

String _memberName(String line) {
  var text = _bare(line);
  if (text.startsWith('abstract ')) text = text.substring(9);
  // A variable's initialiser goes first: ` = ` outside any brackets.
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if ('([{<'.contains(c)) depth++;
    if (')]}>'.contains(c) && !(c == '>' && i > 0 && text[i - 1] == '=')) {
      depth--;
    }
    if (depth == 0 && text.startsWith(' = ', i)) {
      text = text.substring(0, i);
      break;
    }
  }
  text = text.trimRight();
  // Then a parameter list, and type parameters, walked back from the end
  // so a record return type `(double, double) f()` is not taken for one.
  String withoutTrailing(String s, String open, String close) {
    if (!s.endsWith(close)) return s;
    var d = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      if (s[i] == close) d++;
      if (s[i] == open) {
        d--;
        if (d == 0) return s.substring(0, i).trimRight();
      }
    }
    return s;
  }

  text = withoutTrailing(text, '(', ')');
  text = withoutTrailing(text, '<', '>');
  return RegExp(r'([\w$.]+)$').firstMatch(text.trimRight())?.group(1) ?? text;
}

/// The `fix_data` kind of a top-level declaration [header].
String topLevelKind(String header) {
  final bare = _bare(header);
  if (RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s',
  ).hasMatch(bare)) {
    return 'class';
  }
  if (RegExp(r'^(?:base\s+)?mixin\s').hasMatch(bare)) return 'mixin';
  if (bare.startsWith('enum ')) return 'enum';
  if (bare.startsWith('extension type ')) return 'class';
  if (bare.startsWith('extension ')) return 'extension';
  if (bare.startsWith('typedef ')) return 'typedef';
  if (RegExp(r'\bget\s+[\w$]+$').hasMatch(bare)) return 'getter';
  final name = _memberName(bare);
  final at = bare.indexOf('$name(');
  final atGeneric = bare.indexOf('$name<');
  if (at >= 0 || (atGeneric >= 0 && bare.contains('('))) return 'function';
  return 'variable';
}

/// The `fix_data` kind of member [line] of a type named [type], and the
/// name it goes by there (a constructor's is its name after the dot, empty
/// for the unnamed one).
(String, String) memberKind(String line, String type) {
  final bare = _bare(line).replaceFirst(RegExp(r'^abstract '), '');
  final name = _memberName(bare);
  if (name == type || name.startsWith('$type.')) {
    return ('constructor', name == type ? '' : name.substring(type.length + 1));
  }
  if (RegExp(r'\bget\s+[\w$]+$').hasMatch(bare)) return ('getter', name);
  if (RegExp(r'(^|\s)set\s+[\w$]+\(').hasMatch(bare)) return ('setter', name);
  final paren = bare.indexOf('$name(');
  final generic = bare.indexOf('$name<');
  if (paren >= 0 || generic >= 0) return ('method', name);
  return ('field', name);
}

/// `inClass`, `inMixin`, `inEnum` or `inExtension` for a type [header].
String containerKey(String header) => switch (topLevelKind(header)) {
  'mixin' => 'inMixin',
  'enum' => 'inEnum',
  'extension' => 'inExtension',
  _ => 'inClass',
};

/// The library of [libraries] that declares [name] — not one that
/// re-exports it — the package's main library first; null when none does.
String? _declaringLibrary(Iterable<SnapshotLibrary> libraries, String name) {
  final declaring = <String>[
    for (final l in libraries)
      if (l.declarations.containsKey(name)) l.uri,
  ];
  for (final uri in declaring) {
    final package = RegExp(r'^package:(\w+)/').firstMatch(uri)?.group(1);
    if (uri == 'package:$package/$package.dart') return uri;
  }
  return declaring.firstOrNull;
}

/// What could not be generated, as (entry id, why): an entry whose symbol
/// is not in the release's snapshot cannot say what kind it is.
typedef FixDataProblem = (String, String);

/// Each package's `lib/fix_data.yaml`, from [tables] read against the
/// release snapshots [released] (package to `.api` text) and the snapshots
/// now [current].
({Map<String, String> files, List<FixDataProblem> problems}) generateFixData(
  List<MigrationTable> tables, {
  required Map<String, Map<String, String>> released,
  required Map<String, String> current,
  required String stamp,
}) {
  final transforms = <String, List<String>>{};
  final problems = <FixDataProblem>[];
  final now = <String, Map<String, SnapshotLibrary>>{
    for (final e in current.entries) e.key: parseSnapshot(e.value),
  };

  for (final table in tables) {
    final then = <String, Map<String, SnapshotLibrary>>{
      for (final e
          in (released[table.from] ?? const <String, String>{}).entries)
        e.key: parseSnapshot(e.value),
    };
    Iterable<SnapshotLibrary> librariesThen() =>
        then.values.expand((Map<String, SnapshotLibrary> m) => m.values);
    Iterable<SnapshotLibrary> librariesNow() =>
        now.values.expand((Map<String, SnapshotLibrary> m) => m.values);

    (String, List<String>)? declarationThen(String name, String package) {
      final own = then[package]?.values
          .map((SnapshotLibrary l) => l.declarations[name])
          .whereType<(String, List<String>)>();
      if (own != null && own.isNotEmpty) return own.first;
      for (final l in librariesThen()) {
        final d = l.declarations[name];
        if (d != null) return d;
      }
      return null;
    }

    List<String> visibleThen(String name) => <String>[
      for (final l in librariesThen())
        if (l.shows(name)) l.uri,
    ]..sort();

    String packageOf(String uri) =>
        RegExp(r'^package:(\w+)/').firstMatch(uri)?.group(1) ?? '';

    // A package the release merged into another (`flutter3d_lti` into
    // `flutter3d_education`) carries its transforms in the package it is now
    // part of: the old one is not there to read them from.
    void add(String package, String yaml) =>
        (transforms[table.renamedPackages[package] ?? package] ??= <String>[])
            .add(yaml);

    // The libraries a fix matches an element through: those of the release,
    // and where `migrate` moved each one, since it rewrites a project's
    // imports before `dart fix` runs.
    List<String> withMoved(List<String> uris) =>
        <String>{...uris, for (final uri in uris) table.movedUri(uri)}.toList()
          ..sort();

    String title(MigrationEntry e, [String? what]) =>
        "flutter3d ${table.to}: ${what ?? e.id}";

    // A type a `rename` entry covers is no longer shown under its old name
    // anywhere, so a library re-export that lost it is not a move to report:
    // the rename's own fix carries every use.
    //
    // So is a name gone from every library, with an entry of its own saying
    // what replaces it (`linearFromSrgb`, which is `LinearColor.fromSrgb`):
    // there is nothing left to import, and that entry is what a use meets.
    final renamed = <String>{
      for (final e in table.entries)
        if (e.member == null &&
            !e.symbol.contains(':') &&
            (e.kind == 'rename' ||
                ((e.kind == 'manual' || e.kind == 'none') &&
                    !librariesNow().any(
                      (SnapshotLibrary l) => l.shows(e.topName),
                    ))))
          e.topName,
    };

    for (final e in table.entries) {
      switch (e.kind) {
        case 'rename':
          final declared = declarationThen(e.topName, e.package);
          if (declared == null) {
            problems.add((
              e.id,
              '`${e.topName}` is not in the ${table.from} '
                  'snapshot, so its kind is unknown',
            ));
            continue;
          }
          final uris = withMoved(visibleThen(e.topName));
          final member = e.member;
          final newName = e.to!.contains('.') ? e.to!.split('.').last : e.to!;
          if (member == null) {
            add(
              e.package,
              _transform(
                title: title(e),
                date: table.date,
                uris: uris,
                element: <String, String>{topLevelKind(declared.$1): e.topName},
                changes: <String>[
                  "      - kind: 'rename'\n        newName: '$newName'",
                ],
              ),
            );
          } else {
            final line = declared.$2.firstWhere(
              (String m) =>
                  _memberName(_bare(m)) == member ||
                  _memberName(_bare(m)) == '${e.topName}.$member',
              orElse: () => '',
            );
            if (line.isEmpty) {
              problems.add((
                e.id,
                '`${e.symbol}` is not in the ${table.from} '
                    'snapshot',
              ));
              continue;
            }
            final (kind, name) = memberKind(line, e.topName);
            add(
              e.package,
              _transform(
                title: title(e),
                date: table.date,
                uris: uris,
                element: <String, String>{
                  kind: name,
                  containerKey(declared.$1): e.topName,
                },
                changes: <String>[
                  "      - kind: 'rename'\n        newName: '$newName'",
                ],
              ),
            );
          }
        case 'moved':
          final to = e.to!;
          final List<String> names;
          final List<String> fromUris;
          if (e.symbol.contains(':')) {
            // A library no longer re-exported: every name it brought that
            // the re-exporting library no longer shows.
            // The entry's own package's libraries: another package that
            // re-exported the same library has entries of its own.
            final via = <SnapshotLibrary>[
              for (final l in librariesThen())
                if (packageOf(l.uri) == e.package &&
                    l.exports.containsKey(e.symbol))
                  l,
            ];
            names = <String>{
              for (final l in via)
                for (final n in l.exports[e.symbol]!.$2)
                  if (!renamed.contains(n) &&
                      !(now[packageOf(l.uri)]?[l.uri]?.shows(n) ?? false))
                    n,
            }.toList()..sort();
            fromUris = <String>[for (final l in via) l.uri]..sort();
          } else {
            names = <String>[e.topName];
            fromUris = <String>[
              for (final uri in visibleThen(e.topName))
                if (!(now[packageOf(uri)]?[uri]?.shows(e.topName) ?? false))
                  uri,
            ];
          }
          if (fromUris.isEmpty) {
            problems.add((
              e.id,
              'no ${table.from} library that showed '
                  '`${e.symbol}` has lost it',
            ));
            continue;
          }
          for (final name in names) {
            final declared = declarationThen(name, e.package);
            if (declared == null) {
              problems.add((
                e.id,
                '`$name` is not in the ${table.from} '
                    'snapshot, so its kind is unknown',
              ));
              continue;
            }
            final kind = topLevelKind(declared.$1);
            // `dart fix` refuses `replacedBy` for an extension
            // (`invalid_change_for_kind`), and the whole file with it. An
            // extension is reached through its members, not by name, so the
            // import `migrate` rewrites is all a caller needs.
            if (kind == 'extension') continue;
            final newName = e.name ?? name;
            final stillThere = librariesNow().any(
              (SnapshotLibrary l) => l.uri == to && l.shows(newName),
            );
            // A whole library no longer re-exported brought names that have
            // moved on since: `flutter3d_sim` re-exported 0.8's physics,
            // whose `Portable` is the foundation's now. `to` is where most of
            // them are, and each of the rest goes to the library that
            // declares it now, the package's main one first.
            final target = stillThere
                ? to
                : e.symbol.contains(':')
                ? _declaringLibrary(librariesNow(), newName)
                : null;
            if (target == null) {
              problems.add((e.id, '`$to` does not show `$newName`'));
              continue;
            }
            add(
              packageOf(target),
              _transform(
                title: title(e, '${e.id} ($name)'),
                date: table.date,
                uris: withMoved(fromUris),
                element: <String, String>{kind: name},
                changes: <String>[
                  <String>[
                    "      - kind: 'replacedBy'",
                    '        newElement:',
                    "          uris: ['$target']",
                    "          $kind: '$newName'",
                  ].join('\n'),
                ],
              ),
            );
          }
        case 'parameters':
          final declared = declarationThen(e.topName, e.package);
          if (declared == null) {
            problems.add((
              e.id,
              '`${e.topName}` is not in the ${table.from} '
                  'snapshot',
            ));
            continue;
          }
          final Map<String, String> element;
          final member = e.member;
          if (member == null) {
            element = <String, String>{topLevelKind(declared.$1): e.topName};
          } else {
            final line = declared.$2.firstWhere(
              (String m) =>
                  _memberName(_bare(m)) == member ||
                  _memberName(_bare(m)) == '${e.topName}.$member',
              orElse: () => '',
            );
            if (line.isEmpty) {
              problems.add((e.id, '`${e.symbol}` is not in the snapshot'));
              continue;
            }
            final (kind, name) = memberKind(line, e.topName);
            element = <String, String>{
              kind: name,
              containerKey(declared.$1): e.topName,
            };
          }
          final changes = <String>[
            for (final c in e.changes) ?_parameterChange(c),
          ];
          if (changes.length != e.changes.length) {
            problems.add((e.id, 'a change is not rename/remove/add'));
            continue;
          }
          add(
            e.package,
            _transform(
              title: title(e),
              date: table.date,
              uris: withMoved(visibleThen(e.topName)),
              element: element,
              changes: changes,
            ),
          );
      }
    }
  }

  return (
    files: <String, String>{
      for (final MapEntry(key: package, value: list) in transforms.entries)
        package: _file(list, stamp),
    },
    problems: problems,
  );
}

String _file(List<String> transforms, String stamp) =>
    '# Generated from flutter3d_build/lib/migrations/*.yaml by\n'
    '# `dart run tool/generate_migrations.dart` in flutter3d_build. '
    'Do not edit.\n'
    '# table-stamp: $stamp\n'
    '#\n'
    '# Read by `dart fix` and the IDE: see "A break comes with its '
    'migration"\n'
    '# in CONTRIBUTING.md.\n'
    'version: 1\n'
    'transforms:\n'
    '${transforms.join()}';

String _transform({
  required String title,
  required String date,
  required List<String> uris,
  required Map<String, String> element,
  required List<String> changes,
}) {
  final out = StringBuffer()
    ..writeln("  - title: '${title.replaceAll("'", "''")}'")
    ..writeln('    date: $date')
    ..writeln('    element:')
    ..writeln("      uris: [${uris.map((String u) => "'$u'").join(', ')}]");
  for (final MapEntry(:key, :value) in element.entries) {
    out.writeln("      $key: '$value'");
  }
  out.writeln('    changes:');
  for (final c in changes) {
    out.writeln(c);
  }
  return out.toString();
}

String? _parameterChange(Map<String, Object?> c) {
  if (c['rename'] case final String old) {
    return "      - kind: 'renameParameter'\n"
        "        oldName: '$old'\n"
        "        newName: '${c['to']}'";
  }
  if (c.containsKey('remove')) {
    final which = c['remove'];
    return which is int
        ? "      - kind: 'removeParameter'\n        index: $which"
        : "      - kind: 'removeParameter'\n        name: '$which'";
  }
  if (c['add'] case final String name) {
    final named = c['named'] == true;
    final required = c['required'] == true;
    final style = named
        ? (required ? 'required_named' : 'optional_named')
        : (required ? 'required_positional' : 'optional_positional');
    final value = c['value'];
    return "      - kind: 'addParameter'\n"
        '        index: ${c['index'] ?? 0}\n'
        "        name: '$name'\n"
        '        style: $style'
        '${value == null ? '' : "\n        argumentValue:\n          expression: '${'$value'.replaceAll("'", "''")}'"}';
  }
  return null;
}
