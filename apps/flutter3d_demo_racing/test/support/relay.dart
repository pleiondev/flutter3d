/// The relay the network tests race through: `flutter3d_net`'s
/// `bin/relay.dart`, started as a process of its own.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How long the relay may take to say its port.
///
/// **Its start is the environment's, not the code's.** `dart run` compiles
/// the relay inside the test: 4.5 s on an idle M3 Pro on 2026-10-13, and
/// longer than the 15 s this used to allow under a full CI run, where the
/// suites beside it compile at the same time. This leaves the room inside
/// the minute a test has, and a relay that misses it fails saying so.
const Duration relayStartLimit = Duration(seconds: 45);

/// Starts the relay on a free port and answers the port. The relay is killed
/// when the test that started it ends, however it ends.
Future<int> startRelay() async {
  final process = await Process.start(
    'dart',
    <String>['run', 'bin/relay.dart', '0'],
    workingDirectory: '${Directory.current.path}/../../packages/flutter3d_net',
  );
  addTearDown(process.kill);
  // What the relay said, for when it stops before it listens.
  final said = StringBuffer();
  final portFound = Completer<int>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      said.writeln(line);
      final match = RegExp(
        r'flutter3d_net relay listening on (\d+)',
      ).firstMatch(line);
      if (match != null && !portFound.isCompleted) {
        portFound.complete(int.parse(match.group(1)!));
      }
    },
  );
  process.stderr.transform(utf8.decoder).listen(said.write);
  return Future.any(<Future<int>>[
    portFound.future,
    process.exitCode.then(
      (code) => throw StateError(
        'the relay exited ($code) before it listened:\n$said',
      ),
    ),
  ]).timeout(
    relayStartLimit,
    onTimeout: () => throw StateError(
      'the relay did not say its port within ${relayStartLimit.inSeconds} s. '
      'That is the machine, not the race: `dart run` compiles the relay '
      'inside this test, and a loaded machine compiles slowly. Run the file '
      'alone to see the race itself. What the relay said:\n$said',
    ),
  );
}
