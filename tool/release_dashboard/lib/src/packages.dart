/// Reading the workspace's packages the way `pub publish` will.
///
/// **A regular expression per field and no YAML parser**, for the reason the
/// package has no dependencies: what is asked of a pubspec here is three
/// things, all of them one line, and `tool/structure.dart` reads them the same
/// way. A pubspec with a multi-line version would be a broken pubspec.
library;

import 'dart:io';

import 'model.dart';

/// Whether `^constraint` admits [version].
///
/// The caret means "up to the next breaking change", and before 1.0 a breaking
/// change is the minor number: `^0.7.0` is `>=0.7.0 <0.8.0`, which is why
/// `^0.6.0` does not reach 0.7.0 and moving one package forces every dependent
/// to edit its pubspec. Anything that is not a plain caret, an `any`, a range,
/// is answered null: the honest reply is that it was not judged.
bool? caretCovers(String constraint, String version) {
  final wanted = _triple(
    constraint.startsWith('^') ? constraint.substring(1) : '',
  );
  final actual = _triple(version);
  if (wanted == null || actual == null) return null;

  if (_compare(actual, wanted) < 0) return false;
  final ceiling = wanted.$1 > 0
      ? (wanted.$1 + 1, 0, 0)
      : wanted.$2 > 0
      ? (0, wanted.$2 + 1, 0)
      : (0, 0, wanted.$3 + 1);
  return _compare(actual, ceiling) < 0;
}

(int, int, int)? _triple(String text) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(text.trim());
  if (match == null) return null;
  return (
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

int _compare((int, int, int) a, (int, int, int) b) {
  if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
  if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
  return a.$3.compareTo(b.$3);
}

/// The value of a pubspec's top-level `version:` line, without a build number.
String? versionOf(String pubspec) => RegExp(
  r'^version:\s*([^\s+#]+)',
  multiLine: true,
).firstMatch(pubspec)?.group(1);

/// Every `name: ^x.y.z` under `dependencies:` or `dev_dependencies:`.
///
/// Only sibling names matter to the caller, so the filter is theirs; this
/// answers what a pubspec said. A dependency written over several lines, a path
/// or a git one, has no caret here and is left out.
Map<String, String> constraintsIn(String pubspec) {
  final found = <String, String>{};
  String? section;
  for (final line in pubspec.split('\n')) {
    final top = RegExp(r'^([a-z_]+):').firstMatch(line);
    if (top != null) {
      section = top.group(1);
      continue;
    }
    if (section != 'dependencies' && section != 'dev_dependencies') continue;
    final entry = RegExp(r'^  ([a-z0-9_]+):\s*(\^?\d[^\s#]*)').firstMatch(line);
    if (entry != null) found[entry.group(1)!] = entry.group(2)!;
  }
  return found;
}

/// The first `## ` heading of a changelog.
String changelogTopOf(String changelog) {
  for (final line in changelog.split('\n')) {
    if (line.startsWith('## ')) return line.substring(3).trim();
  }
  return '';
}

/// Reads every package under `<root>/packages`.
///
/// [release] is the number the shelf is meant to carry and [ownLine] the names
/// that keep one of their own; everything else is judged against the first.
/// A package's `problems` are the reasons it would not go out as it stands,
/// each one a sentence a person can act on.
Future<PackagesSnapshot> scanPackages(
  Directory root, {
  required String release,
  required Set<String> ownLine,
}) async {
  final packagesDir = Directory('${root.path}/packages');
  if (!packagesDir.existsSync()) {
    return PackagesSnapshot(
      rows: const <PackageRow>[],
      ghostDirectories: const <String>[],
      release: release,
    );
  }

  final directories = packagesDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final ghosts = <String>[];
  final pubspecs = <String, String>{};
  for (final directory in directories) {
    final name = directory.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      pubspecs[name] = pubspec.readAsStringSync();
    } else {
      ghosts.add(name);
    }
  }

  final versions = <String, String>{
    for (final MapEntry(:key, :value) in pubspecs.entries)
      key: versionOf(value) ?? '',
  };

  final rows = <PackageRow>[];
  for (final MapEntry(key: name, value: pubspec) in pubspecs.entries) {
    final version = versions[name]!;
    final isOwn = ownLine.contains(name);
    final problems = <String>[];

    if (version.isEmpty) problems.add('the pubspec names no version');
    if (!isOwn && version.isNotEmpty && version != release) {
      problems.add('is $version, and the shelf is $release');
    }

    final changelogFile = File('${packagesDir.path}/$name/CHANGELOG.md');
    final top = changelogFile.existsSync()
        ? changelogTopOf(changelogFile.readAsStringSync())
        : '';
    if (version.isNotEmpty && top != version) {
      problems.add(
        top.isEmpty
            ? 'CHANGELOG.md has no version heading'
            : 'CHANGELOG.md starts at "$top", not $version',
      );
    }

    for (final MapEntry(key: sibling, value: constraint) in constraintsIn(
      pubspec,
    ).entries) {
      final siblingVersion = versions[sibling];
      if (siblingVersion == null || siblingVersion.isEmpty) continue;
      if (caretCovers(constraint, siblingVersion) == false) {
        problems.add(
          'asks $sibling $constraint, which does not admit its $siblingVersion',
        );
      }
    }

    rows.add(
      PackageRow(
        name: name,
        version: version,
        changelogTop: top,
        ownLine: isOwn,
        problems: problems,
      ),
    );
  }

  return PackagesSnapshot(
    rows: rows,
    ghostDirectories: ghosts,
    release: release,
  );
}
