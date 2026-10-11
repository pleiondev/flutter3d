import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:test/test.dart';

/// `bin/` is the `flutter3d` command and its aliases, nothing else.
///
/// The surface the command commits (`api/flutter3d_build.cli`) says every
/// command also runs as `dart run flutter3d_build:<command>`. That is true
/// only while each file in `bin/` is the command under another name: an
/// entry point with a parser of its own drifts from the command's (its
/// usage, its exit codes, what `-o` means), as `convert` did.
void main() {
  final bin = Directory('bin');
  final aliases = <String>[
    for (final file in bin.listSync().whereType<File>())
      if (file.path.endsWith('.dart'))
        file.uri.pathSegments.last.replaceAll('.dart', ''),
  ]..sort();

  test('bin holds the command and one file per alias', () {
    // `plugin_mcp` is a server, not a command: it speaks MCP over stdio.
    expect(aliases, <String>[
      'convert',
      'create',
      'flutter3d',
      'init',
      'lightmap',
      'lights',
      'migrate',
      'plugin_mcp',
      'plugins',
    ]);
  });

  for (final alias in aliases) {
    if (alias == 'flutter3d' || alias == 'plugin_mcp') continue;
    test('bin/$alias.dart is `flutter3d $alias`, and only that', () {
      // Mutation: give one alias a parser of its own again, and it no longer
      // reads as one call that names its command.
      final code = File('bin/$alias.dart')
          .readAsLinesSync()
          .where((String l) => !l.startsWith('///') && l.trim().isNotEmpty)
          .join('\n');
      expect(code, contains("runFlutter3d(<String>['$alias', ...arguments])"));
      expect(
        RegExp(
          r'^(import|library|Future|  exitCode|\})',
          multiLine: true,
        ).allMatches(code).length,
        code.split('\n').length,
        reason: 'only the library line, imports and one call:\n$code',
      );
      expect(flutter3dUsage, contains('  $alias '));
    });
  }

  test('the command answers an unknown subcommand with the usage', () async {
    expect(await runFlutter3d(const <String>['frobnicate']), CliExit.usage);
    expect(await runFlutter3d(const <String>[]), CliExit.usage);
  });
}
