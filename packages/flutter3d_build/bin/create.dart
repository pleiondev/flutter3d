// `flutter3d create plugin`: a new plugin package, from a template.
//
//   dart run flutter3d_build:create plugin --kind render-step --name my_glow
//   dart run flutter3d_build:create plugin --kind genre --name duel --target ../duel
//   dart run flutter3d_build:create --list
//
// Decision 20 of `tasks/0.9-plugins.md` names the command `flutter3d create
// plugin`; until a `flutter3d` executable exists, this is that command. The
// target defaults to a directory named after the package, and must be empty
// or not exist: nothing a person already wrote is written over. What the
// files are is `pluginTemplate` in `package:flutter3d_build`, tested
// without a process.
import 'dart:io';

import 'package:flutter3d_build/cli.dart' show CliExit;
import 'package:flutter3d_build/flutter3d_build.dart';

const String _usage = '''
usage: dart run flutter3d_build:create plugin --kind <kind> --name <name> [--target <dir>]
       dart run flutter3d_build:create --list''';

void main(List<String> arguments) {
  if (arguments.contains('--list')) {
    for (final kind in PluginKind.values) {
      stdout.writeln('${kind.name.padRight(12)} ${kind.about}');
    }
    return;
  }
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
  if (arguments.isEmpty ||
      arguments.first != 'plugin' ||
      kindName == null ||
      name == null) {
    stderr.writeln(_usage);
    exitCode = CliExit.usage;
    return;
  }
  final PluginKind kind;
  try {
    kind = PluginKind.named(kindName);
  } on ArgumentError catch (error) {
    stderr.writeln('${error.message}\n\n$_usage');
    exitCode = CliExit.usage;
    return;
  }
  final target = option('target') ?? name;
  final answer = PluginWorkshop().create(target, name, kind);
  if (!answer.did) {
    stderr.writeln(answer.says);
    exitCode = CliExit.refused; // the target is not empty
    return;
  }
  stdout.writeln(answer.says);
}
