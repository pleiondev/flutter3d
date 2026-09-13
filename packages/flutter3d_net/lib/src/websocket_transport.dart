import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'net_transport.dart';

/// [NetTransport] over a plain `WebSocket`, through `net-02`'s relay —
/// `doc/tooling-plan.md`'s named fallback for whatever a WebRTC data channel
/// could not reach: a platform it has not been wired into yet, or a network
/// whose NAT neither side's ICE candidates got through.
///
/// **Every game frame rides the relay, for as long as this transport is the
/// one in use.** Unlike a WebRTC transport, where the relay's job shrinks to
/// signalling once the peers have found each other directly, a WebSocket
/// connection *is* the data path — the relay in `bin/relay.dart` forwards
/// every message for the whole life of the room, which is exactly why this
/// is named a fallback rather than the plan.
///
/// [web_socket_channel] rather than `dart:io`'s `WebSocket` because this
/// half of `net-02` has to compile for the web too — a browser has no
/// `dart:io`, and this is meant to be the same class whether the caller is
/// a native build or one running in a tab.
final class WebSocketTransport implements NetTransport {
  WebSocketTransport(this._channel) {
    _channel.stream.listen((raw) {
      final decoded = jsonDecode(raw as String);
      if (decoded is Map<String, Object?>) _listener?.call(decoded);
    });
  }

  final WebSocketChannel _channel;
  void Function(Map<String, Object?> message)? _listener;

  /// Connects to a relay room at [uri] — `ws://host:port/room/<code>`, the
  /// shape `bin/relay.dart` listens on — and waits for the socket to
  /// actually be open before returning, so a caller's first [send] is never
  /// racing the handshake.
  static Future<WebSocketTransport> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return WebSocketTransport(channel);
  }

  @override
  void send(Map<String, Object?> message) =>
      _channel.sink.add(jsonEncode(message));

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      _listener = onMessage;

  /// Closes the underlying socket. Safe to call more than once.
  Future<void> close() => _channel.sink.close();
}
