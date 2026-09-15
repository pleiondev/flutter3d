/// A live diagnostic server (`DiagnosticMcpServer`), reachable over a socket rather than
/// over stdio — see `pubspec.yaml`'s own doc for why literal stdio does not
/// survive being hosted inside `flutter test`.
///
///     flutter test --reporter=silent test/fixtures/render_mcp_server.dart
///
/// Not named `*_test.dart` on purpose, the same reason
/// `flutter3d_sim_mcp/test/fixtures/sim_mcp_server.dart` gives for itself.
library;

import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_sim_mcp/src/diagnostic_server.dart';
import 'package:flutter3d_sim_mcp/src/diagnostic_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a live diagnostic server, reachable over a socket', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    // ignore: avoid_print
    print('diagnostic server listening on ${server.port}');

    server.listen((socket) {
      DiagnosticMcpServer(
        stdioChannel(input: socket, output: socket),
        session: DiagnosticSession(),
      );
    });

    await Future<void>.delayed(const Duration(seconds: 60));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
