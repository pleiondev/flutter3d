/// Writes and checks `api/<package>.api` for every published package.
///
/// ```
/// cd tool/api
/// dart run api_snapshot                      # check every published package
/// dart run api_snapshot --update             # rewrite every snapshot
/// dart run api_snapshot --update flutter3d   # rewrite one
/// dart run api_snapshot --print flutter3d    # print one, write nothing
/// dart run api_snapshot --diff old.api new.api
///                                            # classify two snapshots
/// ```
///
/// `--check` is the default. It exits 1 when a committed snapshot differs
/// from what the source makes, printing each difference classified the way
/// `tool/structure/api.dart` classifies it — an addition or a break — and the
/// release that change asks for. `--brief` makes that one line per package,
/// for the structure rule that runs this.
///
/// **Why every package.** From 1.0.0 every published package is under strict
/// semver. A parameter renamed breaks every caller that names it, and a
/// member added to a type somebody implements breaks that somebody — and both
/// compile cleanly here, because the callers and implementers in this
/// repository are updated alongside. Nothing in the ordinary test run notices
/// that a release just broke somebody else. The snapshot does, and `--update`
/// is the one way past it: the moment somebody has to say what the version
/// number says.
library;

import 'dart:io';

import 'package:api_snapshot/api_snapshot.dart';

import '../../structure/api.dart';

const String _usage = '''
Writes and checks api/<package>.api for every published package.

  dart run api_snapshot [--check] [--brief] [package ...]
  dart run api_snapshot --update [package ...]
  dart run api_snapshot --print <package>
  dart run api_snapshot --diff <old.api> <new.api>
''';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }
  final named = args.where((String a) => !a.startsWith('--')).toList();

  if (args.contains('--diff')) {
    if (named.length != 2) {
      stderr.write(_usage);
      exitCode = 2;
      return;
    }
    final changes = classifyApi(
      File(named[0]).readAsStringSync(),
      File(named[1]).readAsStringSync(),
    );
    stdout.writeln(describeApiChanges(changes));
    return;
  }

  final root = repositoryRootFrom(Directory.current);
  final packages = repositoryPackages(root);
  final unknown = named.where((String n) => !packages.containsKey(n));
  if (unknown.isNotEmpty) {
    stderr.writeln('no package named ${unknown.join(', ')}\n\n$_usage');
    exitCode = 2;
    return;
  }
  final wanted = named.isNotEmpty
      ? named
      : (packages.keys.where((String n) => isPublished(packages[n]!)).toList()
          ..sort());
  final snapshotter = ApiSnapshotter(packages);

  if (args.contains('--print')) {
    for (final name in wanted) {
      stdout.write(snapshotter.snapshot(name));
    }
    return;
  }

  final update = args.contains('--update');
  final brief = args.contains('--brief');
  var stale = 0;
  for (final name in wanted) {
    final current = snapshotter.snapshot(name);
    final file = File('${packages[name]!.path}/${snapshotPathOf(name)}');
    final committed = file.existsSync() ? file.readAsStringSync() : null;
    if (committed == current) continue;
    if (update) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(current);
      stdout.writeln('wrote ${_where(root, file)}');
      continue;
    }
    stale++;
    if (committed == null) {
      stdout.writeln(
        brief
            ? '$name\tthere is no ${snapshotPathOf(name)}'
            : '$name: there is no ${snapshotPathOf(name)}.',
      );
      continue;
    }
    final changes = classifyApi(committed, current);
    if (brief) {
      final breaking = changes.where((ApiChange c) => c.bump == Bump.major);
      stdout.writeln(
        '$name\t${snapshotPathOf(name)} is not what the source makes: '
        '${breaking.length} breaking, ${changes.length - breaking.length} '
        'other${changes.isEmpty ? ' (only the text moved)' : ''}',
      );
    } else {
      stdout
        ..writeln(
          '$name: ${snapshotPathOf(name)} is not what the source makes.',
        )
        ..writeln(describeApiChanges(changes))
        ..writeln();
    }
  }
  if (stale > 0) {
    if (!brief) {
      stdout.writeln(
        'If a change is deliberate, decide the version it needs, write it in '
        'the CHANGELOG (a break under a "**Breaking:**" entry), and run '
        '`dart run api_snapshot --update <package>` in tool/api.',
      );
    }
    exitCode = 1;
  }
}

String _where(Directory root, File file) =>
    file.absolute.path.substring(root.absolute.path.length + 1);
