import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
///
/// **Bytes as they are** ([sendBytes]): a payload whose first byte is
/// [bytesTag], nought, and the bytes after it. JSON never starts with that
/// byte, so the two cannot be taken for each other; a machine that sent its
/// bytes as base64 inside a JSON frame is heard as bytes all the same.
final class DashwireWire extends PeerWire {
  DashwireWire(this.connection) {
    _subscription = connection.messages.listen(_hear);
  }

  final WireConnection connection;

  @override
  WireState get state => connection.isOpen ? WireState.open : WireState.closed;
  late final StreamSubscription<NetMessage> _subscription;

  /// The first byte of a payload that carries bytes rather than JSON.
  static const int bytesTag = 0;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) {
    if (!connection.isOpen) return;
    connection.send(
      reliable ? Channel.reliable : Channel.unreliable,
      utf8.encode(jsonEncode(message)),
    );
  }

  @override
  void sendBytes(Uint8List bytes, {bool reliable = true}) {
    if (!connection.isOpen) return;
    final payload = Uint8List(bytes.length + 1)
      ..[0] = bytesTag
      ..setRange(1, bytes.length + 1, bytes);
    connection.send(reliable ? Channel.reliable : Channel.unreliable, payload);
  }

  void _hear(NetMessage message) {
    final payload = message.payload;
    if (payload.isNotEmpty && payload[0] == bytesTag) {
      deliverBytes(Uint8List.sublistView(payload, 1));
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(payload));
    } on FormatException {
      return;
    }
    if (decoded is Map<String, Object?>) deliver(decoded);
  }

  /// Stops listening and closes the connection.
  @override
  Future<void> close() async {
    await _subscription.cancel();
    await connection.close();
  }
}
