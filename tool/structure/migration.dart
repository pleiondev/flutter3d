/// Whether every break since the last published release has a migration
/// entry: the reading of `packages/flutter3d_build/lib/migrations/*.yaml`
/// that the structure rule and `tool/api`'s `migration_seed` share.
///
/// **Plain Dart over text, like `api.dart`.** The table is YAML, and the
/// package that reads it properly (`flutter3d_build`, through `package:yaml`)
/// needs `pub get`; this needs nothing. So the table keeps one layout — each
/// entry a `  - id: …` line followed by its keys at four spaces — and this
/// reads only the scalar keys at that depth. `flutter3d_build`'s generator
/// reads the same file with the real parser and refuses one whose entries the
/// two readers see differently, so the layout cannot drift from under this.
///
/// **What counts as covered.** A break is a [Bump.major] change from
/// `classifyApi` between the release's snapshot of a package and its
/// snapshot now. An entry covers it when the entry's `package` is that
/// package or one it re-exports (the facade `flutter3d` breaks whenever
/// `flutter3d_core` does, through the same names), and its `symbol` is the
/// break's top-level name — which covers every member of it — or
/// `Name.member`, which covers that member alone. A removed library is
/// covered by an entry whose `symbol` is its URI.
///
/// Two breaks the classifier reports are not breaks to a caller, and are
/// left out here rather than written down by hand by the dozen:
///
///  * a member gone from a type whose supertype, mixin or interface now
///    declares it — the capability getters every backend moved into
///    `DeviceCapabilityForwarders` are still there to call;
///  * a declaration gone from a library that now re-exports the same name
///    from another package — `Portable` moved from `flutter3d_sim` into
///    `flutter3d_physics`, and `flutter3d_sim` still hands it out.
library;

import 'api.dart';

/// The kinds of entry, and the scalar key each one cannot do without.
///
/// What each kind becomes is `flutter3d_build`'s business — `rename`,
/// `moved` and `parameters` turn into `lib/fix_data.yaml` for `dart fix`;
/// `rewrite`, `implementsToWith` and `manual` into the `flutter3d_lints`
/// migration diagnostics and their fixes; `import` into the `migrate`
/// command's own import rewrite — and `none` into nothing but a line in the
/// guide, with the reason a caller has nothing to do. `regroup`,
/// `enumToClass`, `recordToClass` and `nullToThrow` are carried out by the
/// lints with the resolved code; `internal` is one diagnostic per import
/// and one line per package in the guide.
const Map<String, String?> migrationKinds = <String, String?>{
  'rename': 'to',
  'moved': 'to',
  'parameters': 'changes',
  'rewrite': 'template',
  'implementsToWith': null,
  'regroup': 'into',
  'enumToClass': null,
  'recordToClass': 'fields',
  'nullToThrow': 'exception',
  'internal': null,
  'manual': 'guidance',
  'none': 'reason',
  'import': 'to',
};

/// The keys a kind needs beside the one [migrationKinds] names.
const Map<String, List<String>> migrationKindsAlsoNeed = <String, List<String>>{
  'regroup': <String>['options', 'arguments'],
};

/// **The ceiling on `manual` entries.** What wave M left after it moved the
/// backends' own names to `internal`. A `manual` entry is a TODO in
/// somebody's code; a break the kinds above can carry out uses them, and
/// one that cannot is named in [manualAllowlist] with the reason.
const int manualCeiling = 341;

/// `manual` entries past [manualCeiling], each with why no kind carries it
/// out. Entry id to reason.
const Map<String, String> manualAllowlist = <String, String>{
  'build-convert-confined':
      'where a model\'s files live is the user\'s layout, not a shape a '
      'program can rewrite: the files move, or the call passes `root:`',
  'flutter3d-BundleAssetSource-missing':
      'a `catch` changes what it catches; whether the handler still fits is '
      'the reader\'s call',
  'flutter3d-loadModelAsset-missing':
      'a `catch` changes what it catches; whether the handler still fits is '
      'the reader\'s call',
};

/// Words in what a person reads that belong to the work behind the release,
/// not to the user: a wave, a plan file, a review's decision number.
final RegExp _planWords = RegExp(
  r'\(wave \w+\)|\bwave \d\b|tasks/|\bdecision \d|\bAPI review\b|'
  r'\brc1-plan\b|\breadiness review\b',
  caseSensitive: false,
);

/// What a person reads of an entry.
const List<String> _readKeys = <String>['guidance', 'reason', 'instead'];

/// One entry of a migration table, as far as this reader sees it.
final class MigrationEntry {
  const MigrationEntry(this.line, this.fields);

  /// The 1-based line its `- id:` is on.
  final int line;

