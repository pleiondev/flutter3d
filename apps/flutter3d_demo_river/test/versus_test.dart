/// Two players on one river: taking turns on one machine and on two, and a
/// race with a ghost — the real game, stepped as `game_test` steps it, over
/// `flame_multiplayer`'s loopback wire.
library;

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_river/src/course.dart';
import 'package:flutter3d_demo_river/src/river_game.dart';
import 'package:flutter3d_demo_river/src/rules.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show GameAction;
import 'package:flutter_test/flutter_test.dart';

Future<RiverGame> _newGame({Versus? versus, String? room, int slot = 0}) async {
  final game = await initializeGame(
    () => RiverGame(versus: versus, room: room, slot: slot),
  );
  game.open3d(cpuTestDevice(width: 32, height: 24).device);
  await game.ready();
  return game;
}

/// Steps every game in [games] one sixtieth together, and the wires between
/// them, [steps] times.
Future<void> _run(
  List<RiverGame> games,
  int steps, {
  List<LoopbackWire> wires = const <LoopbackWire>[],
  bool Function()? until,
}) async {
  for (var i = 0; i < steps; i++) {
    if (until?.call() ?? false) return;
    for (final game in games) {
      game.update(1 / 60);
    }
    for (final wire in wires) {
      wire.tick();
    }
    for (final game in games) {
      await game.ready();
    }
  }
}

/// Holds [game]'s stick left from take-off until its jet is on the bank.
Future<void> _crashLeft(
  RiverGame game, {
  List<RiverGame> also = const <RiverGame>[],
  List<LoopbackWire> wires = const <LoopbackWire>[],
}) async {
  game.input
    ..press(RiverGame.fire)
    ..press(GameAction.moveLeft);
  await _run(
    <RiverGame>[game, ...also],
    400,
    wires: wires,
    until: () => game.phase == Phase.crashed,
  );
  expect(game.phase, Phase.crashed);
  game.input
    ..release(RiverGame.fire)
    ..release(GameAction.moveLeft);
}

const int _pause = (RiverGame.crashPause * 60) ~/ 1 + 4;

