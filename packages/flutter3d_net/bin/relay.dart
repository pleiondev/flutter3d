import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
/// `/match?size=N&game=<name>` — matchmaking for strangers: a party of N
/// for that game that is still filling, or a new one under a fresh code.
/// The welcome carries the `code`, so friends can still be sent after a
/// matched party, and once a party has all its players everyone in it is
/// told `{"relay": "full", "size": N}` — the moment a game can start. A
/// full party is matched no further, even when somebody leaves it: a race
/// under way is not where a stranger should land.
///
/// `terms=<text>` on any of the three — what every machine in a room or
/// party has to share for their simulations to agree, such as the physics
/// backend a game steps on. The first machine sets them; one asking with
/// other terms is closed with a policy violation whose reason names both.
/// Matchmaking keys on them, so strangers on different terms are never put
/// together. No `terms` is the empty text, and is held to like any other.
///
/// [port] defaults to `0`, which asks the system for whichever port is
/// free — the line this prints on startup is how a caller that bound to
/// `0` (a test, most often) reads back which one it actually got.
/// One party: its players by slot, nobody in a slot that was left, and its
/// spectators.
final class _Party {
  _Party(this.size, this.terms);

  final int size;
  final String terms;
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
  // What the first socket of each room asked for.
  final roomTerms = <String, String>{};
  final parties = <String, _Party>{};
  // The party still filling for each game and size, by its code.
  final filling = <String, String>{};
  final dice = math.Random.secure();

  await for (final request in server) {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('this is a WebSocket relay, not a page');
      await request.response.close();
      continue;
    }
    final segments = request.uri.pathSegments;
    if (segments.length == 1 && segments[0] == 'match') {
      final query = request.uri.queryParameters;
      final size = (int.tryParse(query['size'] ?? '') ?? 4).clamp(2, 32);
      final key = '${query['game'] ?? ''}/$size/${_termsOf(request)}';
      final open = filling[key];
      final code = open != null && parties.containsKey(open)
          ? open
          : filling[key] = _freshCode(dice, parties);
      await _joinParty(
        request,
        parties,
        code,
        watching: false,
        size: size,
        onFull: () => filling.remove(key),
      );
      continue;
    }
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
    final terms = _termsOf(request);
    final held = roomTerms.putIfAbsent(code, () => terms);
    if (held != terms) {
      await socket.close(
        WebSocketStatus.policyViolation,
        _otherTerms('room $code', held, terms),
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
        if (room.isEmpty) {
          rooms.remove(code);
          roomTerms.remove(code);
        }
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
  int? size,
  void Function()? onFull,
}) async {
  final asked =
      size ?? int.tryParse(request.uri.queryParameters['size'] ?? '') ?? 4;
  final party = parties[code];
  if (party == null && watching) {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
    return;
  }
  final terms = _termsOf(request);
  final room = parties[code] ??= _Party(asked.clamp(2, 32), terms);
  final socket = await WebSocketTransformer.upgrade(request);
  if (room.terms != terms) {
    await socket.close(
      WebSocketStatus.policyViolation,
      _otherTerms('party $code', room.terms, terms),
    );
    if (room.everyone.isEmpty) parties.remove(code);
    return;
  }
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
      'code': code,
    }),
  );
  if (!watching && room.players.nonNulls.length == room.size) {
    onFull?.call();
    for (final other in room.everyone) {
      other.add(
        jsonEncode(<String, Object?>{'relay': 'full', 'size': room.size}),
      );
    }
  }
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

/// The terms [request] asked for, the empty text when it named none.
String _termsOf(HttpRequest request) =>
    request.uri.queryParameters['terms'] ?? '';

/// Why a machine asking with [asked] was turned away from [what], held to
/// [held]. The close reason a client shows, cut to the 123 bytes a close
/// frame carries.
String _otherTerms(String what, String held, String asked) {
  final reason =
      '$what plays under "$held", and this machine asked for "$asked"';
  final bytes = utf8.encode(reason);
  return bytes.length <= 123
      ? reason
      : utf8.decode(bytes.sublist(0, 123), allowMalformed: true);
}

/// Five letters no one misreads, for a party nobody named: the alphabet of
/// the racing game's room codes, without I, O, 0 and 1.
String _freshCode(math.Random dice, Map<String, _Party> parties) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  while (true) {
    final code = String.fromCharCodes(<int>[
      for (var i = 0; i < 5; i++)
        alphabet.codeUnitAt(dice.nextInt(alphabet.length)),
    ]);
    if (!parties.containsKey(code)) return code;
  }
}
