@TestOn('vm')
library;

/// `net-03`'s remaining "не сделано": a real create/join-by-code screen's
/// connection half. `NetRace` and the relay are net-03's/net-02's own
/// mechanism, proved on `net_race_test.dart`; this file proves the piece
/// that was still missing — deciding who is car 0, connecting to a real
/// relay by a shared code, and writing each side's own `.f3drun`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter3d_demo_racing/src/net_race_session.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');

TrackDocument _shipped([String circuit = 'ring']) => TrackDocument.fromJson(
  jsonDecode(File('assets/tracks/$circuit.json').readAsStringSync())
      as Map<String, Object?>,
);

CollisionWorld _worldFor(TrackDocument document) {
  final world = CollisionWorld();
  document.level?.addTo(world);
  return world;
}

void _drive(InputState input, int step, {int offset = 0}) {
  final s = step + offset;
  input.setActionValue(_throttle, s % 40 < 30 ? 1.0 : 0.0);
  input.setActionValue(_brake, (s % 200 >= 150 && s % 200 < 170) ? 0.6 : 0.0);
  final steeringRight = s % 80 < 40;
  input.setActionValue(_right, steeringRight ? 0.4 : 0.0);
  input.setActionValue(_left, steeringRight ? 0.0 : 0.4);
}

Future<({Process process, int port})> _startRelay() async {
  final process = await Process.start(
    'dart',
    <String>['run', 'bin/relay.dart', '0'],
    workingDirectory: '${Directory.current.path}/../../packages/flutter3d_net',
  );
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
  test('randomRoomCode never uses a character that reads ambiguously', () {
    final dice = Random(7);
    for (var i = 0; i < 200; i++) {
      final code = NetRaceSession.randomRoomCode(random: dice);
      expect(code.length, 5);
      expect(code.contains('0'), isFalse);
      expect(code.contains('O'), isFalse);
      expect(code.contains('1'), isFalse);
      expect(code.contains('I'), isFalse);
    }
  });

  test('create and join over a real relay agree on car slots, converge, and '
      'each write their own readable .f3drun', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final relayBase = Uri.parse('ws://127.0.0.1:${relay.port}/');

    final inputA = InputState();
    final inputB = InputState();

    final sessionA = await NetRaceSession.create(
      relayBase: relayBase,
      document: _shipped(),
      world: _worldFor(_shipped()),
      input: inputA,
      trackAsset: 'assets/tracks/ring.json',
    );
    addTearDown(sessionA.dispose);

    final sessionB = await NetRaceSession.join(
      relayBase: relayBase,
      document: _shipped(),
      world: _worldFor(_shipped()),
      input: inputB,
      trackAsset: 'assets/tracks/ring.json',
      roomCode: sessionA.roomCode,
    );
    addTearDown(sessionB.dispose);

    expect(sessionA.localCarIndex, 0);
    expect(sessionB.localCarIndex, 1);
    expect(sessionA.connected, isFalse);
    expect(sessionB.connected, isFalse);

    const raceSteps = 400;
    for (var i = 0; i < raceSteps + 60; i++) {
      _drive(inputA, i);
      sessionA.advance();
      inputA.endStep();

      _drive(inputB, i, offset: 37);
      sessionB.advance();
      inputB.endStep();

      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    expect(
      sessionA.connected,
      isTrue,
      reason: 'a race this long over a local relay must have connected',
    );
    expect(sessionB.connected, isTrue);

    final dir = Directory.systemTemp.createTempSync('net_race_session');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pathA = '${dir.path}/side_a.f3drun';
    final pathB = '${dir.path}/side_b.f3drun';
    sessionA.saveRunTo(pathA, buildStamp: 'test');
    sessionB.saveRunTo(pathB, buildStamp: 'test');

    final demoA = Demo.fromJson(
      jsonDecode(File(pathA).readAsStringSync()) as Map<String, Object?>,
    );
    final demoB = Demo.fromJson(
      jsonDecode(File(pathB).readAsStringSync()) as Map<String, Object?>,
    );

    // Each side's own `.f3drun` is its own local driving, not the whole
    // match — see the class doc on `NetRaceSession` for why that is the
    // honest shape of a two-player run rather than a gap in it.
    expect(demoA.level, 'assets/tracks/ring.json');
    expect(demoA.levelHash, demoB.levelHash);
    expect(demoA.tape.steps, greaterThan(0));
    expect(demoB.tape.steps, greaterThan(0));

    // "Оба файла прогона дают одинаковые дайджесты" — proven the same
    // way `net_race_test.dart` already proves convergence, just read
    // back off the files each session actually wrote to disk.
    final divergence = demoA.checkpoints.divergenceFromHex(
      demoB.checkpoints.hexDigests,
    );
    expect(divergence, isNull, reason: 'checkpoints diverged at $divergence');
    expect(demoA.checkpoints.steps, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
