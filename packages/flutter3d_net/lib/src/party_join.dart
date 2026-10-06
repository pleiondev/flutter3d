import 'dart:async';

import 'package:flame_multiplayer/flame_multiplayer.dart';

import 'net_transport_wire.dart';
import 'websocket_transport.dart';

/// A machine's place in a relay's party: its wire, and the slot the relay
/// gave it.
typedef PartySeat = ({
  PartyWire wire,
  int slot,
  int size,
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
Future<PartySeat> joinParty(
  Uri relay,
  String code, {
  int size = 4,
  bool watching = false,
  void Function(int slot)? left,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final socket = await WebSocketTransport.connect(
    relay.replace(
      pathSegments: <String>[watching ? 'watch' : 'party', code],
      queryParameters: watching ? null : <String, String>{'size': '$size'},
    ),
  );
  final welcomed = Completer<({int slot, int size})>();
  final peer = NetTransportWire(socket);
  void Function(Map<String, Object?>)? onward;
  socket.listen((Map<String, Object?> message) {
    switch (message) {
      case {'relay': 'welcome', 'slot': final int slot, 'size': final int of}
          when !welcomed.isCompleted:
        welcomed.complete((slot: slot, size: of));
      case {'relay': 'left', 'slot': final int slot}:
        left?.call(slot);
      default:
        onward?.call(message);
    }
  });
  final seat = await welcomed.future.timeout(timeout);
  final wire = PartyWire.over(
    _Forwarding(peer, (listener) => onward = listener),
    slot: seat.slot,
  );
  return (wire: wire, slot: seat.slot, size: seat.size, socket: socket);
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
