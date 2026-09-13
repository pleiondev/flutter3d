/// One unreliable, unordered channel to the other peer — real transports
/// (a WebRTC data channel, a WebSocket through the relay) implement this;
/// `LoopbackTransport` stands in for one in a test.
///
/// **Deliberately this narrow.** [NetSession] sends one small JSON-shaped
/// message per step and reads whatever arrives whenever it arrives — it does
/// not ask a transport to guarantee order, delivery, or a round trip, because
/// none of the real ones this package will eventually sit on can promise
/// that for free, and a rollback engine that assumed otherwise would work
/// perfectly against `LoopbackTransport` and nowhere else.
abstract interface class NetTransport {
  /// Hands [message] to the transport to deliver whenever it can. Returns
  /// immediately — a message dropped in flight is not an error here, the
  /// same way an unacknowledged UDP datagram is not one at the socket layer.
  void send(Map<String, Object?> message);

  /// Calls [onMessage] for every message this transport delivers, from now
  /// on. At most one listener; a second call replaces the first, which is
  /// [NetSession]'s own contract with itself and not something a transport
  /// needs to guard.
  void listen(void Function(Map<String, Object?> message) onMessage);
}
