/// Bytes on a wire: as they are where the wire carries binary, as base64
/// inside a JSON frame where it carries only messages, and never mixed up
/// with the messages either way.
///
///     dart test test/wire_bytes_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';

/// A wire that carries only JSON, through its [PeerWire.send]: every byte
/// message it sends is the default base64 frame. Joined to another of its
/// kind, delivering at once.
final class _JsonOnly extends PeerWire {
  _JsonOnly(this.slot);

  @override
  final int slot;

  late final _JsonOnly peer;

  /// Every message sent, as the far side received it.
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) {
    sent.add(message);
    peer.deliver(message);
  }
}

// Who sent and what, as a list rather than a record: a record's `==` holds
// its fields to `==`, and a `List` there is equal only to itself.
void main() {
  test('a loopback carries bytes as bytes, late and in order', () {
    // Mutation: deliver due bytes before due messages — the order the two
    // were sent in is lost.
    final (a, b) = LoopbackWire.pair(delaySteps: 2);
    final order = <Object>[];
    b
      ..listen(order.add)
      ..listenBytes((from, bytes) => order.add(<Object>[from, bytes.toList()]));
    final buffer = Uint8List.fromList(<int>[1, 2, 3]);
    a
      ..send(<String, Object?>{'n': 1})
      ..sendBytes(buffer);
    // The sender reuses its buffer; the far side has its own copy.
    buffer[0] = 99;
    b.tick();
    expect(order, isEmpty);
    b.tick();
    expect(order, <Object>[
      <String, Object?>{'n': 1},
      <Object>[
        0,
        <int>[1, 2, 3],
      ],
    ]);
  });

  test('a wire that carries only JSON sends bytes in a base64 frame', () {
    // Mutation: hand the frame to the message listeners too — a game hears
    // a message with the engine's key that it never sent.
    final a = _JsonOnly(0);
    final b = _JsonOnly(1);
    a.peer = b;
    b.peer = a;
    final messages = <Map<String, Object?>>[];
    final bytes = <Uint8List>[];
    b
      ..listen(messages.add)
      ..listenBytes((from, data) {
        expect(from, 0);
        bytes.add(data);
      });
    a.sendBytes(Uint8List.fromList(<int>[0, 255, 7]));
    expect(a.sent.single[PeerWire.engineKey], PeerWire.bytesFrame);
    expect(a.sent.single[PeerWire.bytesKey], isA<String>());
    expect(bytes.single, <int>[0, 255, 7]);
    expect(messages, isEmpty);
  });

  test('a party carries bytes with who sent them', () {
    // Mutation: deliver a party's bytes as from the other of two — slot 2
    // reads as slot 1 sending.
    final party = LoopbackParty(3);
    final heard = <List<Object>>[];
    party
        .wire(0)
        .listenBytes((from, data) => heard.add(<Object>[from, data.toList()]));
    party.wire(2).sendBytes(Uint8List.fromList(<int>[5]));
    party.tick();
    expect(heard, <List<Object>>[
      <Object>[
        2,
        <int>[5],
      ],
    ]);
  });

  test('a party over a relay carries bytes inside its envelope', () {
    // Mutation: let the relay's `{from, body}` envelope carry the frame
    // unread — the bytes arrive as a message with the engine's key.
    final (a, b) = LoopbackWire.pair();
    final left = PeerWire.party(a, slot: 0);
    final right = PeerWire.party(b, slot: 1);
    final heard = <List<Object>>[];
    final messages = <Map<String, Object?>>[];
    right
      ..listen(messages.add)
      ..listenBytes((from, data) => heard.add(<Object>[from, data.toList()]));
    left.sendBytes(Uint8List.fromList(<int>[42, 43]));
    b.tick();
    expect(heard, <List<Object>>[
      <Object>[
        0,
        <int>[42, 43],
      ],
    ]);
    expect(messages, isEmpty);
  });

  test('a cancelled byte listener hears nothing more', () {
    final (a, b) = LoopbackWire.pair();
    final heard = <List<int>>[];
    final listening = b.listenBytes((_, data) => heard.add(data.toList()));
    a.sendBytes(Uint8List.fromList(<int>[1]));
    b.tick();
    listening.cancel();
    a.sendBytes(Uint8List.fromList(<int>[2]));
    b.tick();
    expect(heard, <List<int>>[
      <int>[1],
    ]);
  });
}
