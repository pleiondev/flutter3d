import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:test/test.dart';

/// Every option a command's parser reads is in its usage, and every option
/// its usage names is one the parser reads.
///
/// **The committed surface is built from the usage texts**, so a flag a
/// parser stopped reading, or started reading, with the text left alone
/// passed every check the surface has. Each parser now refuses anything
/// outside its [cliOptions] entry first, so the entry is what it accepts;
/// this holds the entry to the usage both ways, and to the option words
/// written in the parser's own code.
void main() {
  final usages = <String, String>{
    for (final section in cliSurface().split(RegExp(r'^== ', multiLine: true)))
      if (section.isNotEmpty)
        section.substring(0, section.indexOf(' ==')): section,
  };

  /// What the parsers of [command] accept: every entry its forms have.
  Set<String> accepted(String command) => <String>{
    for (final MapEntry(:key, :value) in cliOptions.entries)
      if (key == command || key.startsWith('$command ')) ...<String>{
        ...value.flags,
        ...value.valued,
      },
  };

  /// A flag another command's usage names in passing, which is not this
  /// command's: doctor says what `flutter3d migrate --data` lifts.
  const mentions = <String, Set<String>>{
    'doctor': <String>{'--data'},
  };

  for (final command in cliCommands) {
    test('$command: the usage names what the parser accepts, both ways', () {
      final usage = usages[command];
      expect(usage, isNotNull, reason: 'no == $command == in the surface');
      final named = <String>{
        for (final match in RegExp(
          r'(?<![\w-])(--?[a-z][a-z0-9-]*)',
        ).allMatches(usage!))
          match[1]!,
      }..removeAll(<String>{'-h', '--help', ...?mentions[command]});
      // A single hyphen before a word is an option only when it is one
      // letter (`-o`); `-p` in a sentence would be prose.
      named.removeWhere((String w) => !w.startsWith('--') && w.length != 2);
      // Mutation: add `--colour` to doctor's usage without teaching the
      // parser, or `'--colour'` to the parser's set without the usage.
      expect(named, accepted(command));
    });
  }

  /// Where each command's parser is written, as a file and the start of
  /// each function that reads its arguments.
  const parsers = <String, List<(String, String)>>{
    'convert': <(String, String)>[
      ('convert/command.dart', 'static ConvertCommandSettings parse('),
    ],
    'create': <(String, String)>[
      ('commands.dart', 'int _create('),
      ('commands.dart', 'int _createPlugin('),
      ('commands.dart', 'int _createProject('),
    ],
    'init': <(String, String)>[('init.dart', 'Future<int> runInit(')],
    'plugins': <(String, String)>[('commands.dart', 'int _plugins(')],
    'shaders': <(String, String)>[('commands.dart', 'int _shaders(')],
    'migrate': <(String, String)>[
      ('migrate/command.dart', 'Future<int> runMigrateCommand('),
    ],
    'lights': <(String, String)>[
      ('lights.dart', 'Future<int> runLights('),
      ('lights.dart', 'static _LightsOptions? parse('),
    ],
    'lightmap': <(String, String)>[
      ('lightmap_command.dart', 'int runLightmap('),
    ],
    'visibility': <(String, String)>[
      ('visibility_command.dart', 'int runVisibility('),
    ],
    'decode-worker': <(String, String)>[
      ('decode_worker_command.dart', 'Future<int> runDecodeWorker('),
    ],
    'doctor': <(String, String)>[('doctor.dart', 'int runDoctor(')],
    'help': <(String, String)>[],
  };

  test('the table names every command', () {
    expect(parsers.keys.toSet(), cliCommands.toSet());
  });

  for (final MapEntry(key: command, value: places) in parsers.entries) {
    if (places.isEmpty) continue;
    test('$command: every option its parser names is one it accepts', () {
      final words = <String>{
        for (final (file, start) in places)
          for (final match in RegExp(
            r"'(--?[a-z][a-z0-9-]*)=?'",
          ).allMatches(_body(File('lib/src/$file').readAsStringSync(), start)))
            match[1]!,
      }..removeAll(const <String>{'-h', '--help'});
      // Mutation: teach `runLightmap` a `case '--indirect':` without adding
      // it to `cliOptions['lightmap']`, which refuses it before the case is
      // reached.
      expect(
        accepted(command).containsAll(words),
        isTrue,
        reason:
            '${words.difference(accepted(command))} read by the parser '
            'and refused by cliOptions[$command]',
      );
      expect(
        words.containsAll(accepted(command)),
        isTrue,
        reason:
            '${accepted(command).difference(words)} accepted and never '
            'read',
      );
    });
  }
}

/// The function of [source] whose declaration starts with [start], up to
/// the brace that closes it.
String _body(String source, String start) {
  final from = source.indexOf(start);
  if (from < 0) throw StateError('no `$start` to read');
  final open = source.indexOf('{', source.indexOf(')', from));
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) return source.substring(from, i + 1);
  }
  return source.substring(from);
}
