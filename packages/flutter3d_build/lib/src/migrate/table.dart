/// A migration table — `lib/migrations/<from>_to_<to>.yaml` — read with the
/// real YAML parser: what the `migrate` command and the generators work from.
///
/// The file's layout and its kinds are described at its top. The structure
/// scan reads the same file without a parser (`tool/structure/migration.dart`
/// in the repository); `tool/generate_migrations.dart` refuses a table the two
/// readers see differently.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:yaml/yaml.dart';
import '../build_exceptions.dart';

/// One entry of a migration table.
final class MigrationEntry {
  MigrationEntry(this.fields);

  /// Every key of the entry, as the YAML gave it: strings, lists, maps.
  final Map<String, Object?> fields;

  String get id => fields['id']! as String;
  String get kind => fields['kind']! as String;

  /// The package that declared [symbol] at the release migrated from.
  String get package => (fields['package'] as String?) ?? '';

  /// `Name`, `Name.member`, or a library URI.
  String get symbol => (fields['symbol'] as String?) ?? '';

  /// The top-level name [symbol] is about, or the URI.
  String get topName => symbol.contains(':') ? symbol : symbol.split('.').first;

  /// The member of [topName] it is about, or null.
  String? get member {
    if (symbol.contains(':')) return null;
    final dot = symbol.indexOf('.');
    return dot < 0 ? null : symbol.substring(dot + 1);
  }

  String? get to => fields['to'] as String?;
  String? get from => fields['from'] as String?;
  String? get name => fields['name'] as String?;
  String? get template => fields['template'] as String?;
  String? get guidance => fields['guidance'] as String?;
  String? get reason => fields['reason'] as String?;
  int? get wave => fields['wave'] as int?;

  /// An `internal` entry's word on what stays public in its place.
  String? get instead => fields['instead'] as String?;

  /// A `regroup`'s parameter that takes the options object.
  String? get into => fields['into'] as String?;

  /// A `regroup`'s options class.
  String? get options => fields['options'] as String?;

  /// A `nullToThrow`'s exception type.
  String? get exception => fields['exception'] as String?;

  /// A `regroup`'s named arguments that move into [options].
  List<String> get arguments => <String>[
    for (final a
        in (fields['arguments'] as List<Object?>?) ?? const <Object?>[])
      '$a',
  ];

  /// A `recordToClass`'s map from each record field (`$1`, `name`) to the
  /// class's getter.
  Map<String, String> get fieldMap => <String, String>{
    if (fields['fields'] case final Map<Object?, Object?> map)
      for (final e in map.entries) '${e.key}': '${e.value}',
  };

  /// The libraries a `rewrite`'s template needs in scope.
  List<String> get imports => <String>[
    for (final i in (fields['imports'] as List<Object?>?) ?? const <Object?>[])
      '$i',
  ];

  /// A `parameters` entry's changes, each a map.
  List<Map<String, Object?>> get changes => <Map<String, Object?>>[
    for (final c in (fields['changes'] as List<Object?>?) ?? const <Object?>[])
      if (c is Map)
        <String, Object?>{for (final e in c.entries) '${e.key}': e.value},
  ];

  /// What a person reads about this entry: its guidance, or its reason.
  String get text => (guidance ?? reason ?? '').trim();
}

/// A whole migration table.
final class MigrationTable {
  MigrationTable({
    required this.format,
    required this.from,
    required this.to,
    required this.guide,
    required this.date,
    required this.constraint,
    required this.versions,
    required this.renamedPackages,
    required this.removedPackages,
    required this.entries,
  });

  /// [text] read as a table; [source] names it in an error.
  factory MigrationTable.parse(String text, {String source = 'table'}) {
    final doc = loadYaml(text, sourceUrl: Uri.file(source));
    if (doc is! Map) {
      throw MigrationTableException('$source is not a YAML map');
    }
    Map<String, String> strings(Object? node) => <String, String>{
      if (node is Map)
        for (final e in node.entries) '${e.key}': '${e.value}',
    };
    final packages = doc['packages'] is Map
        ? doc['packages'] as Map
        : const <Object?, Object?>{};
    return MigrationTable(
      format: (doc['format'] as int?) ?? 1,
      from: '${doc['from']}',
      to: '${doc['to']}',
      guide: '${doc['guide'] ?? ''}',
      date: '${doc['date'] ?? ''}',
      constraint: '${packages['constraint'] ?? '^${doc['to']}'}',
      versions: strings(packages['versions']),
      renamedPackages: strings(packages['renamed']),
      removedPackages: strings(packages['removed']),
      entries: <MigrationEntry>[
        for (final e in (doc['entries'] as List<Object?>?) ?? const <Object?>[])
          if (e is Map)
            MigrationEntry(<String, Object?>{
              for (final f in e.entries) '${f.key}': _plain(f.value),
            }),
      ],
    );
  }

