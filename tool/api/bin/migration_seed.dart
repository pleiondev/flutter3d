/// Lists every break since the last release that the open migration table
/// does not cover yet, and drafts an entry for each.
///
/// The open table is the newest one whose release is not tagged yet:
/// `0.8_to_1.0.yaml` until `v1.0.0-rc.1`, then the table that starts at
/// that release. When every table is closed it says how to start the next.
///
/// ```
/// cd tool/api
/// dart run api_snapshot:migration_seed            # print the drafts
/// dart run api_snapshot:migration_seed --append   # add them to the table
/// ```
///
/// The breaks are the ones the structure rule `every break since the last
/// release has its migration` reads: `classifyApi` between the release's
/// snapshots under `tool/api/baseline/<tag>/` and each published package's
/// `api/<package>.api` now, less what `tool/structure/migration.dart` says
/// is no break to a caller. One draft per top-level name, under the package
/// that declared it at the release — a facade re-exporting it is covered by
/// the same entry.
///
/// **A draft is a guess, and says so.** The kind is read off the break's
/// wording: a type that became a `base mixin class` is `implementsToWith`, a
/// new case of a sealed type or a new enum value is `manual`, a constant
/// whose value moved is `none`, a declaration gone beside a new one with the
/// same members is a `rename`. Anything it cannot place is `manual`. Every
/// text a person has to write is `TODO`, which the structure rule refuses —
/// so `--append` cannot make the rule pass by itself.
library;

import 'dart:io';

import 'package:api_snapshot/api_snapshot.dart';

import '../../structure/api.dart';
import '../../structure/migration.dart';

