// The `flutter3d` command: one entry point for the tools this package has.
//
//   dart pub global activate flutter3d_build
//   flutter3d convert Assets/Prefabs/Crate.prefab -o assets_src/imported
//   flutter3d doctor
//   flutter3d help convert
//
// Each subcommand is the same code its `dart run flutter3d_build:<name>`
// entry point runs: `migrate`, `create`, `init`, `plugins` and `lights` call
// those files' own `main`, so the two spellings cannot drift apart.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter3d_build/cli.dart';

import 'create.dart' as create;
import 'init.dart' as init;
import 'lights.dart' as lights;
import 'migrate.dart' as migrate;
import 'plugins.dart' as plugins;

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(flutter3dUsage);
    exitCode = CliExit.usage;
    return;
  }
  final command = arguments.first;
  final rest = arguments.sublist(1);
  switch (command) {
    case 'convert':
      exitCode = await runConvertCommand(rest);
    case 'doctor':
      exitCode = runDoctor(rest);
    case 'create':
      if (rest.firstOrNull == 'project') {
        _createProject(rest.sublist(1));
      } else {
        create.main(rest);
      }
    case 'init':
      await init.main(rest);
    case 'plugins':
      plugins.main(rest);
    case 'migrate':
      await migrate.main(rest);
    case 'lights':
      await lights.main(rest);
    case 'help' || '-h' || '--help':
      if (rest.firstOrNull == '--surface') {
        stdout.write(cliSurface());
      } else {
        await _help(rest.firstOrNull);
      }
    case '--version':
      stdout.writeln('flutter3d_build ${await _packageVersion()}');
    default:
      stderr.writeln('Unknown command "$command".\n\n$flutter3dUsage');
      exitCode = CliExit.usage;
  }
}

Future<void> _help(String? command) async {
  switch (command) {
    case null:
      stdout.writeln(flutter3dUsage);
    case 'convert':
      stdout.writeln(convertUsage);
    case 'doctor':
      runDoctor(const <String>['--help']);
    case 'create':
      stdout.writeln(createUsage);
    case 'migrate' || 'init' || 'lights':
      // Their own usage, from their own parsers.
      // Each prints its usage as the answer to an option it does not
      // take, and says so in its exit code; asked for, it is not an error.
      switch (command) {
        case 'migrate':
          await migrate.main(const <String>['--help']);
        case 'init':
          await init.main(const <String>['--help']);
        default:
          await lights.main(const <String>['--help']);
      }
      exitCode = 0;
    case 'plugins':
      stdout.writeln(pluginsUsage);
    default:
      stderr.writeln('No command "$command".\n\n$flutter3dUsage');
      exitCode = CliExit.usage;
  }
}

void _createProject(List<String> arguments) {
  final positional = <String>[];
  String? name;
  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == '--name' && i + 1 < arguments.length) {
      name = arguments[++i];
    } else if (!arguments[i].startsWith('-')) {
      positional.add(arguments[i]);
    }
  }
  if (positional.length != 1) {
    stderr.writeln('Usage: flutter3d create project <dir> [--name <package>]');
    exitCode = CliExit.usage;
    return;
  }
  final target = positional.single;
  final package =
      name ??
      Uri.directory(target).pathSegments.where((String s) => s.isNotEmpty).last;
  final answer = createProject(target, package);
  if (!answer.did) {
    stderr.writeln(answer.says);
    exitCode = CliExit.refused;
    return;
  }
  stdout.writeln(answer.says);
}

/// This package's version, read from its own pubspec rather than written
/// here a second time: a constant beside the pubspec was a second number
/// to move on every release, and it was the one nobody moved.
///
/// The pubspec sits beside `lib/` wherever the package was resolved from —
/// the workspace, the pub cache, a global activation — so it is found
/// through the package's own URI. `unknown` when it is not there.
Future<String> _packageVersion() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter3d_build/cli.dart'),
  );
  if (library == null) return 'unknown';
  try {
    final pubspec = File.fromUri(library.resolve('../pubspec.yaml'));
    return RegExp(
          r'^version:\s*(\S+)',
          multiLine: true,
        ).firstMatch(pubspec.readAsStringSync())?[1] ??
        'unknown';
  } on FileSystemException {
    return 'unknown';
  }
}
