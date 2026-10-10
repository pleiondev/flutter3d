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

  /// The table that migrates from [from] (`0.8`, or `0.8.5`), shipped in
  /// this package's `lib/migrations/`.
  static Future<MigrationTable> shipped({String from = '0.8'}) async {
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:flutter3d_build/migrations/'),
    );
    if (lib == null) {
      throw StateError('flutter3d_build is not resolvable from here');
    }
    final dir = Directory.fromUri(lib);
    final wanted = from.split('.').take(2).join('.');
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.startsWith('${wanted}_to_') && name.endsWith('.yaml')) {
        return MigrationTable.parse(file.readAsStringSync(), source: file.path);
      }
    }
    throw StateError('no migration table from $from in ${dir.path}');
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

/// [node] with YAML's wrappers taken off.
Object? _plain(Object? node) => switch (node) {
  final YamlList list => <Object?>[for (final v in list) _plain(v)],
  final YamlMap map => <String, Object?>{
    for (final e in map.entries) '${e.key}': _plain(e.value),
  },
  _ => node,
};
