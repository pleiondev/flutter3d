/// A live `flutter3d_sim_mcp` server, reachable over a socket rather than
/// over stdio — see `pubspec.yaml`'s own doc for why literal stdio does not
/// survive being hosted inside `flutter test`.
///
///     flutter test --reporter=silent test/fixtures/sim_mcp_server.dart
///
/// **Not named `*_test.dart` on purpose**, the same reason
/// `flutter3d_session/test/fixtures/timeline_target.dart` gives for itself:
/// `flutter test` run over the whole package should never pick this up on
/// its own, since alone it does nothing but wait for a client that never
/// connects. `test/sim_mcp_test.dart` is what starts it, named explicitly,
/// and kills it when done.
///
/// `--reporter=silent` is required, not a preference: any other reporter
/// writes its own lines to the same `stdout` a client would otherwise be
/// tempted to read the port announcement from, and this file's one
/// diagnostic print already goes through `flutter test`'s "Shell: " prefix
/// — a second, competing writer would make that line harder to find, not
/// easier.
library;

import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game_shooter/staging.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_sim_mcp/src/sim_server.dart';
import 'package:flutter3d_sim_mcp/src/sim_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a live flutter3d_sim_mcp server, reachable over a socket', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    // Read by `test/sim_mcp_test.dart` off this process's own stdout, the
    // same way `run_timeline_extensions_test.dart` reads a VM service URI
    // off `flutter test -v`'s.
    // ignore: avoid_print
    print('flutter3d_sim_mcp listening on ${server.port}');

    server.listen((socket) {
      SimMcpServer(
        stdioChannel(input: socket, output: socket),
        // The host decides what is played; this suite plays the crypt, which
        // names a `widget_surface` entity (`wg-02`) the shooter's own
        // vocabulary does not know without this.
        session: SimSession(
          game: const ShooterHeadlessGame(
            extra: <EntityKind>[WidgetSurfaceKind()],
          ),
        ),
      );
    });

    // Long enough for a client to connect, open a level, step it and hang
    // up; the test that started this process kills it well before this
    // runs out rather than waiting for it.
    await Future<void>.delayed(const Duration(seconds: 60));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
