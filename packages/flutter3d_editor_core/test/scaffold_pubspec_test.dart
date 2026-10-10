/// The scaffolded `pubspec.yaml` against the Dart the templates ship.
///
///     dart test test/scaffold_pubspec_test.dart
///
/// A template's `main.dart` is copied from a real application in this
/// repository, which declares whatever it imports. The scaffolded project
/// gets [pubspecFor] instead, so an import the seed gains has to be added
/// there as well, or the new project leans on a package it never asked for.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:test/test.dart';

import '../tool/levels/shipped.dart';

void main() {
  final root = repositoryRoot(Directory.current.path);
  final templates = Directory('$root/apps/flutter3d_editor/assets/templates');

  test('every package a template imports is in the scaffolded pubspec', () {
    // Mutation: take `flutter3d_plugin_api` out of `pubspecFor`, and the
    // four `app.main.dart.txt` files are named here, since the seed's genre
    // is a `Flutter3dPlugin` with a `PluginManifest`.
    final pubspec = pubspecFor('seed');
    final declared = <String>{
      'flutter',
      'flutter_test',
      for (final Match m in RegExp(
        r'^  (\w+):',
        multiLine: true,
      ).allMatches(pubspec))
        m[1]!,
    };

    final missing = <String>[
      for (final file in templates.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart.txt'))
          for (final Match m in RegExp(
            r"^import 'package:(\w+)/",
            multiLine: true,
          ).allMatches(file.readAsStringSync()))
            if (!declared.contains(m[1]))
              '${file.path.substring(root.length + 1)}: ${m[1]}',
    ];
    expect(missing, isEmpty);
  });
}
