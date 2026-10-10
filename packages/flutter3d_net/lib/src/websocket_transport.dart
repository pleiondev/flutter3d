import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'peer_wire.dart';

/// A [PeerWire] over a plain `WebSocket`, through `net-02`'s relay —
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
///
/// **Reliable throughout**: a WebSocket delivers every message once and in
/// order, so both kinds of [send] go the same road.
///
/// **Bytes go as a binary frame** ([sendBytes]), and the relay forwards one
/// as it forwards text: a message is a text frame of JSON, bytes are a
/// binary frame, and a frame of either kind from a machine that sent bytes
/// as base64 inside JSON is delivered as bytes all the same.
final class WebSocketTransport extends PeerWire {
  WebSocketTransport(this._channel) {
    _channel.stream.listen((raw) {
      switch (raw) {
        case final String text:
          final Object? decoded;
          try {
            decoded = jsonDecode(text);
          } on FormatException {
            return;
          }
          if (decoded is Map<String, Object?>) deliver(decoded);
        case final List<int> bytes:
          deliverBytes(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
      }
    }, onDone: () => _closed.complete(_channel.closeReason));
  }

  @override
  WireState get state =>
      _closed.isCompleted ? WireState.closed : WireState.open;

  final WebSocketChannel _channel;
  final Completer<String?> _closed = Completer<String?>();

  /// Completes when the socket closes, from either end, with the reason the
  /// other end gave — the relay's, when it turned this machine away — or
  /// null when it gave none.
  Future<String?> get closed => _closed.future;

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
  void send(Map<String, Object?> message, {bool reliable = true}) =>
      _channel.sink.add(jsonEncode(message));

  @override
  void sendBytes(Uint8List bytes, {bool reliable = true}) =>
      _channel.sink.add(bytes);

  /// Closes the underlying socket. Safe to call more than once.
  @override
  Future<void> close() => _channel.sink.close();
}