  /// Every table shipped in this package's `lib/migrations/`, as a [chain].
  static Future<List<MigrationTable>> shipped() async {
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:flutter3d_build/migrations/'),
    );
    if (lib == null) {
      throw StateError('flutter3d_build is not resolvable from here');
    }
    final dir = Directory.fromUri(lib);
    return chain(<MigrationTable>[
      for (final file in dir.listSync().whereType<File>())
        if (file.path.endsWith('.yaml'))
          MigrationTable.parse(file.readAsStringSync(), source: file.path),
    ]);
  }

  /// [tables] in the order a project crosses them: each one's `from` is the
  /// one before's `to`. The file names do not decide it, since
  /// `1.0.0-rc.10_to_…` sorts before `1.0.0-rc.2_to_…`.
  ///
  /// Throws a [StateError] naming the release where the chain breaks: a
  /// table that starts where no other ends would leave a project on that
  /// release with nothing to cross.
  static List<MigrationTable> chain(Iterable<MigrationTable> tables) {
    final ordered = tables.toList()
      ..sort(
        (MigrationTable a, MigrationTable b) => compareReleases(a.from, b.from),
      );
    for (var i = 1; i < ordered.length; i++) {
      if (compareReleases(ordered[i - 1].to, ordered[i].from) != 0) {
        throw StateError(
          'the migration tables do not chain: one ends at '
          '${ordered[i - 1].to} and the next starts at ${ordered[i].from}',
        );
      }
    }
    return ordered;
  }

  /// The tables of [chain] a project on [release] still has to cross: every
  /// one whose `to` is newer. A release the first table's `from` names only
  /// by its minor (`0.8.3` under `from: 0.8.5`) crosses it too.
  static List<MigrationTable> after(
    String release,
    List<MigrationTable> chain,
  ) => <MigrationTable>[
    for (final table in chain)
      if (compareReleases(table.to, release) > 0) table,
  ];

  /// [chain] read as one table, the way a project several releases behind
  /// crosses it in one run: the newest constraint and versions, every entry
  /// in order, and renames and moved libraries followed to where they end,
  /// so a package renamed twice goes straight to its last name.
  static MigrationTable merge(List<MigrationTable> chain) {
    if (chain.length == 1) return chain.single;
    final renamed = <String, String>{
      for (final table in chain) ...table.renamedPackages,
    };
    String follow(String name) {
      final seen = <String>{name};
      var at = name;
      for (var next = renamed[at]; next != null && seen.add(next);) {
        at = next;
        next = renamed[at];
      }
      return at;
    }

    final composed = <String, String>{
      for (final key in renamed.keys) key: follow(key),
    };
    final removed = <String, String>{
      for (final table in chain) ...table.removedPackages,
    };
    for (final MapEntry(:key, :value) in composed.entries) {
      if (removed[value] case final why?) removed[key] = why;
    }
    final last = chain.last;
    final merged = MigrationTable(
      format: last.format,
      from: chain.first.from,
      to: last.to,
      guide: last.guide,
      date: last.date,
      constraint: last.constraint,
      versions: <String, String>{for (final table in chain) ...table.versions},
      renamedPackages: composed,
      removedPackages: removed,
      entries: <MigrationEntry>[for (final table in chain) ...table.entries],
    );
    // An import moved by one table and moved again, or renamed with its
    // package, by a later one lands where the last one put it.
    return MigrationTable(
      format: merged.format,
      from: merged.from,
      to: merged.to,
      guide: merged.guide,
      date: merged.date,
      constraint: merged.constraint,
      versions: merged.versions,
      renamedPackages: merged.renamedPackages,
      removedPackages: merged.removedPackages,
      entries: <MigrationEntry>[
        for (final e in merged.entries)
          if (e.kind == 'import' && e.to != null)
            MigrationEntry(<String, Object?>{
              ...e.fields,
              'to': merged._settled(e.to!),
            })
          else
            e,
      ],
    );
  }

  /// [uri] moved by [movedUri] until nothing moves it further.
  String _settled(String uri) {
    final seen = <String>{uri};
    var at = uri;
    for (var next = movedUri(at); seen.add(next); next = movedUri(at)) {
      at = next;
    }
    return at;
  }

  final int format;
  final String from;
  final String to;

  /// The migration guide on the site.
  final String guide;

  /// The date each generated `dart fix` transform carries.
  final String date;

  /// What a dependency on a package of the engine moves to.
  final String constraint;

  /// Packages not on the engine's number, and what a dependency on each
  /// moves to.
  final Map<String, String> versions;
  final Map<String, String> renamedPackages;
  final Map<String, String> removedPackages;
  final List<MigrationEntry> entries;

  /// Whether [package] is one of this repository's: a dependency on it
  /// moves with the release.
  bool owns(String package) =>
      package == 'flutter3d' ||
      package.startsWith('flutter3d_') ||
      package.startsWith('flame_flutter3d') ||
      package.startsWith('flame_multiplayer') ||
      versions.containsKey(package) ||
      renamedPackages.containsKey(package) ||
      removedPackages.containsKey(package);

  /// The constraint a dependency on [package] moves to.
  String constraintFor(String package) => versions[package] ?? constraint;

  /// The `import` entries, from URI to URI: a whole library, or a directory
  /// when the URI ends in `/`.
  Map<String, String> get importMoves => <String, String>{
    for (final e in entries)
      if (e.kind == 'import' && e.from != null && e.to != null) e.from!: e.to!,
  };

  /// [uri] where a migrated project imports it: the `import` entry that
  /// names it, the longest directory entry it is under, or its package's
  /// new name; [uri] itself when none of them moved it.
  String movedUri(String uri) {
    final moves = importMoves;
    if (moves[uri] case final to?) return to;
    final directories = <String>[
      for (final from in moves.keys)
        if (from.endsWith('/') && uri.startsWith(from)) from,
    ]..sort((String a, String b) => b.length.compareTo(a.length));
    if (directories.isNotEmpty) {
      final from = directories.first;
      return '${moves[from]}${uri.substring(from.length)}';
    }
    final package = RegExp(r'^package:(\w+)/').firstMatch(uri)?.group(1);
    if (renamedPackages[package] case final renamed?) {
      return uri.replaceFirst('package:$package/', 'package:$renamed/');
    }
    return uri;
  }

  /// The link to [entry]'s line in the guide.
  String linkFor(MigrationEntry entry) => '$guide#${entry.id}';
}

