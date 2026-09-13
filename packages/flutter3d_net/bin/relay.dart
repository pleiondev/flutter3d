import 'dart:io';

/// `net-02`'s relay: one process, rooms named by a code in the URL path,
/// no accounts.
///
///     dart run flutter3d_net:relay [port]
///
/// `/room/<code>` — the first two sockets to ask for a given code are
/// joined, and everything one of them sends is forwarded to the other,
/// verbatim and unparsed. A third asking for a code already holding two is
/// refused rather than queued: `net-01`'s own `NetSession` is a two-player
/// design, and a relay that queued a third would be promising something
/// nothing on the other end can use.
///
/// **Doubles as either half of `net-02`'s two transports, and does not
/// need to know which.** For [WebSocketTransport] this *is* the data path,
/// carrying every game frame for as long as the room stays open — the
/// fallback the plan names for a platform or a network a WebRTC data
/// channel could not reach. For a WebRTC transport this is only the
/// signalling channel: an SDP offer and answer, a handful of ICE
/// candidates, and then silence once the peers have found each other
/// directly. Both are opaque JSON as far as this file is concerned, which
/// is the whole reason one relay serves both.
///
/// [port] defaults to `0`, which asks the system for whichever port is
/// free — the line this prints on startup is how a caller that bound to
/// `0` (a test, most often) reads back which one it actually got.
Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 0;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  // Read by `test/relay_test.dart` off the child process's own stdout, the
  // same way `run_timeline_extensions_test.dart` reads a VM service URI off
  // `flutter test -v`'s.
  stdout.writeln('flutter3d_net relay listening on ${server.port}');

  final rooms = <String, List<WebSocket>>{};

  await for (final request in server) {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('this is a WebSocket relay, not a page');
      await request.response.close();
      continue;
    }
    final segments = request.uri.pathSegments;
    if (segments.length != 2 || segments[0] != 'room' || segments[1].isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    final code = segments[1];
    final socket = await WebSocketTransformer.upgrade(request);
    final room = rooms.putIfAbsent(code, () => <WebSocket>[]);
    if (room.length >= 2) {
      await socket.close(
        WebSocketStatus.policyViolation,
        'room $code already has two peers',
      );
      continue;
    }
    room.add(socket);
    socket.listen(
      (message) {
        for (final peer in room) {
          if (!identical(peer, socket)) peer.add(message);
        }
      },
      onDone: () {
        room.remove(socket);
        if (room.isEmpty) rooms.remove(code);
      },
    );
  }
}
