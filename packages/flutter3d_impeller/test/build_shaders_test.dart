/// That `dart run flutter3d_impeller:build_shaders` finds the script it runs.
///
///     flutter test test/build_shaders_test.dart
///
/// **The neighbour of `shader_include_test.dart`, and deliberately narrow.**
/// That file guards the *headers* an extension includes — every `<lib/…>` has a
/// file behind it, pub will publish them, no `.pubignore` hides them, and
/// `package_root` resolves this package to the directory holding them. None of
/// it looks at the entry point that starts the build, and that is what broke:
/// `tool/build_shaders.sh` moved here from `flutter3d` and `bin/build_shaders.dart`
/// stayed behind, resolving `package:flutter3d/` and then reporting that the
/// copy "did not ship its shader tooling". The command was dead for a fortnight
/// with nothing red.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `flutter test` runs with the package root as the working directory.
Directory get _thisPackage => Directory.current;

void main() {
  group('the shader tooling this package promises', () {
    test('is shipped', () {
      // Mutation: move or rename `tool/build_shaders.sh` — fails here, which is
      // the failure that went unnoticed.
      final script = File('${_thisPackage.path}/tool/build_shaders.sh');
      expect(
        script.existsSync(),
        isTrue,
        reason: 'tool/build_shaders.sh is what bin/build_shaders.dart runs',
      );
    });

    test('and is runnable without asking bash to guess', () {
      // Started as `bash <script>` by the entry point, so the executable bit is
      // not what makes it run — but a script checked in without it is one
      // nobody can run by hand either, and every document in this repository
      // tells them to do exactly that.
      final mode = File(
        '${_thisPackage.path}/tool/build_shaders.sh',
      ).statSync().modeString();
      expect(mode.contains('x'), isTrue, reason: 'not executable: $mode');
    });

    test('and the entry point looks for it in this package', () {
      // **The whole of the bug, in one assertion.** The entry point resolves a
      // `package:` URI to find its own root, and it named `flutter3d` while the
      // script lived here. Pinned as text because the alternative is running
      // `dart run` in a test, which needs a pub cache and a network.
      //
      // Mutation: point it back at `package:flutter3d/flutter3d.dart` — fails.
      final entry = File(
        '${_thisPackage.path}/bin/build_shaders.dart',
      ).readAsStringSync();
      expect(
        entry,
        contains('package:flutter3d_impeller/'),
        reason: 'the entry point must resolve the package it lives in',
      );
      expect(
        entry,
        contains('/tool/build_shaders.sh'),
        reason: 'and must look for the script beside itself',
      );
    });
  });
}
