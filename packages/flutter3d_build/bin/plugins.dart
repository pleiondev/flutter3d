// Writes `lib/plugins.g.dart`: the plugins this project's dependencies
// declare with a `flutter3d_plugins:` marker in their pubspecs, less what
// this project's own `flutter3d_plugins: include:`/`exclude:` leaves out.
// The pre-1.0 `flutter3d: plugin:` marker is still read, with a warning on
// stderr.
//
//   dart run flutter3d_build:plugins
//   dart run flutter3d_build:plugins --check     # CI: exit 3 when stale
//
// The build hook writes the same file on every build; this is for the first
// time, before any build, so the analyzer finds the file, and for a project
// that does not use the hook. The logic is `writeDiscoveredPlugins` in
// `package:flutter3d_build`, tested against a fixture package config.
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/cli.dart' show CliExit, cliJson, pluginsUsage;
import 'package:flutter3d_build/flutter3d_build.dart';

void main(List<String> arguments) {
  const known = <String>{'--check', '--json'};
  final unknown = arguments.where((String a) => !known.contains(a)).toList();
  if (unknown.isNotEmpty) {
    stderr.writeln(
      arguments.contains('-h') || arguments.contains('--help')
          ? pluginsUsage
          : 'Unknown option ${unknown.first}.\n\n$pluginsUsage',
    );
    exitCode = arguments.contains('-h') || arguments.contains('--help')
        ? CliExit.ok
        : CliExit.usage;
    return;
  }
  final check = arguments.contains('--check');
  final json = arguments.contains('--json');
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
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(
            cliJson('plugins', <String, Object?>{
              'check': true,
              'path': file.path,
              'current': current,
              'warnings': discovery.warnings,
              'plugins': _rows(found),
              'excluded': _rows(discovery.excluded),
            }),
          ),
        );
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
      exitCode = current ? CliExit.ok : CliExit.refused;
      return;
    }
    final report = writeDiscoveredPlugins(root, always: true);
    final found = report.discovery.plugins;
    report.discovery.warnings.forEach(stderr.writeln);
    if (json) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(
          cliJson('plugins', <String, Object?>{
            'check': false,
            'path': report.path,
            'written': report.written,
            'warnings': report.discovery.warnings,
            'plugins': _rows(found),
            'excluded': _rows(report.discovery.excluded),
          }),
        ),
      );
    } else {
      stdout.writeln(
        '${report.written ? 'wrote' : 'unchanged:'} ${report.path} — '
        '${found.isEmpty ? 'no plugins' : found.join(', ')}'
        '${_leftOut(report.discovery.excluded)}',
      );
    }
  } on PluginDiscoveryException catch (error) {
    stderr.writeln(error.message);
    exitCode = CliExit.failure;
  }
}

List<Object?> _rows(List<DiscoveredPlugin> plugins) => <Object?>[
  for (final p in plugins)
    <String, Object?>{
      'package': p.package,
      'import': p.import,
      'class': p.className,
    },
];

/// The plugins the project's own `include`/`exclude` left out, as a tail
/// for the plain report; empty when nothing was.
String _leftOut(List<DiscoveredPlugin> excluded) =>
    excluded.isEmpty ? '' : '; left out: ${excluded.join(', ')}';
