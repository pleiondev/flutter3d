import 'package:flame_multiplayer/flame_multiplayer.dart';

import 'net_transport.dart';

/// Any [NetTransport] as a `flame_multiplayer` [PeerWire]: the relay's
/// [WebSocketTransport], a WebRTC data channel, the [LoopbackTransport] of a
/// test.
///
/// **One kind of delivery for both.** A transport here makes no promise
/// either way and is asked for none, so reliable and unreliable messages go
/// the same road. Over the relay's WebSocket both arrive, once and in order;
/// over a lossy [LoopbackTransport] both may be lost, which is a test of the
/// unreliable kind only — a mode that needs reliable messages wants a
/// loopback with no loss.
final class NetTransportWire implements PeerWire {
  NetTransportWire(this.transport);

  final NetTransport transport;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) =>
      transport.send(message);

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      transport.listen(onMessage);
}