  /// Its scalar keys at entry depth. A key whose value is a block (a list,
  /// a `>-` paragraph) holds the block's lines folded into one, which is
  /// what `>-` means and enough to check a list is there.
  final Map<String, String> fields;

  String get id => fields['id'] ?? '';
  String get kind => fields['kind'] ?? '';
  String get package => fields['package'] ?? '';
  String get symbol => fields['symbol'] ?? '';
}

/// A migration table as this reader sees it.
final class MigrationTable {
  const MigrationTable({
    required this.from,
    required this.to,
    required this.entries,
    required this.renamedPackages,
    required this.removedPackages,
    required this.constraint,
    required this.versions,
  });

  /// `packages: constraint:` — what a dependency on the engine moves to.
  final String constraint;

  /// `packages: versions:` — a package not on the engine's number, and the
  /// constraint a dependency on it moves to.
  final Map<String, String> versions;

  /// The release it migrates from, as `0.8.5`.
  final String from;

  /// The release it migrates to.
  final String to;
  final List<MigrationEntry> entries;

  /// `packages: renamed:` — old name to new.
  final Map<String, String> renamedPackages;

  /// `packages: removed:` — each name, with its guidance.
  final Map<String, String> removedPackages;
}

/// [text] read as a migration table.
MigrationTable readMigrationTable(String text) {
  final lines = text.split('\n');
  final entries = <MigrationEntry>[];
  final renamed = <String, String>{};
  final removed = <String, String>{};
  final versions = <String, String>{};
  String? constraint;
  String? from;
  String? to;
  String? section;
  String? subsection;
  Map<String, String>? current;
  var currentLine = 0;
  void flush() {
    final open = current;
    if (open != null) entries.add(MigrationEntry(currentLine, open));
    current = null;
  }

  String unquote(String v) {
    final t = v.trim();
    if (t.length >= 2 &&
        ((t.startsWith("'") && t.endsWith("'")) ||
            (t.startsWith('"') && t.endsWith('"')))) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final top = RegExp(r'^([A-Za-z_]+):\s*(.*)$').firstMatch(line);
    if (top != null) {
      flush();
      section = top.group(1);
      subsection = null;
      if (section == 'from') from = unquote(top.group(2)!);
      if (section == 'to') to = unquote(top.group(2)!);
      continue;
    }
    if (section == 'packages') {
      final sub = RegExp(r'^  ([A-Za-z_]+):\s*$').firstMatch(line);
      if (sub != null) {
        subsection = sub.group(1);
        continue;
      }
      final scalar = RegExp(r'^  constraint:\s*(\S+)').firstMatch(line);
      if (scalar != null) {
        constraint = unquote(scalar.group(1)!);
        continue;
      }
      final item = RegExp(r'^    ([\w]+):\s*(.*)$').firstMatch(line);
      if (item != null) {
        final into = switch (subsection) {
          'renamed' => renamed,
          'removed' => removed,
          'versions' => versions,
          _ => null,
        };
        into?[item.group(1)!] = unquote(item.group(2)!);
      }
      continue;
    }
    if (section != 'entries') continue;
    final start = RegExp(r'^  - id:\s*(.*)$').firstMatch(line);
    if (start != null) {
      flush();
      currentLine = i + 1;
      current = <String, String>{'id': unquote(start.group(1)!)};
      continue;
    }
    final key = RegExp(r'^    ([A-Za-z_]+):\s*(.*)$').firstMatch(line);
    if (key != null && current != null) {
      var value = unquote(key.group(2)!);
      if (value.isEmpty || value == '>-' || value == '|' || value == '>') {
        // A block: its lines, folded, stand for it.
        final block = <String>[
          for (
            var j = i + 1;
            j < lines.length && lines[j].startsWith('      ');
            j++
          )
            lines[j].trim(),
        ];
        value = block.join(' ');
      }
      current![key.group(1)!] = value;
    }
  }
  flush();
  return MigrationTable(
    from: from ?? '',
    to: to ?? '',
    entries: entries,
    renamedPackages: renamed,
    removedPackages: removed,
    constraint: constraint ?? '',
    versions: versions,
  );
}

