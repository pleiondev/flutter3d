@TestOn('vm')
library;

/// `net-03`'s acceptance, read on the actual genre rather than on a toy:
/// two `RacingSimulation`s, each driven by its own device's input and the
/// other's over a real relay, converge on the same digests — "оба файла
/// прогона дают одинаковые дайджесты" from `doc/tooling-plan.md`.
///
///     dart test test/net_race_test.dart
///
/// The mechanism itself — input delay, prediction, rollback — is net-01's
/// and is proved there and in `flutter3d_net/test/relay_test.dart` on a
/// toy and a bare `NetSession`; what only this file can prove is that
/// `NetRace` wires it to the real `RacingSimulation` correctly: two real
/// cars, on the real shipped `ring.json`, actually arrive at the same
/// place.
///
/// `@TestOn('vm')`: spawns a real relay process and opens real sockets.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_racing/src/net_race.dart';
import 'package:flutter3d_demo_racing/src/staging.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _handbrake = GameAction('handbrake');

TrackDocument _shipped([String circuit = 'ring']) => TrackDocument.fromJson(
  jsonDecode(File('assets/tracks/$circuit.json').readAsStringSync())
      as Map<String, Object?>,
);

({RacingSimulation sim, InputState input}) _stageTwoCars() {
  final document = _shipped();
  final world = CollisionWorld();
  document.level?.addTo(world);
  final input = InputState();
  final staged = stage(document, world, cars: 2, laps: 1);
  return (sim: staged.sim, input: input);
}

/// A driver that touches throttle, brake, both steering directions and the
/// handbrake — [offset] gives the two sides of the test different
/// rhythms, the same reason `net_session_test.dart`'s two toy sides do.
void _drive(InputState input, int step, {int offset = 0}) {
  final s = step + offset;
  input.setActionValue(_throttle, s % 40 < 30 ? 1.0 : 0.0);
  input.setActionValue(_brake, (s % 200 >= 150 && s % 200 < 170) ? 0.6 : 0.0);
  final steeringRight = s % 80 < 40;
  input.setActionValue(_right, steeringRight ? 0.4 : 0.0);
  input.setActionValue(_left, steeringRight ? 0.0 : 0.4);
  if (s == 300) input.press(_handbrake);
  if (s == 305) input.release(_handbrake);
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
  test('two devices racing each other over a real relay end the race agreeing '
      'on every settled checkpoint', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final room = 'race-${DateTime.now().microsecondsSinceEpoch}';
    final roomUri = Uri.parse('ws://127.0.0.1:${relay.port}/room/$room');

    final transportA = await WebSocketTransport.connect(roomUri);
    final transportB = await WebSocketTransport.connect(roomUri);
    addTearDown(transportA.close);
    addTearDown(transportB.close);

    final deviceA = _stageTwoCars();
    final deviceB = _stageTwoCars();
    final digestsA = DigestTrace();
    final digestsB = DigestTrace();

    // The one thing a real "create/join" screen would agree on before a
    // single frame moves: who is car 0. Here, whoever created the room.
    final raceA = NetRace(
      sim: deviceA.sim,
      localCarIndex: 0,
      localInput: deviceA.input,
      transport: transportA,
      inputDelay: 3,
      maxRollbackFrames: 24,
      onSettled: (step, after) => digestsA.observe(step + 1, after.toJson()),
    );
    final raceB = NetRace(
      sim: deviceB.sim,
      localCarIndex: 1,
      localInput: deviceB.input,
      transport: transportB,
      inputDelay: 3,
      maxRollbackFrames: 24,
      onSettled: (step, after) => digestsB.observe(step + 1, after.toJson()),
    );

    const raceSteps = 400;
    for (var i = 0; i < raceSteps + 60; i++) {
      _drive(deviceA.input, i);
      raceA.advance();
      deviceA.input.endStep();

      _drive(deviceB.input, i, offset: 37);
      raceB.advance();
      deviceB.input.endStep();

      // A real socket delivers on the event loop, not synchronously —
      // without yielding here, both sides would run the whole race
      // before either one's `listen` callback ever got a turn to fire.
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    expect(
      raceA.connected,
      isTrue,
      reason: 'a race this long over a local relay must have connected',
    );
    expect(raceB.connected, isTrue);

    final divergence = digestsA.divergenceFromHex(digestsB.hexDigests);
    expect(
      divergence,
      isNull,
      reason:
          'both devices played the same two-car race and should reach '
          'the same settled state at every checkpoint: $divergence',
    );
    expect(digestsA.steps, isNotEmpty);
    expect(raceA.session.droppedCorrections, 0);
    expect(raceB.session.droppedCorrections, 0);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('the very first inputDelay steps — before either side has sent a '
      'message the other could possibly receive — are symmetric', () {
    // **A fast, deterministic regression guard for a real bug this file
    // found.** An earlier version ghosted only the remote car while
    // `inputDelay` held the local one at a bare default — so device A
    // believed its own car did nothing and the other ghosted forward,
    // while device B believed the exact opposite about the same steps,
    // and neither side's timeline was ever addressed by a message that
    // could correct it: the very first frame either side sends is
    // tagged for step `inputDelay`, so steps before it are never
    // confirmed by anyone. `LoopbackTransport` with zero delay makes
    // this reproduce in a few milliseconds rather than needing the real
    // relay above to catch it again.
    final (transportA, transportB) = LoopbackTransport.pair(stepsPerSecond: 60);
    final deviceA = _stageTwoCars();
    final deviceB = _stageTwoCars();
    final digestsA = DigestTrace(every: 1);
    final digestsB = DigestTrace(every: 1);

    final raceA = NetRace(
      sim: deviceA.sim,
      localCarIndex: 0,
      localInput: deviceA.input,
      transport: transportA,
      inputDelay: 3,
      onSettled: (step, after) => digestsA.observe(step + 1, after.toJson()),
    );
    final raceB = NetRace(
      sim: deviceB.sim,
      localCarIndex: 1,
      localInput: deviceB.input,
      transport: transportB,
      inputDelay: 3,
      onSettled: (step, after) => digestsB.observe(step + 1, after.toJson()),
    );

    for (var i = 0; i < 460; i++) {
      _drive(deviceA.input, i);
      raceA.advance();
      deviceA.input.endStep();
      transportA.tick();

      _drive(deviceB.input, i, offset: 37);
      raceB.advance();
      deviceB.input.endStep();
      transportB.tick();
    }

    expect(digestsA.divergenceFromHex(digestsB.hexDigests), isNull);
  });
}
