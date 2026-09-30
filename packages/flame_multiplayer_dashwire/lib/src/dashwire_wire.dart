import 'dart:async';
import 'dart:convert';

import 'package:dashwire/dashwire.dart';
import 'package:flame_multiplayer/flame_multiplayer.dart';

/// A dashwire [WireConnection] as a `flame_multiplayer` [PeerWire].
///
/// **Both kinds of delivery, each on its own channel.** A reliable message
/// goes on [Channel.reliable] and an unreliable one on [Channel.unreliable]:
/// over a transport that has both, a rollback frame is never held up behind
/// a lost one, and a turn handed over is never lost. Over dashwire's
/// WebSocket both happen to arrive; nothing here depends on that.
///
/// **JSON in UTF-8 on the wire,** the shape every message here already has.
/// A payload that is not one — something else on the same connection — is
/// passed over, not thrown on.
final class DashwireWire implements PeerWire {
  DashwireWire(this.connection) {
    _subscription = connection.messages.listen(_hear);
  }

  final WireConnection connection;
  late final StreamSubscription<NetMessage> _subscription;
  void Function(Map<String, Object?> message)? _listener;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) {
    if (!connection.isOpen) return;
    connection.send(
      reliable ? Channel.reliable : Channel.unreliable,
      utf8.encode(jsonEncode(message)),
    );
  }

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      _listener = onMessage;

  void _hear(NetMessage message) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(message.payload));
    } on FormatException {
      return;
    }
    if (decoded is Map<String, Object?>) _listener?.call(decoded);
  }

  /// Stops listening and closes the connection.
  Future<void> close() async {
    await _subscription.cancel();
    await connection.close();
  }
}