/// What is wrong with the entries of [table] on their own, as (line, what).
List<(int, String)> migrationTableProblems(MigrationTable table) {
  final problems = <(int, String)>[];
  final seen = <String>{};
  for (final e in table.entries) {
    if (e.id.isEmpty) problems.add((e.line, 'an entry with no id'));
    if (!seen.add(e.id)) problems.add((e.line, 'the id `${e.id}` is taken'));
    if (!migrationKinds.containsKey(e.kind)) {
      problems.add((
        e.line,
        '`${e.id}` has kind `${e.kind}`, not one of '
            '${migrationKinds.keys.join(', ')}',
      ));
      continue;
    }
    for (final needs in <String>[
      ?migrationKinds[e.kind],
      ...?migrationKindsAlsoNeed[e.kind],
    ]) {
      if ((e.fields[needs] ?? '').isEmpty) {
        problems.add((e.line, '`${e.id}` is a ${e.kind} with no `$needs`'));
      }
    }
    // The import is what an internal entry's diagnostic stands on, so it
    // names what an import brings: a top-level name or a library.
    if (e.kind == 'internal' &&
        !e.symbol.contains(':') &&
        e.symbol.contains('.')) {
      problems.add((
        e.line,
        '`${e.id}` is internal but names the member `${e.symbol}`: an '
            'internal entry names a top-level name or a library',
      ));
    }
    for (final key in _readKeys) {
      final said = _planWords.firstMatch(e.fields[key] ?? '');
      if (said != null) {
        problems.add((
          e.line,
          '`${e.id}` says "${said.group(0)}" in `$key`: what a person reads '
              'lands in their TODO, and names no wave, plan or review',
        ));
      }
    }
    // `migration_seed` writes TODO where a person has to decide; a TODO
    // left in is a break nobody has thought about yet.
    for (final MapEntry(:key, :value) in e.fields.entries) {
      if (value.contains('TODO')) {
        problems.add((e.line, '`${e.id}` still says TODO in `$key`'));
      }
    }
    if (e.kind != 'import' && e.package.isEmpty) {
      problems.add((e.line, '`${e.id}` names no package'));
    }
    if (e.kind != 'import' && e.symbol.isEmpty) {
      problems.add((e.line, '`${e.id}` names no symbol'));
    }
  }
  return problems;
}

/// What is wrong with the count of `manual` entries in [tables], as (entry
/// id or table, what): past [ceiling] with no reason in [allowlist], or an
/// allowlisted id that is not a `manual` entry any more.
///
/// The entries past the ceiling are the last ones appended, since the table
/// only grows at its end; each is named with the kind its text suggests
/// would carry it out, when one does.
List<(String, String)> manualCeilingProblems(
  List<MigrationTable> tables, {
  int ceiling = manualCeiling,
  Map<String, String> allowlist = manualAllowlist,
}) {
  final problems = <(String, String)>[];
  final manual = <MigrationEntry>[
    for (final t in tables)
      for (final e in t.entries)
        if (e.kind == 'manual') e,
  ];
  final counted = <MigrationEntry>[
    for (final e in manual)
      if (!allowlist.containsKey(e.id)) e,
  ];
  if (counted.length > ceiling) {
    for (final e in counted.skip(ceiling)) {
      final kind = automatableKind(e.fields['guidance'] ?? '');
      problems.add((
        e.id,
        'is manual entry ${counted.indexOf(e) + 1}, past the ceiling of '
            '$ceiling: '
            '${kind == null ? 'carry it out with a kind the tools apply' : 'its text reads like a `$kind`'}, '
            'or name it in `manualAllowlist` with the reason no kind can',
      ));
    }
  }
  final ids = <String>{for (final e in manual) e.id};
  for (final MapEntry(key: id, value: reason) in allowlist.entries) {
    if (!ids.contains(id)) {
      problems.add((id, 'is on `manualAllowlist` but is no manual entry'));
    } else if (reason.trim().isEmpty) {
      problems.add((id, 'is on `manualAllowlist` with no reason'));
    }
  }
  return problems;
}

/// The automatic kind a `manual` entry's [guidance] describes, or null.
String? automatableKind(String guidance) {
  final text = guidance.replaceAll(RegExp(r'\s+'), ' ');
  if (RegExp(
    r'has (?:a new case|new values|a new value)|An open set since|'
    r'is a class with constants|no longer (?:an enum|sealed)',
  ).hasMatch(text)) {
    return 'enumToClass';
  }
  if (RegExp(
    r'throws [^.]*(?:where|instead of|in place of) (?:it )?'
    r'(?:returned|returning|answered|answering) null',
  ).hasMatch(text)) {
    return 'nullToThrow';
  }
  if (RegExp(r'\.\$\d|\ba record\b').hasMatch(text)) return 'recordToClass';
  if (RegExp(r'moved into `\w+Options`|now in `\w+Options`').hasMatch(text)) {
    return 'regroup';
  }
  return null;
}

/// The counts of [tables] a person is told: every entry, and the ones left
/// by hand (`manual`).
({int entries, int byHand, int internal}) migrationCounts(
  List<MigrationTable> tables,
) => (
  entries: tables.fold(0, (int n, MigrationTable t) => n + t.entries.length),
  byHand: tables.fold(
    0,
    (int n, MigrationTable t) =>
        n + t.entries.where((MigrationEntry e) => e.kind == 'manual').length,
  ),
  internal: tables.fold(
    0,
    (int n, MigrationTable t) =>
        n + t.entries.where((MigrationEntry e) => e.kind == 'internal').length,
  ),
);