void main(List<String> args) {
  final root = repositoryRootFrom(Directory.current);
  final tables =
      Directory('${root.path}/packages/flutter3d_build/lib/migrations')
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  if (tables.isEmpty) {
    stderr.writeln('no migration table under flutter3d_build/lib/migrations');
    exitCode = 1;
    return;
  }
  String? git(List<String> args) {
    try {
      final result = Process.runSync('git', args, workingDirectory: root.path);
      return result.exitCode == 0 ? result.stdout as String : null;
    } on ProcessException {
      return null;
    }
  }

  // The open table: the newest one whose release is not tagged. A tagged
  // table is closed (the structure rule `a migration table is closed once
  // its release is tagged`), and the breaks after it start a new one.
  final tags = <String>{
    for (final line in (git(<String>['tag', '--list', 'v*']) ?? '').split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  };
  final texts = <String, String>{
    for (final f in tables) f.uri.pathSegments.last: f.readAsStringSync(),
  };
  final open = openMigrationTable(texts, tags: tags);
  if (open == null) {
    final (_, last) = newestMigrationTable(texts)!;
    stderr.writeln(
      'every migration table is closed: ${last.to} is tagged. Start the '
      'next one as `packages/flutter3d_build/lib/migrations/'
      '${last.to}_to_<next>.yaml`, with the header of the last table, '
      '`from: ${last.to}`, `to: <next>` and an empty `entries:`, then run '
      'this again',
    );
    exitCode = 1;
    return;
  }
  final tableFile = tables.firstWhere(
    (File f) => f.uri.pathSegments.last == open,
  );
  final table = readMigrationTable(texts[open]!);
  // The release's API: a baseline written for it (a release from before
  // the snapshots), or the snapshots at its tag.
  final baseline = Directory('${root.path}/tool/api/baseline/v${table.from}');
  final packages = repositoryPackages(root);
  final released = <String, String>{
    if (baseline.existsSync())
      for (final f in baseline.listSync().whereType<File>())
        if (f.path.endsWith('.api'))
          f.uri.pathSegments.last.replaceAll('.api', ''): f.readAsStringSync()
        else
          for (final MapEntry(key: name, value: dir) in packages.entries)
            if (git(<String>[
                  'show',
                  'v${table.from}:${dir.path.substring(root.path.length + 1)}/api/$name.api',
                ])
                case final String text)
              name: text,
  };
  if (released.isEmpty) {
    stderr.writeln(
      'no API for ${table.from}: neither a baseline (`dart run '
      'api_snapshot:api_baseline v${table.from} baseline/v${table.from}` '
      'in tool/api) nor snapshots at the tag v${table.from}',
    );
    exitCode = 1;
    return;
  }
  final current = <String, String>{
    for (final MapEntry(key: name, value: dir) in packages.entries)
      if (isPublished(dir) && File('${dir.path}/api/$name.api').existsSync())
        name: File('${dir.path}/api/$name.api').readAsStringSync(),
  };
  final left = uncoveredBreaks(
    released: released,
    current: current,
    table: table,
  );
  if (left.isEmpty) {
    stdout.writeln(
      'every break since ${table.from} has an entry in '
      '${tableFile.uri.pathSegments.last}',
    );
    return;
  }

  // Where each name was declared at the release, so a facade's break goes
  // under the package that owns the name.
  final owner = <String, String>{};
  for (final MapEntry(key: package, value: text) in released.entries) {
    for (final library in parseApi(text).values) {
      for (final name in library.declarations.keys) {
        owner.putIfAbsent(name, () => package);
      }
    }
  }
  final grouped = <String, List<MigrationBreak>>{};
  for (final b in left) {
    final package = owner[b.change.subject] ?? b.package;
    (grouped['$package ${b.change.subject}'] ??= <MigrationBreak>[]).add(b);
  }
  final now = <String, Map<String, ApiLibrary>>{
    for (final e in current.entries) e.key: parseApi(e.value),
  };
  final then = <String, Map<String, ApiLibrary>>{
    for (final e in released.entries) e.key: parseApi(e.value),
  };

  final out = StringBuffer();
  for (final key in grouped.keys.toList()..sort()) {
    final [package, subject] = key.split(' ');
    final breaks = grouped[key]!;
    final whats = <String>{for (final b in breaks) b.change.what};
    out
      ..writeln()
      ..writeln(
        '  # ${breaks.length} break(s), seen in '
        '${{for (final b in breaks) b.package}.join(', ')}:',
      );
    for (final w in whats.take(6)) {
      out.writeln('  #   ${w.length > 160 ? '${w.substring(0, 160)}…' : w}');
    }
    final id =
        '${package.replaceFirst('flutter3d_', '')}-'
        '${subject.replaceAll(RegExp(r'[^\w]+'), '-')}';
    out
      ..writeln('  - id: $id')
      ..writeln('    package: $package')
      ..writeln('    symbol: $subject');
    final draft = _draft(subject, whats, then[package], now[package], now);
    for (final line in draft) {
      out.writeln('    $line');
    }
  }
  if (args.contains('--append')) {
    tableFile.writeAsStringSync(
      '${tableFile.readAsStringSync().trimRight()}\n$out',
    );
    stdout.writeln(
      'appended ${grouped.length} drafts to ${tableFile.path}; replace each '
      'TODO, then run the structure scan',
    );
  } else {
    stdout
      ..writeln('# ${grouped.length} names with breaks no entry covers:')
      ..write(out);
  }
}

/// The kind and keys of a draft entry, read off the breaks' wording.
///
/// Where the wording settles it — a name that now lives in another library,
/// a new case of a sealed type, members an implementer now owes — the draft
/// is written out; where a person has to decide, it says TODO.
List<String> _draft(
  String subject,
  Set<String> whats,
  Map<String, ApiLibrary>? then,
  Map<String, ApiLibrary>? now,
  Map<String, Map<String, ApiLibrary>> everywhere,
) {
  List<String> block(String key, String text) => <String>[
    '$key: >-',
    for (final line in _wrap(text)) '  $line',
  ];

  if (whats.any(
    (String w) =>
        w.contains('can no longer be implemented') && w.contains('mixin class'),
  )) {
    return const <String>['kind: implementsToWith'];
  }

  // Gone from where it was, declared somewhere now: an import to change.
  if (whats.every(
    (String w) =>
        w == 'gone' ||
        w == 'no longer re-exported' ||
        w.startsWith('no longer re-exported through '),
  )) {
    final home = _declaredAt(subject, everywhere);
    if (home != null) return <String>['kind: moved', 'to: $home'];
  }

  final sealedCases = <String>{
    for (final w in whats)
      if (RegExp(r'^new subtype of sealed (\w+)').firstMatch(w) case final m?)
        m.group(1)!,
  };
  if (sealedCases.isNotEmpty && whats.length == sealedCases.length) {
    final parent = sealedCases.first;
    return <String>[
      'kind: manual',
      ...block(
        'guidance',
        '`$parent` has a new case, `$subject`: a `switch` over a `$parent` '
            'that names every case needs one for it, or a wildcard.',
      ),
    ];
  }
  final values = whats.where((String w) => w.startsWith('the values changed'));
  if (values.isNotEmpty && whats.length == 1) {
    final m = RegExp(
      r'values: ([^)]*?) -> values: ([^)]*?)\)',
    ).firstMatch(values.single);
    final added = m == null
        ? const <String>[]
        : m
              .group(2)!
              .split(', ')
              .toSet()
              .difference(m.group(1)!.split(', ').toSet())
              .toList();
    final removed = m == null
        ? const <String>[]
        : m
              .group(1)!
              .split(', ')
              .toSet()
              .difference(m.group(2)!.split(', ').toSet())
              .toList();
    if (removed.isEmpty) {
      return <String>[
        'kind: manual',
        ...block(
          'guidance',
          '`$subject` has new values (${added.map((String v) => '`$v`').join(', ')}): '
              'a `switch` over a `$subject` that names every value needs a '
              'case for each, or a wildcard.',
        ),
      ];
    }
  }

  if (whats.every(
    // A constant, not a const constructor: `const int k = 2`.
    (String w) =>
        RegExp(r' changed: (static )?const [\w<>?, ]+ [\w$]+ = ').hasMatch(w),
  )) {
    return <String>[
      'kind: none',
      ...block(
        'reason',
        'Only the value of the constant moved; code that reads `$subject` '
            'gets the new one. TODO: confirm nothing outside hard-codes it.',
      ),
    ];
  }

  final owed = <String>[
    for (final w in whats)
      if (RegExp(
            r'^\w+\.(\w+) is new on a type outside code may implement',
          ).firstMatch(w)
          case final m?)
        m.group(1)!,
  ];
  if (owed.isNotEmpty && owed.length == whats.length) {
    return <String>[
      'kind: manual',
      ...block(
        'guidance',
        'Only code that implements `$subject` has anything to do: it now '
            'has to provide ${owed.map((String o) => '`$o`').join(', ')}. '
            'Code that calls a `$subject` needs no change.',
      ),
    ];
  }

  if (whats.contains('gone') && then != null && now != null) {
    final rename = _renameOf(subject, then, now);
    if (rename != null) {
      return <String>['kind: rename', 'to: $rename  # TODO: confirm'];
    }
  }
  return const <String>[
    'kind: manual',
    'guidance: >-',
    '  TODO: what a caller writes instead.',
  ];
}

/// The public library that declares [name] now, preferring a package's
/// main library, or null when none does.
String? _declaredAt(
  String name,
  Map<String, Map<String, ApiLibrary>> everywhere,
) {
  final found = <String>[
    for (final libraries in everywhere.values)
      for (final library in libraries.values)
        if (library.declarations.containsKey(name)) library.uri,
  ];
  if (found.isEmpty) return null;
  found.sort((String a, String b) {
    bool main(String u) {
      final m = RegExp(r'^package:(\w+)/(\w+)\.dart$').firstMatch(u);
      return m != null && m.group(1) == m.group(2);
    }

    return (main(a) ? 0 : 1).compareTo(main(b) ? 0 : 1);
  });
  return found.first;
}

/// [text] in lines short enough for the table.
List<String> _wrap(String text) {
  final lines = <String>[];
  var line = StringBuffer();
  for (final word in text.split(' ')) {
    if (line.length + word.length + 1 > 72 && line.isNotEmpty) {
      lines.add(line.toString());
      line = StringBuffer();
    }
    if (line.isNotEmpty) line.write(' ');
    line.write(word);
  }
  if (line.isNotEmpty) lines.add(line.toString());
  return lines;
}

/// A new declaration of the same kind with the same members as [subject]
/// had, in the same library: the likeliest rename.
String? _renameOf(
  String subject,
  Map<String, ApiLibrary> then,
  Map<String, ApiLibrary> now,
) {
  for (final MapEntry(key: uri, value: library) in then.entries) {
    final was = library.declarations[subject];
    if (was == null) continue;
    final after = now[uri];
    if (after == null) continue;
    Set<String> names(ApiBlock b) => b.members.map(memberName).toSet();
    final before = names(was);
    for (final MapEntry(key: name, value: block)
        in after.declarations.entries) {
      if (library.declarations.containsKey(name)) continue;
      final members = names(block);
      final shared = members.intersection(before).length;
      if (before.isNotEmpty && shared * 4 >= before.length * 3) return name;
    }
  }
  return null;
}
