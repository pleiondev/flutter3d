/// `flutter3d decode-worker`: compiles the browser's decode worker into the
/// script a web build serves.
///
///     flutter3d decode-worker [web/flutter3d_decode_worker.js]
///
/// The script is the engine's decoders as a program of their own, which a
/// Web Worker runs; `WebDecodeWorker.use` names it at startup. It is built
/// from `flutter3d_core` as resolved by the project the command runs in, so
/// it is compiled again after an upgrade: a page and a worker from two
/// releases do not talk, and the page then decodes in place and says why.
/// `dart run flutter3d_core:decode_worker` is the same command under its
/// old name.
library;

import 'dart:io';
import 'dart:isolate';

import 'cli_contract.dart';

/// Runs `flutter3d decode-worker [output]` and returns its exit code
/// ([CliExit]).
Future<int> runDecodeWorker(
  List<String> arguments, {
  IOSink? out,
  IOSink? err,
}) async {
  final say = out ?? stdout;
  final complain = err ?? stderr;
  if (arguments.contains('-h') || arguments.contains('--help')) {
    say.writeln(decodeWorkerUsage);
    return CliExit.ok;
  }
  if (cliOptions['decode-worker']!.unknownIn(arguments) case final String b) {
    complain.writeln('${unknownOption(b)}\n\n$decodeWorkerUsage');
    return CliExit.usage;
  }
  if (arguments.length > 1) {
    complain.writeln(
      'decode-worker takes one output path at most.\n\n$decodeWorkerUsage',
    );
    return CliExit.usage;
  }
  return _compile(
    arguments.firstOrNull ?? 'web/flutter3d_decode_worker.js',
    say,
    complain,
  );
}

/// Compiles the worker to [output], with the compiler's own words on
/// [say] and [complain].
Future<int> _compile(String output, IOSink say, IOSink complain) async {
  final entry = await Isolate.resolvePackageUri(
    Uri.parse(
      'package:flutter3d_core/src/engine/platform/decode_worker_main.dart',
    ),
  );
  final packages = await Isolate.packageConfig;
  if (entry == null || packages == null) {
    complain.writeln(
      'decode-worker could not find flutter3d_core in this project; run it '
      'with `dart run` from a project that depends on it.',
    );
    return CliExit.failure;
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
  say.write(result.stdout);
  complain.write(result.stderr);
  // The compiler's list of inputs, which nothing serves.
  final deps = File('$output.deps');
  if (deps.existsSync()) deps.deleteSync();
  return result.exitCode == 0 ? CliExit.ok : CliExit.failure;
}
