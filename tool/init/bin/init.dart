/// `tpl-01`'s own row: `dart run flutter3d:init --template=<genre>`.
///
///     dart run tool/init/bin/init.dart --list
///     dart run tool/init/bin/init.dart --template=racing --target=../my_game
///
/// **Not `dart run flutter3d:init`.** That name needs `flutter3d_build` —
/// `ap-10` — which is not a package that exists in this tree yet. What is
/// here is the mechanism the real command would call once it does: the same
/// `Template`/`scaffold` pair the editor's own "new project" wizard already
/// calls, reached from plain `dart run` instead of from inside a running
/// Flutter app.
library;

import 'dart:io';

import 'package:init/init.dart';

void main(List<String> arguments) {
  String? template;
  String? target;
  String? name;
  var list = false;

  for (final argument in arguments) {
    if (argument == '--list') {
      list = true;
    } else if (argument.startsWith('--template=')) {
      template = argument.substring('--template='.length);
    } else if (argument.startsWith('--target=')) {
      target = argument.substring('--target='.length);
    } else if (argument.startsWith('--name=')) {
      name = argument.substring('--name='.length);
    } else {
      stderr.writeln('unknown argument: $argument');
      exitCode = 64; // EX_USAGE
      return;
    }
  }

  final templatesRoot = defaultTemplatesRoot(_repositoryRoot());

  if (list) {
    for (final genre in availableTemplates(templatesRoot)) {
      stdout.writeln(genre);
    }
    return;
  }

  if (template == null || target == null) {
    stderr.writeln(
      'usage: dart run tool/init/bin/init.dart --template=<genre> '
      '--target=<directory> [--name=<package_name>]\n'
      '       dart run tool/init/bin/init.dart --list',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  writeProject(
    templatesRoot: templatesRoot,
    genre: template,
    targetDirectory: target,
    projectName: name,
  );
  stdout.writeln('wrote $template to $target');
}

/// This script's own checkout root — `tool/init/bin/init.dart` is always
/// three directories under it, wherever the checkout itself lives.
String _repositoryRoot() {
  final script = File.fromUri(Platform.script).absolute;
  return script.parent.parent.parent.parent.path;
}
