import 'dart:async';

import 'package:flame_multiplayer/flame_multiplayer.dart';

import 'net_transport_wire.dart';
import 'websocket_transport.dart';

/// A machine's place in a relay's party: its wire, the slot the relay gave
/// it, the party's [code] — the one to send a friend — and [full], which
/// completes once every player's slot is taken.
typedef PartySeat = ({
  PartyWire wire,
  int slot,
  int size,
  String code,
  Future<void> full,
  WebSocketTransport socket,
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
Future<PartySeat> joinParty(
  Uri relay,
  String code, {
  int size = 4,
  bool watching = false,
  String terms = '',
  void Function(int slot)? left,
  Duration timeout = const Duration(seconds: 10),
}) => _seat(
  relay.replace(
    pathSegments: <String>[watching ? 'watch' : 'party', code],
    queryParameters: <String, String>{
      if (!watching) 'size': '$size',
      if (terms.isNotEmpty) 'terms': terms,
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
/// circuits, never match each other's players. So do [terms], as
/// [joinParty] reads them.
Future<PartySeat> findParty(
  Uri relay, {
  required String game,
  int size = 4,
  String terms = '',
  void Function(int slot)? left,
  Duration timeout = const Duration(seconds: 10),
}) => _seat(
  relay.replace(
    pathSegments: const <String>['match'],
    queryParameters: <String, String>{
      'size': '$size',
      'game': game,
      if (terms.isNotEmpty) 'terms': terms,
    },
  ),
  left: left,
  timeout: timeout,
);

Future<PartySeat> _seat(
  Uri at, {
  String? code,
  void Function(int slot)? left,
  required Duration timeout,
}) async {
  final socket = await WebSocketTransport.connect(at);
  final welcomed = Completer<({int slot, int size, String code})>();
  final full = Completer<void>();
  final peer = NetTransportWire(socket);
  void Function(Map<String, Object?>)? onward;
  socket.listen((Map<String, Object?> message) {
    switch (message) {
      case {'relay': 'welcome', 'slot': final int slot, 'size': final int of}
          when !welcomed.isCompleted:
        // A relay from before matchmaking names no code; the one asked
        // for is the party's.
        final named = message['code'];
        welcomed.complete((
          slot: slot,
          size: of,
          code: named is String ? named : code ?? '',
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
  final wire = PartyWire.over(
    _Forwarding(peer, (listener) => onward = listener),
    slot: seat.slot,
  );
  return (
    wire: wire,
    slot: seat.slot,
    size: seat.size,
    code: seat.code,
    full: full.future,
    socket: socket,
  );
}

/// [inner]'s sending, and a listener [attach] puts behind the relay's own
/// messages.
final class _Forwarding implements PeerWire {
  _Forwarding(this.inner, this.attach);

  final PeerWire inner;
  final void Function(void Function(Map<String, Object?>) listener) attach;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) =>
      inner.send(message, reliable: reliable);

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      attach(onMessage);
}