/// Where [text] — prose about the migration, such as the README's "Coming
/// from 0.8" — states a count the table does not: a round guess ("about two
/// hundred places"), or `N entries`, `N places`, `N changes`, `N by hand`
/// with N not the table's. Each as what it said and what the table says.
List<String> migrationNumberProblems(
  String text, {
  required ({int entries, int byHand, int internal}) counts,
}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ');
  final problems = <String>[];
  for (final m in RegExp(
    r'\babout (?:a |an |one |two |three |four |five |six |seven |eight |nine |'
    r'several |a few )?(?:hundred|thousand|dozen)s? (?:places|changes|entries)',
    caseSensitive: false,
  ).allMatches(flat)) {
    problems.add(
      '"${m.group(0)}" is a guess: the table has ${counts.entries} entries, '
      '${counts.byHand} of them by hand',
    );
  }
  for (final m in RegExp(
    r'\b(\d[\d ,]*\d|\d) (entries|places|changes|by hand)\b',
  ).allMatches(flat)) {
    final n = int.parse(m.group(1)!.replaceAll(RegExp('[ ,]'), ''));
    final want = m.group(2) == 'by hand' ? counts.byHand : counts.entries;
    if (n != want) {
      problems.add(
        '"${m.group(0)}" is not the table\'s: it has ${counts.entries} '
        'entries, ${counts.byHand} of them by hand',
      );
    }
  }
  return problems;
}

/// One break and where it was found.
typedef MigrationBreak = ({String package, ApiChange change});

/// The member a break is about, `Name.member`, or the bare name when it is
/// about the whole declaration.
String breakSymbol(ApiChange change) {
  final prefix = '${change.subject}.';
  if (change.what.startsWith(prefix)) {
    final rest = change.what.substring(prefix.length);
    final end = rest.indexOf(' ');
    return '$prefix${end < 0 ? rest : rest.substring(0, end)}';
  }
  return change.subject;
}

