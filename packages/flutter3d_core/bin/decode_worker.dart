/// Compiles the browser's decode worker into a script a web build serves.
///
///     dart run flutter3d_core:decode_worker [web/flutter3d_decode_worker.js]
///
/// The script is the engine's decoders as a program of their own, which a
/// Web Worker runs; `WebDecodeWorker.use` names it at startup. It is built
/// from this package as resolved by the project the command runs in, so it
/// is compiled again after an upgrade: a page and a worker from two releases
/// do not talk, and the page then decodes in place and says why.
library;

import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('-h') || arguments.contains('--help')) {
    stdout.writeln(
      'Usage: dart run flutter3d_core:decode_worker [output]\n'
      '\n'
      'Compiles the decode worker to [output], '
      'web/flutter3d_decode_worker.js by default.',
    );
    return;
  }
  if (arguments.length > 1) {
    stderr.writeln('decode_worker takes one output path at most.');
    exitCode = 64;
    return;
  }
  final output = arguments.isEmpty
      ? 'web/flutter3d_decode_worker.js'
      : arguments.single;
  final entry = await Isolate.resolvePackageUri(
    Uri.parse(
      'package:flutter3d_core/src/engine/platform/decode_worker_main.dart',
    ),
  );
  final packages = await Isolate.packageConfig;
  if (entry == null || packages == null) {
    stderr.writeln(
      'decode_worker could not find flutter3d_core in this project; run it '
      'with `dart run` from a project that depends on it.',
    );
    exitCode = 69;
    return;
  }
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'compile',
    'js',
    '-O2',
    '--no-source-maps',
    '--packages=${packages.toFilePath()}',
    '--output=$output',
    entry.toFilePath(),
  ]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  // The compiler's list of inputs, which nothing serves.
  final deps = File('$output.deps');
  if (deps.existsSync()) deps.deleteSync();
  exitCode = result.exitCode;
}
