/// The doors a map's world reaches the crowd through: the pace a walker
/// goes at, the shots a step fired, and what steps after the crowd.
///
///     flutter test test/step_hooks_test.dart
///
/// Each was something the strategy demo's world did from outside the step —
/// a wader's walk cut back after it was taken, a shot guessed from a cooldown
/// that grew, a world stepped by the screen's loop and nobody else's. Here
/// they are the simulation's, and so every loop that steps a match has them.
library;

import 'dart:typed_data';

import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 30.0;

StrategySimulation _world() => StrategySimulation(
  random: GameRandom(1),
  ground: Heightfield(
    columns: 41,
    rows: 41,
    cellSize: 2.0,
    heights: Float32List(41 * 41),
  ),
);

/// How far a soldier sent across open ground has walked after [steps].
double _walked({UnitPace? pace, int steps = 30}) {
  final sim = _world()..pace = pace;
  final unit = sim.add(
    StrategyUnit(position: Vector3(20.0, 0.0, 40.0), type: UnitType.worker),
  )..order = UnitOrder.moveTo(Vector3(60.0, 0.0, 40.0));
  for (var i = 0; i < steps; i++) {
    sim.step(_dt);
  }
  return unit.position.x - 20.0;
}

void main() {
  test('a walker goes at the pace the map allows it, in the step', () {
    final dry = _walked();
    final headings = <(double, double)>[];
    final wading = _walked(
      pace: (StrategyUnit unit, double x, double z) {
        headings.add((x, z));
        return 0.5;
      },
    );
    expect(dry, greaterThan(1.0), reason: 'a walker that went nowhere');
    // Half the pace, half the way — to within what a field's directions,
    // read in other cells along a shorter walk, wander by. Mutation: the
    // pace not asked in `_walk` (`speed` used as it is) — the wader goes as
    // far as the dry walker.
    expect(wading, closeTo(dry / 2.0, dry * 0.02));
    // Told which way it is heading — a unit vector, mostly east, the way the
    // field sends it — so a current along the way can be told from one
    // against it. Mutation: the step handed over scaled by the speed — it is
    // no longer of unit length; or its parts swapped — it heads north.
    final (x, z) = headings.first;
    expect(x * x + z * z, closeTo(1.0, 1e-6));
    expect(x, greaterThan(z.abs()));
  });

  test('a step says which shots it fired, and at whom', () {
    final sim = _world();
    final shooter = sim.add(
      StrategyUnit(position: Vector3(40.0, 0.0, 40.0), type: UnitType.soldier),
    );
    final mark = sim.add(
      StrategyUnit(
        position: Vector3(42.0, 0.0, 40.0),
        side: 1,
        type: UnitType.worker,
      ),
    );
    sim.step(_dt);
    // Mutation: the shot not written down in `_fight` — the list is empty
    // on the step the worker was hurt.
    expect(mark.health, lessThan(mark.type.health));
    expect(sim.shots, hasLength(1));
    expect(sim.shots.single.shooter, same(shooter));
    expect(sim.shots.single.mark, same(mark));
    // The next step is reloading and fires nothing, and says so. Mutation:
    // the list not emptied at the top of `step` — last step's shot is
    // reported again.
    sim.step(_dt);
    expect(sim.shots, isEmpty);
  });

  test('what hangs after the step runs once a step, after the crowd', () {
    final sim = _world();
    final unit = sim.add(
      StrategyUnit(position: Vector3(20.0, 0.0, 40.0), type: UnitType.worker),
    )..order = UnitOrder.moveTo(Vector3(60.0, 0.0, 40.0));
    final seen = <double>[];
    sim.afterStep.add((double dt) => seen.add(unit.position.x));
    sim
      ..step(_dt)
      ..step(_dt);
    // Mutation: `afterStep` run at the top of `step` — it sees the walker
    // where it stood before it walked, the start the first time.
    expect(seen, hasLength(2));
    expect(seen.first, greaterThan(20.0));
    expect(seen.last, greaterThan(seen.first));
  });
}
