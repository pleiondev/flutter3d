/// `attach.dart` is the part of Play a browser has, so nothing under it may
/// import `dart:io`.
///
///     dart test test/attach_web_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

final RegExp _directive = RegExp(
  r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

void main() {
  test('nothing attach.dart reaches in this repository imports dart:io', () {
    // Workspace packages are followed; a hosted one is taken at its word,
    // since `web_socket_channel` itself picks `dart:io` by a conditional
    // import that a browser build never takes.
    final packages = _workspacePackages();
    final seen = <String>{};
    final reachesIo = <String>[];

    void visit(File file) {
      if (!seen.add(file.absolute.path)) return;
      for (final match in _directive.allMatches(file.readAsStringSync())) {
        final target = match.group(1)!;
        if (target == 'dart:io') reachesIo.add(file.path);
        final next = switch (target) {
          _ when target.startsWith('dart:') => null,
          _ when target.startsWith('package:') => () {
            final [name, ...rest] = target.substring(8).split('/');
            final root = packages[name];
            return root == null ? null : File('$root/lib/${rest.join('/')}');
          }(),
          _ => File.fromUri(file.uri.resolve(target)),
        };
        if (next != null) visit(next);
      }
    }

    visit(File('lib/attach.dart'));

    // Mutation: `level_push.dart` back on `vmServiceConnectUri`, or
    // `attach.dart` exporting `flutter_run.dart`, puts `dart:io` under it.
    // A web build still compiles then — dart2js takes `dart:io` and throws
    // `UnsupportedError` from it at run time — so this test is the only
    // thing that notices before somebody presses Send in a browser.
    expect(reachesIo, isEmpty);
    expect(seen.any((it) => it.endsWith('attached_run.dart')), isTrue);
    expect(seen.any((it) => it.contains('flutter3d_sim')), isTrue);
  });
}

/// Every package of this workspace, by name, to its directory.
Map<String, String> _workspacePackages() {
  final root = Directory('../..').absolute;
  return <String, String>{
    for (final pubspec in <File>[
      ...Directory('${root.path}/packages')
          .listSync()
          .whereType<Directory>()
          .map((d) => File('${d.path}/pubspec.yaml')),
    ])
      if (pubspec.existsSync())
        if (RegExp(
              r'^name:\s*(\S+)',
              multiLine: true,
            ).firstMatch(pubspec.readAsStringSync())
            case final match?)
          match.group(1)!: pubspec.parent.path,
  };
}
