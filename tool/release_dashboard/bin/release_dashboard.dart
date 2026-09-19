/// One look at the state of a release, printed as JSON.
///
///     dart run tool/release_dashboard/bin/release_dashboard.dart --out state.json
///     dart run release_dashboard:release_dashboard --run publish,web
///
/// It reads the tree, asks git, GitHub, pub.dev and the modeller's server what
/// they say, runs the quick checks that have not judged this tree and prints
/// what it found. It stays running for as long as that takes and no longer, and
/// it opens no port: the page that shows the result is `page.html`, published
/// as an artifact, and whoever publishes the state is the one that ran this.
library;

import 'dart:convert';
import 'dart:io';

import 'package:release_dashboard/release_dashboard.dart';

const String _usage = '''
Usage: dart run release_dashboard:release_dashboard [options]

  --out <file>       Write the JSON there instead of printing it.
  --run <id,id>      Also run these checks, whatever they last said. The ids
                     are format, structure, plan, analyze, publish, web, ci.
  --root <path>      The repository (default: found from the current directory).
  --release <x.y.z>  The version the shelf is meant to carry (default 0.7.0).
  --no-auto          Do not run the quick checks that are out of date.
  -h, --help         This text.
''';

/// The nearest directory at or above [start] that is this repository's root:
/// the one that holds `tool/structure.dart`.
Directory? _findRoot(Directory start) {
  var dir = start.absolute;
  while (true) {
    if (File('${dir.path}/tool/structure.dart').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

Future<void> main(List<String> arguments) async {
  String? out;
  String? rootPath;
  var release = '0.7.0';
  var auto = true;
  final run = <String>{};

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      case '--out':
        out = arguments[++i];
      case '--run':
        run.addAll(arguments[++i].split(',').where((id) => id.isNotEmpty));
      case '--root':
        rootPath = arguments[++i];
      case '--release':
        release = arguments[++i];
      case '--no-auto':
        auto = false;
      default:
        stderr.write('Unknown option ${arguments[i]}\n$_usage');
        exitCode = 64;
        return;
    }
  }

  final root = rootPath != null
      ? Directory(rootPath)
      : _findRoot(Directory.current);
  if (root == null || !root.existsSync()) {
    stderr.writeln(
      'Not inside the repository: no tool/structure.dart above '
      '${Directory.current.path}. Pass --root.',
    );
    exitCode = 78;
    return;
  }

  final config = ReleaseConfig(release: release, tag: 'v$release');
  final gates = defaultGates(
    root,
  ).map((gate) => auto ? gate : gate.withoutAuto()).toList();
  final unknown = run.where((id) => !gates.any((g) => g.id == id));
  if (unknown.isNotEmpty) {
    stderr.writeln('No such check: ${unknown.join(', ')}');
    exitCode = 64;
    return;
  }

  final dashboard = Dashboard(
    root: root,
    config: config,
    sources: LocalSources(root, config),
    gates: gates,
    memory: File('${root.path}/.dart_tool/release_dashboard/results.json'),
  );

  final json = jsonEncode(await dashboard.look(run: run));
  if (out == null) {
    stdout.writeln(json);
  } else {
    File(out).writeAsStringSync(json);
    stderr.writeln('Wrote $out');
  }
}
