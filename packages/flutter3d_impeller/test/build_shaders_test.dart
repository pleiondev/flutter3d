/// That `dart run flutter3d_impeller:build_shaders` finds the script it runs,
/// and puts the bundle where the package that asked for it can load it.
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

  group('the bundle lands in the package that owns it', () {
    // The script needs an SDK to find `impellerc` under, and asking for the
    // real one would tie this test to `flutter precache` and to a compiler run
    // measured in seconds. So it gets a fake: a directory shaped like
    // bin/cache/artifacts/engine/<platform>, with an `impellerc` that writes
    // one line of plausible Metal at whatever `--sl=` names. Everything the
    // script decides — which manifest, which include roots, and the output path
    // this group is about — it decides before reaching the compiler.
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('f3d_bundle_out'));
    tearDown(() => temp.deleteSync(recursive: true));

    String write(String relative, String contents) {
      final file = File('${temp.path}/$relative')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(contents);
      return file.path;
    }

    void executable(String path) {
      final chmod = Process.runSync('chmod', ['+x', path]);
      expect(chmod.exitCode, 0, reason: 'chmod +x $path: ${chmod.stderr}');
    }

    String stubSdk() {
      executable(
        write('sdk/bin/cache/artifacts/engine/stub/impellerc', '''
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\$arg" in
    --sl=*) printf 'fragment demo_fragment_main(constant FragInfo& frag_info)\\n' \\
              > "\${arg#--sl=}" ;;
  esac
done
'''),
      );
      Directory(
        '${temp.path}/sdk/bin/cache/artifacts/engine/stub/shader_lib',
      ).createSync(recursive: true);
      return '${temp.path}/sdk';
    }

    ProcessResult run(String script, List<String> arguments, String sdk) =>
        Process.runSync(
          'bash',
          [script, '--platform', 'stub', ...arguments],
          environment: {'FLUTTER_ROOT': sdk},
        );

    test('which is the extension, when an extension is what we were given', () {
      // The published instruction is `dart run flutter3d_impeller:build_shaders`
      // from the extension's root, and bin/build_shaders.dart turns that into
      // `--package <the extension>`. The bundle is then the extension's asset:
      // it is the extension's pubspec that declares it and the extension's name
      // that an application loads it under.
      //
      // Mutation: put `OUT="$OWNER/…"` back in tool/build_shaders.sh — this
      // fails on both expectations, the bundle landing in flutter3d_impeller
      // instead, which in a pub-cache install is not even writable.
      final sdk = stubSdk();
      write('extension/shaders/demo.shaderbundle.json', '{}');

      final result = run('${_thisPackage.path}/tool/build_shaders.sh', [
        '--package',
        '${temp.path}/extension',
      ], sdk);

      expect(
        File(
          '${temp.path}/extension/assets/shaders/demo.shaderbundle',
        ).existsSync(),
        isTrue,
        reason: 'exit ${result.exitCode}\n${result.stdout}\n${result.stderr}',
      );
      expect(
        File(
          '${_thisPackage.path}/assets/shaders/demo.shaderbundle',
        ).existsSync(),
        isFalse,
        reason: 'the extension\'s bundle must not be written into this package',
      );
    });

    test('and is still this package, when sources.txt sends us elsewhere', () {
      // The other direction, and the reason the output path is not simply the
      // package being read: flutter3d_impeller's own GLSL lives in
      // flutter3d_shaders, and the compiled bundle stays here regardless.
      //
      // The redirection resolves the source package by running
      // tool/package_root.dart with the SDK's Dart, so the stub SDK ships a
      // `dart` that answers with the fixture's path and nothing else.
      //
      // Mutation: set BUNDLE_OWNER to PACKAGE unconditionally — this fails,
      // the engine's bundle landing in flutter3d_shaders, which no application
      // lists in its assets.
      final sdk = stubSdk();
      write('source/shaders/demo.shaderbundle.json', '{}');
      final script = write(
        'owner/tool/build_shaders.sh',
        File('${_thisPackage.path}/tool/build_shaders.sh').readAsStringSync(),
      );
      write('owner/tool/sources.txt', 'demo_sources\n');
      write(
        'owner/tool/package_root.dart',
        '// never run: the stub answers.\n',
      );
      executable(
        write('sdk/bin/cache/dart-sdk/bin/dart', '''
#!/usr/bin/env bash
echo '${temp.path}/source'
'''),
      );

      final result = run(script, const [], sdk);

      expect(
        File(
          '${temp.path}/owner/assets/shaders/demo.shaderbundle',
        ).existsSync(),
        isTrue,
        reason: 'exit ${result.exitCode}\n${result.stdout}\n${result.stderr}',
      );
      expect(
        Directory('${temp.path}/source/assets').existsSync(),
        isFalse,
        reason: 'the package the GLSL came from gets no bundle',
      );
    });
  });
}
