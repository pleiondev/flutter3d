// Runs flutter3d's shader build against *this* package.
//
//   dart run flutter3d:build_shaders
//
// A twenty-line wrapper around tool/build_shaders.sh, and the whole point of it
// is the part that is not code: `dart run <package>:<executable>` makes pub find
// flutter3d. An extension installed from pub cannot otherwise name the script —
// it lives in a version-stamped cache directory nobody can write down — and
// bootstrapping that lookup by hand is the same package_config.json walk the
// build already needs, duplicated into every extension that ever ships.
//
// Defaults the package being built to the current directory, so the extension
// runs this from its own root and passes nothing. Any argument accepted by
// tool/build_shaders.sh is forwarded; an explicit -p/--package wins.

import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> arguments) async {
  // Resolving a `package:` URI rather than looking at Platform.script, which is
  // a trap here: `dart run flutter3d:build_shaders` first compiles this file
  // into `<consumer>/.dart_tool/pub/bin/flutter3d/build_shaders.dart-*.snapshot`
  // and runs *that*, so Platform.script points into the consumer's build
  // directory and its parent.parent is nothing at all. The package URI is
  // resolved through the same package_config.json the build itself leans on, and
  // survives the snapshot.
  final libraryUri =
      await Isolate.resolvePackageUri(Uri.parse('package:flutter3d/flutter3d.dart'));
  if (libraryUri == null) {
    stderr.writeln('build_shaders: cannot resolve package:flutter3d');
    exitCode = 1;
    return;
  }
  // .../flutter3d/lib/flutter3d.dart -> .../flutter3d
  final ownPackage = File.fromUri(libraryUri).parent.parent;
  final script = '${ownPackage.path}/tool/build_shaders.sh';

  if (!File(script).existsSync()) {
    stderr.writeln('build_shaders: missing $script');
    stderr.writeln(
      'This copy of flutter3d did not ship its shader tooling.',
    );
    exitCode = 1;
    return;
  }

  final givesPackage = arguments.contains('-p') ||
      arguments.contains('--package');

  final result = await Process.start(
    'bash',
    [
      script,
      if (!givesPackage) ...['--package', Directory.current.path],
      ...arguments,
    ],
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await result.exitCode;
}
