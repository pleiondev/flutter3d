import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

void main() {
  test('`buildAssets` runs against real hooks-package objects, not a fake of '
      'them — a real BuildInputBuilder/BuildInput/BuildOutputBuilder, the same '
      'classes `hook/build.dart` gets handed by the Flutter tool', () async {
    // `package:hooks` also ships `testBuildHook`, which drives a real
    // `hook/build.dart`'s `main` end to end through a real `input.json`
    // on disk — but it hardcodes `packageRoot: Directory.current.uri`,
    // and mutating the process-wide `Directory.current` to point at a
    // scratch project broke every *other* test file's relative fixture
    // paths the moment `dart test` ran them concurrently in the same
    // process (isolates share one OS working directory; there is no
    // per-isolate CWD to change instead) — found by running the suite,
    // not guessed. `BuildInputBuilder.setupShared` takes `packageRoot` as
    // an explicit `Uri` instead, which is the same real class
    // `testBuildHook` itself builds with, minus the one call that made
    // it unsafe to run alongside anything else.
    final project = Directory.systemTemp.createTempSync('f3d_hook_');
    addTearDown(() => project.deleteSync(recursive: true));

    Directory('${project.path}/assets_src').createSync();
    File('${project.path}/assets_src/hero.obj').writeAsStringSync('''
v 0.0 0.0 0.0
v 1.0 0.0 0.0
v 0.0 1.0 0.0
f 1 2 3
''');

    final inputBuilder = BuildInputBuilder()
      ..setupShared(
        packageRoot: project.uri,
        packageName: 'hook_test_project',
        outputFile: project.uri.resolve('output.json'),
        outputDirectoryShared: project.uri.resolve('shared/'),
      )
      ..setupBuildInput()
      ..config.setupBuild(linkingEnabled: false);
    final input = inputBuilder.build();
    final output = BuildOutputBuilder();

    await buildAssets(input, output);

    expect(
      File('${project.path}/flutter3d_generated/hero.f3d').existsSync(),
      isTrue,
    );

    // `BuildOutputBuilder` only exposes what it was given through its own
    // JSON, the same way the real Flutter tool would read it back —
    // reading through a fresh `BuildOutput` rather than a private field
    // is the honest way to check what was actually recorded.
    final recorded = BuildOutput(output.json);
    expect(
      recorded.dependencies.map((uri) => uri.toFilePath()),
      contains(File('${project.path}/assets_src/hero.obj').path),
    );
  });
}