/// Two release numbers in semver's order: by the three numbers (a missing
/// one is 0, so `0.8` is `0.8.0`), then a pre-release below its release,
/// its parts compared as numbers where both are (`rc.2` < `rc.10`).
int compareReleases(String a, String b) {
  (List<int>, List<String>) parts(String v) {
    final core = v.trim().split('+').first;
    final pre = core.indexOf('-');
    final numbers = (pre < 0 ? core : core.substring(0, pre)).split('.');
    return (
      <int>[
        for (var i = 0; i < 3; i++)
          int.tryParse(numbers.elementAtOrNull(i) ?? '') ?? 0,
      ],
      pre < 0 ? const <String>[] : core.substring(pre + 1).split('.'),
    );
  }

  final (x, xPre) = parts(a);
  final (y, yPre) = parts(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
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

/// The release a project is on, read from its `pubspec.lock`: the oldest
/// version it resolves of a package [tables] move with the engine's number.
/// A package on its own number (`pad_input`) says nothing about the
/// engine's. Null for a lock that names none, or is no lock.
String? lockedRelease(String lock, List<MigrationTable> tables) {
  final Object? doc;
  try {
    doc = loadYaml(lock);
  } on YamlException {
    return null;
  }
  if (doc is! Map || doc['packages'] is! Map) return null;
  final own = <String>{for (final t in tables) ...t.versions.keys};
  final found = <String>[
    for (final MapEntry(:key, :value) in (doc['packages'] as Map).entries)
      if (value is Map &&
          value['version'] != null &&
          !own.contains('$key') &&
          tables.any((MigrationTable t) => t.owns('$key')))
        '${value['version']}',
  ]..sort(compareReleases);
  return found.firstOrNull;
}

/// [node] with YAML's wrappers taken off.
Object? _plain(Object? node) => switch (node) {
  final YamlList list => <Object?>[for (final v in list) _plain(v)],
  final YamlMap map => <String, Object?>{
    for (final e in map.entries) '${e.key}': _plain(e.value),
  },
  _ => node,
};
