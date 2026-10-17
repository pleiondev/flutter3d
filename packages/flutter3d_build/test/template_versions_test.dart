import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart'
    show flutter3dBuildVersionConstraint;
import 'package:flutter3d_build/src/plugin_template.dart';
import 'package:flutter3d_build/src/project_template.dart';
import 'package:flutter3d_build/src/template_versions.dart';
import 'package:test/test.dart';

/// Every constraint a template writes on a package of this repository is a
/// caret on that package's own version, read from its pubspec here.
///
/// **They were 24 literals of `^1.0.0-rc.1`**, one of them held to its
/// pubspec, so a 1.3 template using a 1.3 API would still have written
/// `^1.0.0-rc.1` and a `pub get` that resolved 1.0 would not compile.
void main() {
  /// The constraint a project should get on a package at [version]: the
  /// pre-release whole, since `^1.0.0` does not admit `1.0.0-rc.1`, and a
  /// release from its minor.
  String caretOn(String version) {
    final release = RegExp(r'^(\d+)\.(\d+)\.\d+$').firstMatch(version);
    return release == null
        ? '^$version'
        : '^${release.group(1)}.${release.group(2)}.0';
  }

  String versionOf(String package) {
    final pubspec = File('../$package/pubspec.yaml');
    expect(pubspec.existsSync(), isTrue, reason: '$package is not beside');
    return RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync())!.group(1)!;
  }

  for (final MapEntry(key: package, value: constraint)
      in templateConstraints.entries) {
    test('$package: $constraint follows its pubspec', () {
      // Mutation: bump `version:` in flutter3d_app's pubspec and not here.
      expect(constraint, caretOn(versionOf(package)));
    });
  }

  test('init writes the constraint the templates do', () {
    expect(
      flutter3dBuildVersionConstraint,
      templateConstraints['flutter3d_build'],
    );
  });

  test(
    'every constraint a template writes on this repository is the table\'s',
    () {
      // Mutation: write `flutter3d_core: ^1.0.0-rc.1` in a template again.
      final texts = <String, String>{
        for (final kind in ProjectKind.values)
          'project ${kind.name}': projectTemplate(
            'game',
            kind: kind,
          )['pubspec.yaml']!,
        for (final kind in PluginKind.values)
          if (kind != PluginKind.backend)
            'plugin ${kind.name}': pluginTemplate(
              name: 'glow',
              kind: kind,
            )['pubspec.yaml']!,
      };
      for (final MapEntry(key: what, value: pubspec) in texts.entries) {
        for (final match in RegExp(
          r'^  ((?:flutter3d|flame_flutter3d)\w*): (\S+)$',
          multiLine: true,
        ).allMatches(pubspec)) {
          final package = match.group(1)!;
          // The lints plugin is versioned on its own line, outside the table.
          if (package == 'flutter3d_lints') continue;
          expect(
            match.group(2),
            templateConstraints[package],
            reason: '$what writes $package: ${match.group(2)}',
          );
        }
      }
    },
  );
}
