@TestOn('vm')
library;

/// `flame_multiplayer` over dashwire: its network simulator, late, jittery
/// and losing unreliable messages, and its WebSocket through
/// `flutter3d_net`'s relay.
///
///     dart test
///
/// `@TestOn('vm')`: the relay test starts a real process and opens real
/// sockets.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dashwire/dashwire.dart';
import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flame_multiplayer_dashwire/flame_multiplayer_dashwire.dart';
import 'package:test/test.dart';

/// Two dashwire ends as degraded as a bad connection: 15 ms each way, up to
/// 10 ms of jitter, one unreliable message in eight lost and one in twenty
/// arriving twice.
(DashwireWire, DashwireWire) _badConnection() {
  final (a, b) = LoopbackConnection.pair();
  const conditions = SimulatedConditions(
    latency: Duration(milliseconds: 15),
    jitter: Duration(milliseconds: 10),
    unreliableLoss: 0.125,
    unreliableDuplicate: 0.05,
    seed: 7,
  );
  return (
    DashwireWire(SimulatorConnection(a, conditions)),
    DashwireWire(SimulatorConnection(b, conditions)),
  );
}

Future<void> _pause() => Future<void>.delayed(const Duration(milliseconds: 2));

void main() {
  test('a room is met and a rollback settles the same on both over a bad '
      'connection', () async {
    final (wireA, wireB) = _badConnection();
    addTearDown(wireA.close);
    addTearDown(wireB.close);
    final roomA = PeerRoom(wireA, slot: 0, about: const {'plays': 'elf'});
    final roomB = PeerRoom(wireB, slot: 1, about: const {'plays': 'wizard'});
    for (var i = 0; i < 500 && !(roomA.met && roomB.met); i++) {
      roomA.step(1 / 60);
      roomB.step(1 / 60);
      await _pause();
    }
    expect(roomA.peer, {'plays': 'wizard'});
    expect(roomB.peer, {'plays': 'elf'});

    // Two counters walked by two players' hands, and a running sum that any
    // wrong guess left uncorrected would show.
    final games = <List<int>>[
      <int>[0, 0, 0],
      <int>[0, 0, 0],
    ];
    final settled = <Map<int, String>>[<int, String>{}, <int, String>{}];
    final plays = <RollbackPlay<List<int>>>[
      for (final slot in <int>[0, 1])
        RollbackPlay<List<int>>(
          wire: (slot == 0 ? roomA : roomB).channel('play'),
          localSlot: slot,
          capture: () {
            final n = games[slot][2];
            return {'move': (n ~/ (5 + slot * 3)).isEven ? 1 : -1};
          },
          applyAndStep: (hands) {
            final game = games[slot];
            game[0] += (hands[0]['move'] as int?) ?? 0;
            game[1] += (hands[1]['move'] as int?) ?? 0;
            game[2] += game[0] * 3 + game[1] + 1;
          },
          save: () => List<int>.of(games[slot]),
          restore: (state) => games[slot].setAll(0, state),
          maxRollbackFrames: 30,
          onSettled: (step, after) => settled[slot][step] = jsonEncode(after),
        ),
    ];
    for (var i = 0; i < 300; i++) {
      plays[0].advance();
      plays[1].advance();
      await _pause();
    }

    final common = settled[0].keys.where(settled[1].containsKey).toList();
    expect(common.length, greaterThan(200));
    for (final step in common) {
      expect(settled[0][step], settled[1][step], reason: 'step $step');
    }
    expect(plays[0].session.droppedCorrections, 0);
    expect(plays[1].session.droppedCorrections, 0);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('turns keep their order, and the baton arrives, over the reliable '
      'channel of a bad connection', () async {
    final (wireA, wireB) = _badConnection();
    addTearDown(wireA.close);
    addTearDown(wireB.close);
    final shown = <Object?>[];
    Map<String, Object?>? handed;
    final host = BatonStream(
      wireA,
      holding: true,
      onFrame: (_) {},
      onEvent: (_) {},
      onBaton: (_) {},
    );
    final guest = BatonStream(
      wireB,
      holding: false,
      onFrame: (f) => shown.add(f['n']),
      onEvent: (e) => shown.add(e['what']),
      onBaton: (s) => handed = s,
    );
    for (var n = 0; n < 60; n++) {
      host.tellFrame({'n': n});
      if (n == 30) host.tellEvent({'what': 'bridge down'});
      guest.step();
      await _pause();
    }
    host.pass({'player': 1});
    for (var i = 0; i < 300 && handed == null; i++) {
      guest.step();
      await _pause();
    }
    expect(shown, <Object?>[
      for (var n = 0; n <= 30; n++) n,
      'bridge down',
      for (var n = 31; n < 60; n++) n,
    ]);
    expect(handed, {'player': 1});
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('two games meet in a room of flutter3d_net\'s relay through dashwire\'s '
      'WebSocket', () async {
    final relay = await Process.start('dart', <String>[
      'run',
      'bin/relay.dart',
      '0',
    ], workingDirectory: '../flutter3d_net');
    addTearDown(relay.kill);
    final port = Completer<int>();
    relay.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        final match = RegExp(r'listening on (\d+)').firstMatch(line);
        if (match != null && !port.isCompleted) {
          port.complete(int.parse(match.group(1)!));
        }
      },
    );
    final uri = Uri.parse(
      'ws://127.0.0.1:${await port.future.timeout(const Duration(seconds: 20))}'
      '/room/dash-${DateTime.now().microsecondsSinceEpoch}',
    );
    final wireA = DashwireWire(await connectWebSocket(uri));
    final wireB = DashwireWire(await connectWebSocket(uri));
    addTearDown(wireA.close);
    addTearDown(wireB.close);

    final roomA = PeerRoom(wireA, slot: 0, about: const {'plays': 'jet'});
    final roomB = PeerRoom(wireB, slot: 1, about: const {'plays': 'ghost'});
    for (var i = 0; i < 500 && !(roomA.met && roomB.met); i++) {
      roomA.step(1 / 60);
      roomB.step(1 / 60);
      await _pause();
    }
    expect(roomA.peer, {'plays': 'ghost'});
    expect(roomB.peer, {'plays': 'jet'});

    final feedA = PeerFeed(roomA.channel('ghost'));
    final feedB = PeerFeed(roomB.channel('ghost'));
    for (var x = 0; x < 20; x++) {
      feedA.tell(() => {'x': x});
      await _pause();
    }
    for (var i = 0; i < 200 && feedB.latest?['x'] != 19; i++) {
      await _pause();
    }
    expect(feedB.latest, {'x': 19});
    expect(feedA.latest, isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));
}