void main() {
  group('Turns', () {
    test('a lost jet hands over to the other player, who starts on a jet '
        'of their own', () {
      final t = Turns();
      expect(t.player, 0);
      expect(t.next(), 1);
      expect(t.runs[1].reserve, RunState.startingReserve);
      expect(t.next(), 0);
      expect(t.runs[0].reserve, RunState.startingReserve - 1);

      // One player out of jets: the other flies on alone, then it is over.
      t.runs[1].reserve = 0;
      t.player = 1;
      expect(t.next(), 0);
      t.runs[0].reserve = 0;
      expect(t.next(), isNull);
    });

    test('travels as JSON and comes back the same', () {
      final t = Turns()
        ..runs[0].award(12340)
        ..runs[1].count(TargetKind.tanker)
        ..next();
      final back = Turns()..load(t.toJson());
      expect(back.toJson(), t.toJson());
      expect(back.player, 1);
      expect(back.runs[0].reserve, RunState.startingReserve + 1);
      expect(back.runs[1].tally[TargetKind.tanker], 1);
    });
  });

  test('on one machine a crash passes the keys, and each player keeps their '
      'own run', () async {
    final game = await _newGame(versus: Versus.turns);
    final t = game.turns!;
    expect(t.player, 0);

    await _crashLeft(game);
    await _run(<RiverGame>[game], _pause);
    expect(t.player, 1);
    expect(game.phase, Phase.ready);
    expect(identical(game.run, t.runs[1]), isTrue);
    expect(t.runs[1].reserve, RunState.startingReserve);

    await _crashLeft(game);
    await _run(<RiverGame>[game], _pause);
    expect(t.player, 0);
    expect(t.runs[0].reserve, RunState.startingReserve - 1);
    expect(t.runs[1].reserve, RunState.startingReserve);
  });

  test('on two machines the other watches the flight, sees what it shot, and '
      'flies when the jet is lost', () async {
    final (wireA, wireB) = LoopbackWire.pair(delaySteps: 3);
    final wires = <LoopbackWire>[wireA, wireB];
    final host = await _newGame(versus: Versus.turns, room: 'r', slot: 0);
    final guest = await _newGame(versus: Versus.turns, room: 'r', slot: 1);
    expect(host.waiting, isTrue);
    host.goOnline(wireA);
    guest.goOnline(wireB);
    final both = <RiverGame>[host, guest];
    await _run(both, 120, wires: wires, until: () => !guest.waiting);
    expect(host.waiting || guest.waiting, isFalse);
    expect(host.watching, isFalse);
    expect(guest.watching, isTrue);

    // The host flies at a target it has a clear run at, and shoots it.
    final target = host.targets.firstWhere(
      (t) =>
          t.plan.kind != TargetKind.jet &&
          t.plan.kind != TargetKind.depot &&
          t.plan.speed == 0.0 &&
          _clear(
            host.course,
            t.plan.x,
            t.plan.distance - 20.0,
            t.plan.distance - 2.0,
          ),
    );
    host.jet.position.setValues(target.plan.x, -(target.plan.distance - 20.0));
    host.phase = Phase.flying;
    host.input.press(RiverGame.fire);
    await _run(both, 90, wires: wires, until: () => target.down);
    expect(target.down, isTrue);
    await _run(both, 10, wires: wires);
    host.input.release(RiverGame.fire);

    // The guest's jet is where the host's was a few steps ago, and the
    // target is down there too, with the host's score.
    expect(
      guest.jet.position.distanceTo(host.jet.position),
      lessThan(RiverGame.fastSpeed * 6 / 60),
    );
    final mirrored = guest.targets.firstWhere(
      (t) =>
          t.plan.distance == target.plan.distance && t.plan.x == target.plan.x,
    );
    expect(mirrored.down, isTrue);
    expect(guest.turns!.runs[0].score, host.turns!.runs[0].score);
    expect(guest.turns!.runs[0].score, greaterThan(0));
    // Only the host's word counts: the guest's own shots decide nothing.
    expect(guest.run.score, host.run.score);

    // The host loses the jet: after the pause the guest's player flies, on
    // the guest's machine, and the host watches.
    await _crashLeft(host, also: <RiverGame>[guest], wires: wires);
    await _run(both, 10, wires: wires);
    expect(guest.phase, Phase.crashed, reason: 'the crash was replayed');
    await _run(both, _pause + 10, wires: wires);
    expect(guest.turns!.player, 1);
    expect(guest.watching, isFalse);
    expect(host.watching, isTrue);
    expect(host.turns!.player, 1);

    // And now the host sees the guest's flight.
    guest.input.press(GameAction.moveForward);
    await _run(both, 60, wires: wires);
    expect(guest.phase, Phase.flying);
    expect(host.phase, Phase.flying);
    expect(
      host.jet.position.distanceTo(guest.jet.position),
      lessThan(RiverGame.fastSpeed * 6 / 60),
    );
  });

  test('racing, each sees the other as a ghost where it is', () async {
    final (wireA, wireB) = LoopbackWire.pair(delaySteps: 2, lossRate: 0.2);
    final wires = <LoopbackWire>[wireA, wireB];
    final a = await _newGame(versus: Versus.race, room: 'r', slot: 0);
    final b = await _newGame(versus: Versus.race, room: 'r', slot: 1);
    a.goOnline(wireA);
    b.goOnline(wireB);
    final both = <RiverGame>[a, b];
    await _run(both, 120, wires: wires, until: () => !a.waiting && !b.waiting);
    expect(a.waiting || b.waiting, isFalse);

    a.input.press(GameAction.moveForward);
    await _run(both, 90, wires: wires);
    expect(a.phase, Phase.flying);
    expect(b.phase, Phase.ready);

    // B sees A ahead of it, where A is; A sees B still on the water.
    expect(b.rival!.distance, closeTo(a.distance, RiverGame.fastSpeed / 6));
    expect(b.rival!.phase, Phase.flying);
    expect(a.rival!.phase, Phase.ready);
    expect(a.rival!.distance, closeTo(b.distance, 0.01));
    expect(a.watching || b.watching, isFalse);
  });
}

/// Whether a jet at [x] flies from [from] to [to] without touching a bank.
bool _clear(Course course, double x, double from, double to) {
  for (var d = from; d <= to; d += 0.25) {
    if (!course.rowAt(d).isWater(x, halfWidth: RiverGame.wingReach + 0.2)) {
      return false;
    }
  }
  return true;
}
