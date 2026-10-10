import 'dart:async';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationVersion;

import 'peer_wire.dart';
import 'websocket_transport.dart';
import 'wire_hello.dart';

/// A machine's place in a relay's party: its wire, the slot the relay gave
/// it, the party's [code] — the one to send a friend — and [full], which
/// completes once every player's slot is taken.
///
/// `owner` is the token the relay welcomed the machine that opened the
/// party with, and null for everybody else: it is what a spectator is let
/// in with ([joinParty]'s `owner`), so the host hands it only to whoever it
/// invites to watch.
typedef PartySeat = ({
  PeerWire wire,
  int slot,
  int size,
  String code,
  Future<void> full,
  WebSocketTransport socket,
  String? owner,
});

/// Joins the party [code] on the relay at [relay] — `ws://host:port/` —
/// as a player, or with [watching] as a spectator, and answers once the
/// relay has said which slot is this machine's; a party of [size] when this
/// machine is the first to ask for [code].
///
/// The relay's own messages — the welcome, who left — arrive on the wire
/// unsigned, and the [PartyWire] it hands back passes on only what machines
/// sent, each with its sender's slot. [left] is told of a slot whose
/// machine went away.
///
/// [terms] is what every machine in the party has to share, the physics
/// backend for one: the first to ask sets them, and the relay turns away a
/// machine asking with others — the future fails with the relay's reason.
///
/// [simulation] is the game's ([SimulationVersion], as `WireHello` carries
/// it), held the same way: a party runs one, and a machine on another is
/// turned away with a reason naming both. Null names none, which meets only
/// another that names none. The protocol this build speaks
/// always goes with it, and a relay of another major turns the machine away.
///
/// [owner] is what a spectator is let in with: the `owner` of the seat the
/// party's host was given. A relay turns a watcher away without it.
Future<PartySeat> joinParty(
  Uri relay,
  String code, {
  int size = 4,
  bool watching = false,
  String? owner,
  String terms = '',
  SimulationVersion? simulation,
  void Function(int slot)? left,
  Duration timeout = const Duration(seconds: 10),
}) => _seat(
  relay.replace(
    pathSegments: <String>[watching ? 'watch' : 'party', code],
    queryParameters: <String, String>{
      if (!watching) 'size': '$size',
      if (watching) 'owner': ?owner,
      if (terms.isNotEmpty) 'terms': terms,
      ..._versions(simulation),
    },
  ),
  code: code,
  left: left,
  timeout: timeout,
);

/// Finds a party of [size] for [game] on the relay at [relay] — one still
/// filling with strangers who asked for the same, or a new one — and
/// answers with this machine's seat in it. The seat's `code` is the
/// party's, for a friend to join by; its `full` completes when the last
/// player arrives, which is when a game should start.
///
/// [game] keeps games apart: two games on one relay, or one game's
/// circuits, never match each other's players. So do [terms] and
/// [simulation], as [joinParty] reads them: a match forms only between
/// builds on the same simulation.
Future<PartySeat> findParty(
  Uri relay, {
  required String game,
  int size = 4,
  String terms = '',
  SimulationVersion? simulation,
  void Function(int slot)? left,
  Duration timeout = const Duration(seconds: 10),
}) => _seat(
  relay.replace(
    pathSegments: const <String>['match'],
    queryParameters: <String, String>{
      'size': '$size',
      'game': game,
      if (terms.isNotEmpty) 'terms': terms,
      ..._versions(simulation),
    },
  ),
  left: left,
  timeout: timeout,
);

/// The address of the two-player room [code] on the relay at [relay] —
/// `ws://host:port/` — for [WebSocketTransport.connect], asking with
/// [terms], this build's protocol and the game's [simulation], as
/// [joinParty] does: a machine on another simulation is closed with
/// the relay's reason, which [WebSocketTransport.closed] answers.
Uri relayRoom(
  Uri relay,
  String code, {
  String terms = '',
  SimulationVersion? simulation,
}) => relay.replace(
  pathSegments: <String>['room', code],
  queryParameters: <String, String>{
    if (terms.isNotEmpty) 'terms': terms,
    ..._versions(simulation),
  },
);

/// The versions a relay is asked with: this build's protocol, and the
/// game's [simulation] when it names one.
Map<String, String> _versions(SimulationVersion? simulation) =>
    <String, String>{
      'protocol':
          '${WireHello.currentProtocolMajor}.${WireHello.currentProtocolMinor}',
      'simulation': ?simulation?.describe(),
    };

Future<PartySeat> _seat(
  Uri at, {
  String? code,
  void Function(int slot)? left,
  required Duration timeout,
}) async {
  final socket = await WebSocketTransport.connect(at);
  final welcomed =
      Completer<({int slot, int size, String code, String? owner})>();
  final full = Completer<void>();
  void Function(Map<String, Object?>)? onward;
  socket.listen((Map<String, Object?> message) {
    switch (message) {
      case {'relay': 'welcome', 'slot': final int slot, 'size': final int of}
          when !welcomed.isCompleted:
        // A relay from before matchmaking names no code; the one asked
        // for is the party's.
        final named = message['code'];
        final owner = message['owner'];
        welcomed.complete((
          slot: slot,
          size: of,
          code: named is String ? named : code ?? '',
          owner: owner is String ? owner : null,
        ));
      case {'relay': 'full'}:
        if (!full.isCompleted) full.complete();
      case {'relay': 'left', 'slot': final int slot}:
        left?.call(slot);
      default:
        onward?.call(message);
    }
  });
  // Turned away — a full party, other terms — before a welcome: say why
  // now rather than at the timeout.
  unawaited(
    socket.closed.then((String? reason) {
      if (welcomed.isCompleted) return;
      welcomed.completeError(
        StateError('the relay closed $at: ${reason ?? 'no reason given'}'),
      );
    }),
  );
  final seat = await welcomed.future.timeout(timeout);
  final wire = PeerWire.party(
    _Forwarding(socket, (listener) => onward = listener),
    slot: seat.slot,
  );
  return (
    wire: wire,
    slot: seat.slot,
    size: seat.size,
    code: seat.code,
    full: full.future,
    socket: socket,
    owner: seat.owner,
  );
}

/// [inner]'s sending, and what [attach] hands on from behind the relay's
/// own messages delivered to whoever listens.
final class _Forwarding extends PeerWire {
  _Forwarding(this.inner, this.attach) {
    attach(deliver);
  }

  @override
  WireState get state => inner.state;

  @override
  Future<void> close() => inner.close();

  final PeerWire inner;
  final void Function(void Function(Map<String, Object?>) listener) attach;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) =>
      inner.send(message, reliable: reliable);
}
