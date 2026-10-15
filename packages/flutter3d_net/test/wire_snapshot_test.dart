/// The wire as a contract: `api/flutter3d_net.wire` against the messages
/// the code sends and the golden JSON minted for protocol 3.
///
///     dart test test/wire_snapshot_test.dart
///
/// **The snapshot is written in literals, not the code's constants.** Every
/// other wire test builds its messages from `PeerWire.engineKey` and the
/// like, so a renamed key passes them all; here the key is read from the
/// snapshot's text and the code has to send it. The structure check holds
/// the snapshot to the base its major was recorded with, so a line can be
/// added within protocol 3 and never removed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

import 'wire_contract.dart';

/// A wire that keeps what it is asked to send.
final class _Tap extends PeerWire {
  _Tap(this.slot);

  @override
  final int slot;

  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  @override
  void send(PeerSend context) => sent.add(context.message);
}

Map<String, Object?> _golden(String name) =>
    jsonDecode(
          File(
            'test/fixtures/wire/v${WireHello.currentProtocolMajor}/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  final wire = readWire();

  test('names the protocol this build speaks', () {
    // Mutation: bump the minor without a line here, and the snapshot no
    // longer says which protocol its lines are.
    expect(
      wire.protocol,
      '${WireHello.currentProtocolMajor}.${WireHello.currentProtocolMinor}',
    );
  });

  test('every message has its golden, and every golden its message', () {
    final directory = Directory(
      'test/fixtures/wire/v${WireHello.currentProtocolMajor}',
    );
    final goldens = <String>{
      for (final file in directory.listSync().whereType<File>())
        if (file.path.endsWith('.json'))
          file.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''),
    };
    final messages = <String>{
      for (final block in wire.blocks.values)
        if (block.kind == 'message') block.name,
    };
    expect(goldens, messages);
    for (final name in messages) {
      // Mutation: drop a key from a block that a golden carries, or add
      // one no golden has as always carried, and this names it.
      expect(
        wireProblems(wire.blocks[name]!, _golden(name)),
        isEmpty,
        reason: name,
      );
    }
  });

  test('the code\'s words are the snapshot\'s', () {
    String tag(String message, String key) => wire.blocks[message]!.tags[key]!;
    // Mutation: rename any of these constants, and the far side of a 1.0
    // build no longer recognises the message.
    expect(PeerWire.engineKey, 'f3d');
    expect(tag('rollback', PeerWire.engineKey), RollbackSession.messageKind);
    expect(tag('bytes', PeerWire.engineKey), PeerWire.bytesFrame);
    expect(wire.blocks['bytes']!.required, <String>{PeerWire.bytesKey});
    expect(tag('route', PeerWire.engineKey), PeerWire.routeFrame);
    expect(tag('observe.join', PeerWire.engineKey), ObserverMessages.join);
    expect(tag('observe.start', PeerWire.engineKey), ObserverMessages.start);
    expect(tag('observe.step', PeerWire.engineKey), ObserverMessages.step);
    for (final (name, event) in <(String, String)>[
      ('relay.welcome', RelayMessages.welcome),
      ('relay.full', RelayMessages.full),
      ('relay.left', RelayMessages.left),
    ]) {
      expect(tag(name, PeerWire.engineKey), RelayMessages.relay);
      expect(tag(name, RelayMessages.event), event);
    }
  });

  group('what the code sends is the snapshot\'s', () {
    test('a room\'s hello and a channel\'s frame', () {
      final tap = _Tap(0);
      final room = PeerRoom(tap, slot: 0);
      tap.deliver(PeerDelivery(message: _golden('room.hello')));
      room.channel('game').send(PeerSend(message: <String, Object?>{'n': 1}));
      expectOnTheWire(tap.sent.first, 'room.hello');
      expectOnTheWire(tap.sent.last, 'room.channel');
    });

    test('a rollback\'s frames', () {
      final tap = _Tap(0);
      RollbackSession<int>(
        wire: tap,
        captureLocalFrame: () => <String, Object?>{'move': 1},
        applyAndStep: (_) {},
        save: () => 0,
        restore: (_) {},
      ).advance();
      expectOnTheWire(tap.sent.single, 'rollback');
    });

    test('bytes over a wire that carries only messages', () {
      final tap = _Tap(0)
        ..sendBytes(PeerSendBytes(bytes: Uint8List.fromList(<int>[1, 2, 3])));
      expectOnTheWire(tap.sent.single, 'bytes');
      expect(tap.sent.single, _golden('bytes'));
    });

    test('an observer\'s join and the feed\'s start', () {
      final observer = _Tap(1);
      SimulationObserver(
        wire: observer,
        simulation: SimulationVersion.engineOnly,
      ).join();
      expectOnTheWire(observer.sent.single, 'observe.join');

      final feed = _Tap(0);
      ObserverFeed(
        wire: feed,
        simulation: SimulationVersion.engineOnly,
        capture: () => Snapshot(<String, Object?>{}),
      );
      feed.deliver(PeerDelivery(message: observer.sent.single, from: 1));
      expectOnTheWire(feed.sent.single, 'observe.start');
    });

    test('a relay room\'s address', () {
      final address = relayRoom(
        Uri.parse('ws://127.0.0.1:1/'),
        'AB12',
        terms: 'ranked',
        simulation: SimulationVersion.engineOnly,
      );
      final block = wire.blocks['/room/<code>']!;
      expect(address.pathSegments.first, 'room');
      expect(block.required, everyElement(isIn(address.queryParameters.keys)));
      expect(address.queryParameters.keys, everyElement(isIn(block.keys)));
    });
  });
}
