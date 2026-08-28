/// Which way the runner is looking, and how it gets there.
///
///     flutter test test/facing_test.dart
///
/// **Written because an extraction found the hole.** The turn was three lines
/// inside `_face` — the shortest way round a circle, then a clamped step — and
/// when those two moved to `flutter3d_game` as shared arithmetic, replacing the
/// shared version with a plain subtraction left every test in this package
/// passing. A runner spinning the whole way round at the wrap point is
/// something a player sees immediately and no assertion here could.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// How far [to] is from [from], the short way round, **worked out here rather
/// than with `shortestAngle`**.
///
/// The second thing a mutation caught in this file: the first version measured
/// the runner's error with the very function it was trying to break, so a
/// broken one measured itself as fine. `atan2(sin, cos)` is the same answer by
/// a different road.
double _error(double from, double to) =>
    math.atan2(math.sin(to - from), math.cos(to - from));

({CollisionWorld world, Runner runner, InputState input}) _field() {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(120.0, 1.0, 120.0));
  return (
    world: world,
    runner: Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    ),
    input: InputState(),
  );
}

/// Walks in [heading] for one step and answers where the runner ended up
/// looking.
double _faceTowards(
  ({CollisionWorld world, Runner runner, InputState input}) it,
  Vector3 heading, {
  int steps = 1,
}) {
  for (var i = 0; i < steps; i++) {
    it.input.beginStep();
    it.input.setStickAxis(heading.x, heading.z);
    it.runner.step(_dt, it.input);
    it.input.endStep();
  }
  return it.runner.yaw;
}

void main() {
  test('a runner turns the short way round the wrap point', () {
    // **The first version of this test measured the wrong thing**, and a
    // mutation said so: it checked how *far* the runner turned in a step, and
    // a runner setting off the long way round turns exactly as far in the
    // first step as one setting off the right way. What matters is the
    // direction — after a step it must be *closer* to where it is going.
    //
    // Six radians apart is what forces the question: that is more than half a
    // turn, so the short way round is the other way, and a plain subtraction
    // sends it off the long way.
    final heading = Vector3(1.0, 0.0, 0.0);
    final settled = _faceTowards(_field(), heading, steps: 60);

    final it = _field();
    it.runner.yaw = settled - 6.0;
    final before = _error(it.runner.yaw, settled).abs();

    final after = _error(_faceTowards(it, heading), settled).abs();

    expect(
      after,
      lessThan(before),
      reason:
          'a step of turning left it further from where it is going: '
          '$before then $after',
    );
  });

  test('and gets there in the time the turn rate says', () {
    // The other half of the claim: it is a rate, not a snap.
    //
    // Written against where the runner settles rather than against an angle
    // worked out here, because which way `atan2(wish.x, wish.z)` points for a
    // given stick reading is the runner's own convention and not what this
    // test is about.
    final heading = Vector3(1.0, 0.0, 0.0);
    final settled = _faceTowards(_field(), heading, steps: 60);

    final afterOne = _faceTowards(_field(), heading);

    expect(
      _error(afterOne, settled).abs(),
      greaterThan(0.2),
      reason: 'the whole turn happened in one step',
    );
    expect(
      _error(0.0, afterOne).abs(),
      greaterThan(0.0),
      reason: 'it did not turn at all',
    );
  });
}
