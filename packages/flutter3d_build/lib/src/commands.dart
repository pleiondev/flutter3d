/// The `flutter3d` command, as one function: [runFlutter3d].
///
/// **Every entry point in `bin/` is this function.** `bin/flutter3d.dart`
/// hands it the command line; `bin/convert.dart`, `bin/create.dart`,
/// `bin/init.dart`, `bin/lightmap.dart`, `bin/lights.dart`, `bin/migrate.dart`,
/// `bin/plugins.dart` and `bin/shaders.dart` are the same commands under the names
/// `dart run flutter3d_build:<name>` reaches, each one line that puts its
/// own name in front of the arguments. So the two spellings run the same code, and a
/// command has one usage text, one exit code table and one `--json` shape.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart'
    show MaterialBuildException;

import 'cli_contract.dart';
import 'convert/command.dart' show runConvertCommand;
import 'doctor.dart' show runDoctor;
import 'init.dart' show runInit;
import 'lightmap_command.dart' show runLightmap;
import 'lights.dart' show runLights;
import 'migrate/command.dart' show runMigrateCommand;
import 'plugin_author_server.dart' show PluginWorkshop;
import 'plugin_discovery.dart';
import 'plugin_template.dart' show PluginKind;
import 'project_template.dart' show createProject;
import 'shader_build.dart';

/// Runs `flutter3d <command> [arguments]` and returns its exit code
/// ([CliExit]). Writes to stdout and stderr as the command does.
Future<int> runFlutter3d(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(flutter3dUsage);
    return CliExit.usage;
  }
  final command = arguments.first;
  final rest = arguments.sublist(1);
  switch (command) {
    case 'convert':
      return runConvertCommand(rest);
    case 'doctor':
      return runDoctor(rest);
    case 'create':
      return _create(rest);
    case 'init':
      return runInit(rest);
    case 'plugins':
      return _plugins(rest);
    case 'shaders':
      return _shaders(rest);
    case 'migrate':
      return runMigrateCommand(rest);
    case 'lights':
      return runLights(rest);
    case 'lightmap':
      return runLightmap(rest);
    case 'help' || '-h' || '--help':
      if (rest.firstOrNull == '--surface') {
        stdout.write(cliSurface());
        return CliExit.ok;
      }
      return _help(rest.firstOrNull);
    case '--version':
      stdout.writeln('flutter3d_build ${await _packageVersion()}');
      return CliExit.ok;
    default:
      stderr.writeln('Unknown command "$command".\n\n$flutter3dUsage');
      return CliExit.usage;
  }
}

Future<int> _help(String? command) async {
  switch (command) {
    case null:
      stdout.writeln(flutter3dUsage);
    case 'convert':
      stdout.writeln(convertUsage);
    case 'doctor':
      runDoctor(const <String>['--help']);
    case 'create':
      stdout.writeln(createUsage);
    // Their own usage, from their own parsers. Each prints it as the answer
    // to an option it does not take, and says so in its exit code; asked
    // for, it is not an error.
    case 'migrate':
      await runMigrateCommand(const <String>['--help']);
    case 'init':
      await runInit(const <String>['--help']);
    case 'lights':
      await runLights(const <String>['--help']);
    case 'lightmap':
      runLightmap(const <String>['--help']);
    case 'plugins':
      stdout.writeln(pluginsUsage);
    case 'shaders':
      stdout.writeln(shadersUsage);
    default:
      stderr.writeln('No command "$command".\n\n$flutter3dUsage');
      return CliExit.usage;
  }
  return CliExit.ok;
}

/// `flutter3d create project <dir>`, `create plugin …` and `create --list`.
int _create(List<String> arguments) {
  if (arguments.contains('--list')) {
    for (final kind in PluginKind.values) {
      stdout.writeln('${kind.name.padRight(12)} ${kind.about}');
    }
    return CliExit.ok;
  }
  return switch (arguments.firstOrNull) {
    'project' => _createProject(arguments.sublist(1)),
    'plugin' => _createPlugin(arguments.sublist(1)),
    _ => () {
      stderr.writeln(createUsage);
      return CliExit.usage;
    }(),
  };
}

int _createPlugin(List<String> arguments) {
  String? option(String name) {
    final at = arguments.indexOf('--$name');
    if (at >= 0 && at + 1 < arguments.length) return arguments[at + 1];
    final prefix = '--$name=';
    return arguments
        .where((String a) => a.startsWith(prefix))
        .map((String a) => a.substring(prefix.length))
        .firstOrNull;
  }

  final kindName = option('kind');
  final name = option('name');
  if (kindName == null || name == null) {
    stderr.writeln(createUsage);
    return CliExit.usage;
  }
  final PluginKind kind;
  try {
    kind = PluginKind.named(kindName);
  } on ArgumentError catch (error) {
    stderr.writeln('${error.message}\n\n$createUsage');
    return CliExit.usage;
  }
  final answer = PluginWorkshop().create(option('target') ?? name, name, kind);
  if (!answer.did) {
    stderr.writeln(answer.says);
    return CliExit.refused; // the target is not empty
  }
  stdout.writeln(answer.says);
  return CliExit.ok;
}

int _createProject(List<String> arguments) {
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
    return CliExit.usage;
  }
  final target = positional.single;
  final package =
      name ??
      Uri.directory(target).pathSegments.where((String s) => s.isNotEmpty).last;
  final answer = createProject(target, package);
  if (!answer.did) {
    stderr.writeln(answer.says);
    return CliExit.refused;
  }
  stdout.writeln(answer.says);
  return CliExit.ok;
}