/// Every break between [released] and [current] — package name to snapshot
/// text — that no entry of [table] covers and that is not one of the two
/// non-breaks the library comment describes.
///
/// A package in [released] with no snapshot in [current] is a package gone,
/// which `packages: removed:` or `renamed:` has to name; it is reported as a
/// break whose subject is the package.
List<MigrationBreak> uncoveredBreaks({
  required Map<String, String> released,
  required Map<String, String> current,
  required MigrationTable table,
}) {
  final parsedNow = <String, Map<String, ApiLibrary>>{
    for (final e in current.entries) e.key: parseApi(e.value),
  };
  // Every declaration now, by name, wherever it is.
  final declarations = <String, List<ApiBlock>>{};
  for (final libraries in parsedNow.values) {
    for (final library in libraries.values) {
      for (final d in library.declarations.entries) {
        (declarations[d.key] ??= <ApiBlock>[]).add(d.value);
      }
    }
  }

  Set<String> reexported(String package) {
    final out = <String>{package};
    final queue = <String>[package];
    while (queue.isNotEmpty) {
      final p = queue.removeLast();
      for (final text in <String?>[current[p], released[p]]) {
        if (text == null) continue;
        for (final m in RegExp(
          r'^export package:(\w+)/',
          multiLine: true,
        ).allMatches(text)) {
          if (out.add(m.group(1)!)) queue.add(m.group(1)!);
        }
      }
    }
    return out;
  }

  final covers = <String, Set<String>>{};
  for (final e in table.entries) {
    (covers[e.symbol] ??= <String>{}).add(e.package);
  }
  bool covered(String package, String symbol) {
    final reach = reexported(package);
    final top = symbol.contains(':') ? symbol : symbol.split('.').first;
    for (final s in <String>{symbol, top}) {
      if ((covers[s] ?? const <String>{}).any(reach.contains)) return true;
    }
    return false;
  }

  bool inherited(String type, String member, [int depth = 0]) {
    if (depth > 12) return false;
    for (final block in declarations[type] ?? const <ApiBlock>[]) {
      for (final parent in supertypeNames(block.header)) {
        for (final p in declarations[parent] ?? const <ApiBlock>[]) {
          if (p.members.any((String m) => memberName(m) == member)) {
            return true;
          }
        }
        if (inherited(parent, member, depth + 1)) return true;
      }
    }
    return false;
  }

  bool stillExported(String package, String library, String name) {
    final lib = parsedNow[package]?[library];
    if (lib == null) return false;
    for (final export in lib.exports.values) {
      if (export.members.any((String m) => m.split(' ').first == name)) {
        return true;
      }
      final show = RegExp(r' show ([\w$, ]+)').firstMatch(export.header);
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

  final out = <MigrationBreak>[];
  for (final package in released.keys.toList()..sort()) {
    final renamed = table.renamedPackages[package];
    final now = current.containsKey(package)
        ? _asReleased(null, current[package], table)
        : (renamed == null
              ? null
              : _asReleased(package, current[renamed], table));
    if (now == null) {
      if (!table.removedPackages.containsKey(package) &&
          !table.renamedPackages.containsKey(package)) {
        out.add((
          package: package,
          change: ApiChange(
            package,
            package,
            'the package is gone: name it under packages: removed: or '
            'renamed:',
            Bump.major,
          ),
        ));
      }
      continue;
    }
    for (final change in classifyApi(released[package]!, now)) {
      if (change.bump != Bump.major) continue;
      final symbol = breakSymbol(change);
      if (covered(package, symbol)) continue;
      if (symbol != change.subject &&
          change.what.endsWith(' is gone') &&
          inherited(
            change.subject,
            symbol.substring(change.subject.length + 1),
          )) {
        continue;
      }
      if (change.what == 'gone' &&
          stillExported(package, change.library, change.subject)) {
        continue;
      }
      if (onlyGainedSupertypes(change.what)) continue;
      if (constructorCalledTheSame(change.subject, change.what)) continue;
      out.add((package: package, change: change));
    }
  }
  return out;
}

/// [current] with the libraries that moved in this release read under the
/// URIs they were released with, so a package is measured against its
/// release and not against the move.
///
/// With a [package], [current] is the snapshot of the package it was merged
/// into, and only the libraries `import` entries say [package]'s became are
/// kept, under [package]'s own URIs. Null when no entry moves a library of
/// it there: a package renamed whole compares with nothing, as before.
/// Without one, every library is kept and only what it re-exports is read
/// back: `flutter3d_sim_mcp` re-exports the kit, released as
/// `package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart` and
/// `package:flutter3d_mcp/kit.dart` now, and that is no break.
///
/// **Why measure a merged package at all.** `flutter3d_lti` went into
/// `flutter3d_education` with renames of its own (`LtiPlatformConfig` is
/// `LtiPlatformSettings`); skipping a renamed package would have let the
/// next break in it through with no entry, because the package it was
/// released as is no longer there to compare.
String? _asReleased(String? package, String? current, MigrationTable table) {
  if (current == null) return null;
  // Every library that moved, new URI to old: this package's, to pick its
  // libraries out, and its siblings', so a re-export of the kit
  // (`package:flutter3d_mcp/kit.dart`, released as
  // `package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart`) reads as the one it
  // was.
  final back = <String, String>{
    for (final e in table.entries)
      if (e.kind == 'import' &&
          e.fields['from'] != null &&
          e.fields['to'] != null &&
          !e.fields['from']!.endsWith('/'))
        e.fields['to']!: e.fields['from']!,
  };
  final out = StringBuffer();
  var keep = false;
  for (final line in current.split('\n')) {
    if (line.startsWith('library ')) {
      final uri = line.substring('library '.length).trim();
      final was = back[uri];
      if (package == null) {
        keep = true;
        out.writeln(line);
        continue;
      }
      keep = was != null && was.startsWith('package:$package/');
      if (keep) out.writeln('library $was');
      continue;
    }
    if (!keep) continue;
    final export = RegExp(r'^export (\S+)(.*)$').firstMatch(line);
    final was = export == null ? null : back[export.group(1)];
    out.writeln(was == null ? line : 'export $was${export!.group(2)}');
  }
  return out.isEmpty ? null : out.toString();
}

/// Whether a break worded `the declaration changed: <was> -> <now>` only
/// moved supertypes between `implements`, `with` and `extends` or added
/// some, on a type nobody outside may implement (`final`, `sealed`, `base`)
/// and with its modifiers unchanged. Every caller still holds a value of
/// every type it held one of; what the classifier cannot tell from text is
/// that `final class A implements B` and `final class A with B` are the
/// same promise to everybody but A's author.
bool onlyGainedSupertypes(String what) {
  const prefix = 'the declaration changed: ';
  if (!what.startsWith(prefix)) return false;
  final parts = what.substring(prefix.length).split(' -> ');
  if (parts.length != 2) return false;
  String head(String h) {
    final bare = splitAnnotations(h).rest;
    final cut = RegExp(r' (extends|with|implements|on) ').firstMatch(bare);
    return cut == null ? bare : bare.substring(0, cut.start);
  }

  final was = parts[0];
  final now = parts[1];
  if (head(was) != head(now)) return false;
  if (!RegExp(r'^(abstract )?(final|sealed|base)\b').hasMatch(head(now)) &&
      !RegExp(r'^(abstract )?base mixin\b').hasMatch(head(now))) {
    return false;
  }
  return supertypeNames(now).containsAll(supertypeNames(was));
}

/// Whether a break worded `Type.Type changed: <was> -> <now>` (or a named
/// constructor) is one no call can see: every argument a caller passed it
/// still takes the same way, with the same default, and what it gained is
/// optional. Writing `this.width` as `int width` to forward it, renaming a
/// positional parameter, adding an optional named one: the classifier calls
/// each a changed signature, because a method someone overrides would break
/// on it; a constructor is never overridden.
///
/// A default that moved is not one of these: a call that leaves the argument
/// out gets something else, which a migration entry has to say.
bool constructorCalledTheSame(String type, String what) {
  final m = RegExp(
    '^${RegExp.escape(type)}\\.(${RegExp.escape(type)}|[\\w\$]+) changed: ',
  ).firstMatch(what);
  if (m == null) return false;
  final parts = what.substring(m.end).split(' -> ');
  if (parts.length != 2) return false;
  final was = parts[0];
  final now = parts[1];
  bool isConstructor(String sig) => RegExp(
    '^(const |factory )*${RegExp.escape(type)}(\\.[\\w\$]+)?\\(',
  ).hasMatch(sig);
  if (!isConstructor(was) || !isConstructor(now)) return false;
  final p0 = _parameterList(was);
  final p1 = _parameterList(now);
  if (p0 == null || p1 == null) return false;
  if (p0.positional.length != p1.positional.length) return false;
  if (p0.optional.length > p1.optional.length) return false;
  for (var i = 0; i < p0.optional.length; i++) {
    if (p0.optional[i].$2 != p1.optional[i].$2) return false;
  }
  for (final MapEntry(key: name, value: (required, fallback))
      in p0.named.entries) {
    final after = p1.named[name];
    if (after == null || after.$1 != required || after.$2 != fallback) {
      return false;
    }
  }
  for (final MapEntry(key: name, value: (required, _)) in p1.named.entries) {
    if (!p0.named.containsKey(name) && required) return false;
  }
  return true;
}

/// A signature's parameters: positional names, optional positional (name,
/// default), and named ones as name to (required, default).
({
  List<String> positional,
  List<(String, String)> optional,
  Map<String, (bool, String)> named,
})?
_parameterList(String signature) {
  final open = signature.indexOf('(');
  if (open < 0 || !signature.endsWith(')')) return null;
  final inner = signature.substring(open + 1, signature.length - 1);
  final positional = <String>[];
  final optional = <(String, String)>[];
  final named = <String, (bool, String)>{};
  (String, String) read(String p) {
    var text = p.trim();
    var fallback = '';
    final eq = _topLevel(text, ' = ');
    if (eq >= 0) {
      fallback = text.substring(eq + 3).trim();
      text = text.substring(0, eq).trim();
    }
    final name = RegExp(r'([\w$]+)\s*$').firstMatch(text)?.group(1) ?? text;
    return (name, fallback);
  }

  for (final item in _splitTopLevel(inner)) {
    if (item.startsWith('[')) {
      for (final p in _splitTopLevel(item.substring(1, item.length - 1))) {
        optional.add(read(p));
      }
    } else if (item.startsWith('{')) {
      for (final p in _splitTopLevel(item.substring(1, item.length - 1))) {
        final required = p.trimLeft().startsWith('required ');
        final (name, fallback) = read(
          required ? p.trimLeft().substring('required '.length) : p,
        );
        named[name] = (required, fallback);
      }
    } else {
      positional.add(read(item).$1);
    }
  }
  return (positional: positional, optional: optional, named: named);
}

int _topLevel(String s, String needle) {
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if ('([{<'.contains(c)) depth++;
    if (')]}>'.contains(c)) depth--;
    if (depth == 0 && s.startsWith(needle, i)) return i;
  }
  return -1;
}

List<String> _splitTopLevel(String s) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      if (c == quote) quote = null;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if ('([{<'.contains(c)) {
      depth++;
    } else if (')]}>'.contains(c)) {
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

/// The type names a declaration header extends, mixes in, implements or is
/// `on`, without their type arguments.
Set<String> supertypeNames(String header) {
  final bare = splitAnnotations(header).rest;
  final out = <String>{};
  for (final word in const <String>[
    ' extends ',
    ' with ',
    ' implements ',
    ' on ',
  ]) {
    final at = bare.indexOf(word);
    if (at < 0) continue;
    var rest = bare.substring(at + word.length);
    for (final stop in const <String>[
      ' extends ',
      ' with ',
      ' implements ',
      ' on ',
    ]) {
      final s = rest.indexOf(stop);
      if (s >= 0) rest = rest.substring(0, s);
    }
    var depth = 0;
    final name = StringBuffer();
    for (final c in rest.split('')) {
      if (c == '<') depth++;
      if (c == '>') depth--;
      if (depth > 0 || c == '>' || c == '<') continue;
      if (c == ',') {
        out.add(name.toString().trim());
        name.clear();
      } else {
        name.write(c);
      }
    }
    if (name.toString().trim().isNotEmpty) out.add(name.toString().trim());
  }
  return out..removeWhere((String s) => s.isEmpty);
}

/// A 64-bit FNV-1a of [text], as 16 hex digits: the stamp a generated file
/// carries of the table it was generated from, so a structure rule can tell
/// a stale one without `package:crypto`.
String tableStamp(String text) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final unit in text.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    hash ^= unit >> 8;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  String half(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '${half(hash >> 32)}${half(hash)}';
}

// ----------------------------------------------------------------- proofs

/// The proof that the reader and the coverage check fire on what they must
/// and stay quiet on what only looks like it. Invented names, as in
/// `proveApiDetectorsWork`.
List<(String, String)> proveMigrationDetectorsWork() {
  final broken = <(String, String)>[];
  const table = '''
format: 1
from: 0.1.0
to: 1.0.0
packages:
  constraint: ^1.0.0
  versions:
    p_side: ^0.2.0
  renamed:
    p_old: p_new
  removed:
    p_gone: Use p instead.
entries:
  - id: p-ab-renamed
    package: p
    symbol: Ab
    kind: rename
    to: Cd
  - id: p-ef-g
    package: q
    symbol: Ef.g
    kind: manual
    guidance: >-
      Call h instead.
  - id: p-bad
    package: p
    symbol: Zz
    kind: rewrite
''';
  final read = readMigrationTable(table);
  if (read.entries.length != 3 ||
      read.from != '0.1.0' ||
      read.entries[1].fields['guidance'] != 'Call h instead.' ||
      read.renamedPackages['p_old'] != 'p_new' ||
      read.constraint != '^1.0.0' ||
      read.versions['p_side'] != '^0.2.0' ||
      read.removedPackages['p_gone'] != 'Use p instead.') {
    broken.add((
      'migration table reader',
      'read ${read.entries.length} entries from ${read.from} with '
          '${read.entries.map((MigrationEntry e) => e.fields)}',
    ));
  }
  final problems = migrationTableProblems(read);
  if (problems.length != 1 || !problems.single.$2.contains('no `template`')) {
    broken.add((
      'migration table reader',
      'found $problems where only the rewrite without a template is wrong',
    ));
  }

  const lib = 'library package:p/p.dart\n\n';
  const qlib = 'library package:q/q.dart\n\n';
  final released = <String, String>{
    'p':
        '${lib}final class Ab\n\nfinal class Gh\n  void k()\n\n'
        'final class Mn\n  void o()\n\nfinal class Portable\n\n'
        'final class Uv\n  void w()\n',
    'q': '${qlib}final class Ef\n  void g()\n  void x()\n',
    'p_gone': 'library package:p_gone/p_gone.dart\n\nfinal class Old\n',
    'p_away': 'library package:p_away/p_away.dart\n\nfinal class Away\n',
  };
  final current = <String, String>{
    'p':
        '${lib}final class Cd\n\nfinal class Gh with Base\n\n'
        'final class Mn\n\nfinal class Uv\n  void w(int a)\n\n'
        'export package:r/r.dart (whole library)\n  Portable from r\n',
    'q': '${qlib}final class Ef\n',
    'base': 'library package:base/base.dart\n\nmixin Base\n  void k()\n',
  };
  final left = uncoveredBreaks(
    released: released,
    current: current,
    table: read,
  ).map((MigrationBreak b) => '${b.package}:${breakSymbol(b.change)}').toSet();
  const want = <String>{'p:Mn.o', 'p:Uv.w', 'q:Ef.x', 'p_away:p_away'};
  if (left.length != want.length || !left.containsAll(want)) {
    broken.add((
      'migration coverage',
      'left $left uncovered, where only $want have no entry: a rename '
          'covers its old name, a member covers only itself, an inherited '
          'member and a re-exported move are no breaks, and a gone package '
          'needs naming',
    ));
  }
  for (final (what, want) in const <(String, bool)>[
    (
      'the declaration changed: final class A implements B -> '
          'final class A with B, C',
      true,
    ),
    (
      'the declaration changed: abstract base class G -> '
          'abstract base class G extends E',
      true,
    ),
    ('the declaration changed: class A implements B -> class A with B', false),
    (
      'the declaration changed: final class A implements B -> '
          'final class A with C',
      false,
    ),
    (
      'the declaration changed: final class A -> sealed class A extends B',
      false,
    ),
  ]) {
    if (onlyGainedSupertypes(what) != want) {
      broken.add((
        'migration supertypes',
        '${want ? 'missed' : 'took'} "$what" as only gaining supertypes',
      ));
    }
  }
  for (final (what, want) in const <(String, bool)>[
    ('Ab.Ab changed: Ab(this.x) -> Ab(int y)', true),
    (
      'Ab.Ab changed: const Ab({this.x = 1}) -> '
          'const Ab({int x = 1, bool y = false})',
      true,
    ),
    ('Ab.Ab changed: Ab({this.x = 1}) -> Ab({int x = 2})', false),
    ('Ab.Ab changed: Ab({this.x}) -> Ab({required int x})', false),
    ('Ab.Ab changed: Ab(this.x) -> Ab(this.x, this.y)', false),
    ('Ab.f changed: void f(int a) -> void f(int a, {int b = 0})', false),
  ]) {
    if (constructorCalledTheSame('Ab', what) != want) {
      broken.add((
        'migration constructors',
        '${want ? 'missed' : 'took'} "$what" as a constructor every call '
            'still fits',
      ));
    }
  }
  if (tableStamp('a') == tableStamp('b') || tableStamp('') != tableStamp('')) {
    broken.add(('table stamp', 'is not a function of the text alone'));
  }

  // The kinds wave M added, and what an entry may not say.
  const kinds = '''
from: 0.1.0
to: 1.0.0
entries:
  - id: k-regroup
    package: p
    symbol: View
    kind: regroup
    into: view
    options: ViewOptions
    arguments: [fov]
  - id: k-regroup-bare
    package: p
    symbol: View
    kind: regroup
    into: view
  - id: k-internal
    package: p
    symbol: Stage
    kind: internal
    instead: >-
      Use `Kit`.
  - id: k-internal-member
    package: p
    symbol: Stage.run
    kind: internal
  - id: k-wave
    package: p
    symbol: Loop
    kind: manual
    guidance: >-
      `Loop` is gone (wave 3); use `EngineLoop`.
  - id: k-throw
    package: p
    symbol: load
    kind: nullToThrow
    exception: NotFound
''';
  final readKinds = readMigrationTable(kinds);
  final kindProblems = migrationTableProblems(
    readKinds,
  ).map(((int, String) p) => p.$2).toList();
  final wantKinds = <String>[
    'k-regroup-bare` is a regroup with no `options`',
    'k-regroup-bare` is a regroup with no `arguments`',
    'names the member `Stage.run`',
    'says "(wave 3)"',
  ];
  if (kindProblems.length != wantKinds.length ||
      !wantKinds.every(
        (String w) => kindProblems.any((String p) => p.contains(w)),
      )) {
    broken.add((
      'migration kinds',
      'found $kindProblems where only $wantKinds are wrong',
    ));
  }
  final ceiling = manualCeilingProblems(
    <MigrationTable>[readKinds, read],
    ceiling: 1,
    allowlist: const <String, String>{'p-gone': 'no entry'},
  );
  if (ceiling.length != 2 ||
      ceiling.first.$1 != 'p-ef-g' ||
      ceiling.last.$1 != 'p-gone') {
    broken.add((
      'manual ceiling',
      'found $ceiling where the second manual entry is past a ceiling of 1 '
          'and the allowlist names an entry that is not there',
    ));
  }
  for (final (text, want) in const <(String, String?)>[
    ('`Kind` has a new case, `Other`: a `switch` …', 'enumToClass'),
    ('`load` throws `NotFound` where it returned null.', 'nullToThrow'),
    ('`size` is a class now: `.\$1` is `.width`.', 'recordToClass'),
    ('`fov` moved into `ViewOptions`.', 'regroup'),
    ('Call `h` instead.', null),
  ]) {
    if (automatableKind(text) != want) {
      broken.add((
        'manual ceiling',
        'read "$text" as ${automatableKind(text)}, not $want',
      ));
    }
  }
  const counts = (entries: 1538, byHand: 341, internal: 380);
  for (final (text, problems) in const <(String, int)>[
    ('1.0 changed the 0.8 API in about two\nhundred places.', 1),
    ('The table has 1 538 entries, 341 by hand.', 0),
    ('The table has 1538 entries, 720 by hand.', 1),
    ('Version 1.0 runs on 3 platforms.', 0),
  ]) {
    final found = migrationNumberProblems(text, counts: counts);
    if (found.length != problems) {
      broken.add((
        'migration numbers',
        'found $found in "$text", where $problems are wrong',
      ));
    }
  }
  return broken;
}
