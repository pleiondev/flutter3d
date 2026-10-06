import 'dart:convert';
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
/// `/party/<code>?size=N` — a party of up to N (two to thirty-two), for
/// `flame_multiplayer`'s `PartyRollback` and `AuthorityServer`: everything
/// one sends goes to every other, and each is told its slot first, in a
/// message of the relay's own — `{"relay": "welcome", "slot": k, "size":
/// N}` — since a party's slots have to be the same numbers on every
/// machine and only the relay sees the order they arrive in. Who leaves is
/// said too, `{"relay": "left", "slot": k}`. `/watch/<code>` joins a party
/// to watch: its slot comes after the players', it hears everything and
/// what it says reaches the players, so a spectator can ask for the tape.
///
/// [port] defaults to `0`, which asks the system for whichever port is
/// free — the line this prints on startup is how a caller that bound to
/// `0` (a test, most often) reads back which one it actually got.
/// One party: its players by slot, nobody in a slot that was left, and its
/// spectators.
final class _Party {
  _Party(this.size);

  final int size;
  final List<WebSocket?> players = <WebSocket?>[];
  final List<WebSocket> watchers = <WebSocket>[];

  Iterable<WebSocket> get everyone => <WebSocket>[
    for (final player in players) ?player,
    ...watchers,
  ];
}

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 0;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  // Read by `test/relay_test.dart` off the child process's own stdout, the
  // same way `run_timeline_extensions_test.dart` reads a VM service URI off
  // `flutter test -v`'s.
  stdout.writeln('flutter3d_net relay listening on ${server.port}');

  final rooms = <String, List<WebSocket>>{};
  final parties = <String, _Party>{};

  await for (final request in server) {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('this is a WebSocket relay, not a page');
      await request.response.close();
      continue;
    }
    final segments = request.uri.pathSegments;
    if (segments.length == 2 &&
        (segments[0] == 'party' || segments[0] == 'watch') &&
        segments[1].isNotEmpty) {
      await _joinParty(
        request,
        parties,
        segments[1],
        watching: segments[0] == 'watch',
      );
      continue;
    }
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

/// Joins [request] to the party [code] — as the next player, or with
/// [watching] as a spectator — tells it its slot, and forwards what it
/// sends to everybody else there.
Future<void> _joinParty(
  HttpRequest request,
  Map<String, _Party> parties,
  String code, {
  required bool watching,
}) async {
  final asked = int.tryParse(request.uri.queryParameters['size'] ?? '') ?? 4;
  final party = parties[code];
  if (party == null && watching) {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
    return;
  }
  final room = parties[code] ??= _Party(asked.clamp(2, 32));
  final socket = await WebSocketTransformer.upgrade(request);
  final int slot;
  if (watching) {
    slot = room.size + room.watchers.length;
    room.watchers.add(socket);
  } else {
    final free = room.players.indexOf(null);
    if (free < 0 && room.players.length >= room.size) {
      await socket.close(
        WebSocketStatus.policyViolation,
        'party $code already has ${room.size} players',
      );
      return;
    }
    slot = free >= 0 ? free : room.players.length;
    if (free >= 0) {
      room.players[free] = socket;
    } else {
      room.players.add(socket);
    }
  }
  socket.add(
    jsonEncode(<String, Object?>{
      'relay': 'welcome',
      'slot': slot,
      'size': room.size,
      'watching': watching,
    }),
  );
  socket.listen(
    (message) {
      for (final other in room.everyone) {
        if (!identical(other, socket)) other.add(message);
      }
    },
    onDone: () {
      if (watching) {
        room.watchers.remove(socket);
      } else {
        room.players[slot] = null;
      }
      for (final other in room.everyone) {
        other.add(jsonEncode(<String, Object?>{'relay': 'left', 'slot': slot}));
      }
      if (room.everyone.isEmpty) parties.remove(code);
    },
  );
}