/// `flutter3d plugins [--check] [--json]`: writes `lib/plugins.g.dart` from
/// the dependencies' `flutter3d_plugins:` markers and the project's own
/// `with:`, `without:` and `set:`, or checks that it is current.
int _plugins(List<String> arguments) {
  const known = <String>{'--check', '--json'};
  final help = arguments.contains('-h') || arguments.contains('--help');
  final unknown = arguments.where((String a) => !known.contains(a)).toList();
  if (unknown.isNotEmpty) {
    stderr.writeln(
      help ? pluginsUsage : 'Unknown option ${unknown.first}.\n\n$pluginsUsage',
    );
    return help ? CliExit.ok : CliExit.usage;
  }
  final check = arguments.contains('--check');
  final json = arguments.contains('--json');
  void printJson(Map<String, Object?> body) => stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(cliJson('plugins', body)),
  );
  try {
    final root = Directory.current;
    if (check) {
      final discovery = discoverPlugins(root);
      discovery.warnings.forEach(stderr.writeln);
      final file = File('${root.path}/lib/plugins.g.dart');
      final current =
          file.existsSync() &&
          file.readAsStringSync() == renderPluginsFile(discovery.plugins);
      final found = discovery.plugins;
      if (json) {
        printJson(<String, Object?>{
          'check': true,
          'path': file.path,
          'current': current,
          'warnings': discovery.warnings,
          'plugins': _rows(found),
          'excluded': _rows(discovery.excluded),
        });
      } else {
        stdout.writeln(
          current
              ? 'current: ${file.path} — '
                    '${found.isEmpty ? 'no plugins' : found.join(', ')}'
                    '${_leftOut(discovery.excluded)}'
              : 'out of date: ${file.path} is not what the dependencies '
                    'declare; run `flutter3d plugins`',
        );
      }
      return current ? CliExit.ok : CliExit.refused;
    }
    final report = writeDiscoveredPlugins(root, always: true);
    final found = report.discovery.plugins;
    report.discovery.warnings.forEach(stderr.writeln);
    if (json) {
      printJson(<String, Object?>{
        'check': false,
        'path': report.path,
        'written': report.written,
        'warnings': report.discovery.warnings,
        'plugins': _rows(found),
        'excluded': _rows(report.discovery.excluded),
      });
    } else {
      stdout.writeln(
        '${report.written ? 'wrote' : 'unchanged:'} ${report.path} — '
        '${found.isEmpty ? 'no plugins' : found.join(', ')}'
        '${_leftOut(report.discovery.excluded)}',
      );
    }
    return CliExit.ok;
  } on PluginDiscoveryException catch (error) {
    stderr.writeln(error.message);
    return CliExit.failure;
  }
}

/// `flutter3d shaders [--full-shaders] [--target native|web|any] [--json]`:
/// the build hook's shader step by hand (D15), against the project in the
/// working directory.
int _shaders(List<String> arguments) {
  final known = <String>{'--full-shaders', '--json', '--target'};
  final targetAt = arguments.indexOf('--target');
  final targetName = targetAt < 0 || targetAt + 1 >= arguments.length
      ? 'any'
      : arguments[targetAt + 1];
  final target = switch (targetName) {
    'native' => ShaderBuildTarget.native,
    'web' => ShaderBuildTarget.web,
    'any' => ShaderBuildTarget.any,
    _ => null,
  };
  final unknown = <String>[
    for (var i = 0; i < arguments.length; i++)
      if (!known.contains(arguments[i]) && i != targetAt + 1) arguments[i],
  ];
  if (unknown.isNotEmpty ||
      target == null ||
      (targetAt >= 0 && targetAt + 1 >= arguments.length)) {
    final help = arguments.contains('-h') || arguments.contains('--help');
    stderr.writeln(
      help
          ? shadersUsage
          : '${target == null ? 'Unknown target "$targetName"' : 'Unknown option ${unknown.firstOrNull ?? '--target'}'}.\n\n$shadersUsage',
    );
    return help ? CliExit.ok : CliExit.usage;
  }
  final root = Directory.current;
  try {
    final discovery = discoverPlugins(root);
    final report = runShaderBuild(
      root,
      plugins: discovery,
      full: arguments.contains('--full-shaders'),
      target: target,
      log: arguments.contains('--json') ? _Discard() : null,
    );
    if (arguments.contains('--json')) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(
          cliJson('shaders', <String, Object?>{
            'ran': report.ran,
            'written': report.written,
            'bytes': report.bytes,
            'full': report.full,
            'needs': report.needs,
            'stages': report.stages,
            'totalStages': report.totalStages,
            'materials': report.materials,
          }),
        ),
      );
    }
    return CliExit.ok;
  } on PluginDiscoveryException catch (error) {
    stderr.writeln(error.message);
    return CliExit.failure;
  } on MaterialBuildException catch (error) {
    stderr.writeln(error);
    return CliExit.failure;
  }
}

/// A sink that keeps nothing: the build's log, when the output is JSON.
final class _Discard implements IOSink {
  @override
  void writeln([Object? object = '']) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<Object?> _rows(List<DiscoveredPlugin> plugins) => <Object?>[
  for (final p in plugins)
    <String, Object?>{
      'package': p.package,
      'import': p.import,
      'class': p.className,
    },
];

/// The plugins the project's own `without:` left out, as a tail for the
/// plain report; empty when nothing was.
String _leftOut(List<DiscoveredPlugin> excluded) =>
    excluded.isEmpty ? '' : '; left out: ${excluded.join(', ')}';

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
