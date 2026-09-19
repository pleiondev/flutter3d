/// The version a person is shown and a bug report carries is the version
/// `pubspec.yaml` says.
///
///     flutter test test/app_version_test.dart
library;

import 'dart:io';

import 'package:flutter3d_modeler/src/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kModelerVersion is the pubspec\'s own version', () {
    // Tests run with the package directory as the working directory.
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final String? declared = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);

    // Mutation: bump one and not the other. The About row then says a build
    // that is not the one installed, and a report is answered from the
    // wrong release.
    expect(declared, isNotNull, reason: 'pubspec.yaml has no version:');
    expect(kModelerVersion, declared);
  });

  test('is a release and a build, and this release is 0.7', () {
    expect(kModelerVersion, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    expect(kModelerVersion, startsWith('0.7.'));
  });

  test('a report says which build it is about before where it ran', () {
    final String environment = reportEnvironmentFor('macOS');

    // Mutation: build the environment from the platform alone, which is what
    // it was. The issue arrives with no version to reproduce against.
    expect(environment, contains(kModelerVersion));
    expect(environment, endsWith('macOS'));
    expect(
      environment.indexOf(kModelerVersion),
      lessThan(environment.indexOf('macOS')),
    );
  });
}
