/// The turns of this package, over `flutter3d_net`'s relay and its WebSocket
/// transport: a room met through the relay, and a [BatonStream] handing a
/// turn across it.
///
///     dart test test/relay_turns_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';

Future<({Process process, int port})> _startRelay() async {
  final process = await Process.start('dart', <String>[
    'run',
    'bin/relay.dart',
    '0',
  ], workingDirectory: '../flutter3d_net');
  final portFound = Completer<int>();
  final subscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final match = RegExp(
          r'flutter3d_net relay listening on (\d+)',
        ).firstMatch(line);
        if (match != null && !portFound.isCompleted) {
          portFound.complete(int.parse(match.group(1)!));
        }
      });
  final port = await portFound.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      process.kill();
      throw StateError('the relay never printed the port it bound to');
    },
  );
  await subscription.cancel();
  return (process: process, port: port);
}

void main() {
  test('flame_multiplayer\'s room and turns work over the relay through '
      'its WebSocket transport', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final room = 'turns-${DateTime.now().microsecondsSinceEpoch}';
    final roomUri = Uri.parse('ws://127.0.0.1:${relay.port}/room/$room');
    final transportA = await WebSocketTransport.connect(roomUri);
    final transportB = await WebSocketTransport.connect(roomUri);
    addTearDown(transportA.close);
    addTearDown(transportB.close);

    final roomA = PeerRoom(
      transportA,
      slot: 0,
      about: const <String, Object?>{'plays': 'jet'},
    );
    final roomB = PeerRoom(transportB, slot: 1);
    final frames = <Object?>[];
    Map<String, Object?>? handed;
    final host = BatonStream(
      roomA.channel('turns'),
      holding: true,
      onFrame: (_) {},
      onEvent: (_) {},
      onBaton: (_) {},
    );
    final guest = BatonStream(
      roomB.channel('turns'),
      holding: false,
      onFrame: (f) => frames.add(f['n']),
      onEvent: (_) {},
      onBaton: (s) => handed = s,
    );

    for (var i = 0; i < 400 && !(roomA.hasMet && roomB.hasMet); i++) {
      roomA.step(1 / 60);
      roomB.step(1 / 60);
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(roomB.peer, <String, Object?>{'plays': 'jet'});

    for (var n = 0; n < 30; n++) {
      host.tellFrame(<String, Object?>{'n': n});
      guest.step();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    host.pass(<String, Object?>{'player': 1});
    for (var i = 0; i < 200 && handed == null; i++) {
      guest.step();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(frames, <int>[for (var n = 0; n < 30; n++) n]);
    expect(handed, <String, Object?>{'player': 1});
    expect(guest.isHolding, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
