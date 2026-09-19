/// A live page over the state of a release.
///
///     dart run tool/release_dashboard/bin/release_dashboard.dart
///     dart run release_dashboard:release_dashboard --port 9000
///
/// Open the address it prints. Nothing is installed and nothing is written: it
/// reads the tree, runs the repository's own scripts on request and on change,
/// and asks git, GitHub, pub.dev and the modeller's own server what they say.
library;

import 'dart:async';
import 'dart:io';

import 'package:release_dashboard/release_dashboard.dart';

const String _usage = '''
Usage: dart run release_dashboard:release_dashboard [options]

  --port <n>        Where to listen, on 127.0.0.1 only (default 8765).
  --root <path>     The repository (default: found from the current directory).
  --release <x.y.z> The version the shelf is meant to carry (default 0.7.0).
  --no-auto         Do not run the quick checks when the tree changes.
  -h, --help        This text.
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
  var port = 8765;
  String? rootPath;
  var release = '0.7.0';
  var auto = true;

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      case '--port':
        port = int.tryParse(arguments[++i]) ?? port;
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
  final dashboard = Dashboard(
    root: root,
    config: config,
    sources: LocalSources(root, config),
    gates: gates,
  );

  final page = File.fromUri(Platform.script.resolve('../web/index.html'));
  if (!page.existsSync()) {
    stderr.writeln('The page is missing: ${page.path}');
    exitCode = 66;
    return;
  }

  final server = await serveDashboard(dashboard, page: page, port: port);
  stdout.writeln(
    'Release $release, in ${root.path}\n'
    'http://127.0.0.1:${server.port}/   (Ctrl-C to stop)',
  );

  await dashboard.start();

  await ProcessSignal.sigint.watch().first;
  await dashboard.close();
  await server.close(force: true);
}
