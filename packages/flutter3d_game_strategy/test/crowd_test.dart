/// The step a crowd takes: where an order sends it, what keeps units apart,
/// and what puts them on the ground.
library;

import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Ground sixty metres square, shaped by [height].
Heightfield _ground([double Function(int column, int row)? height]) {
  const int samples = 31;
  final heights = Float32List(samples * samples);
  if (height != null) {
    for (var row = 0; row < samples; row++) {
      for (var column = 0; column < samples; column++) {
        heights[row * samples + column] = height(column, row);
      }
    }
  }
  return Heightfield(
    columns: samples,
    rows: samples,
    cellSize: 2.0,
    heights: heights,
  );
}

void main() {
  group('an order', () {
    test('walks a unit towards where it points', () {
      final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
      final unit = sim.add(Unit(position: Vector3(4.0, 0.0, 4.0)));
      unit.order = UnitOrder.moveTo(Vector3(50.0, 0.0, 50.0));

      final before = unit.position.clone();
      for (var i = 0; i < 60; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(
        unit.position.distanceTo(Vector3(50.0, 0.0, 50.0)),
        lessThan(before.distanceTo(Vector3(50.0, 0.0, 50.0))),
        reason: 'a second of walking gets closer',
      );
    });

    test('leaves a unit under no order where it stands', () {
      // Mutation: drop the `continue` on a null goal — a held unit then
      // descends whichever field was built last and wanders off.
      final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
      final held = sim.add(Unit(position: Vector3(10.0, 0.0, 10.0)));
      final sent = sim.add(Unit(position: Vector3(20.0, 0.0, 20.0)))
        ..order = UnitOrder.moveTo(Vector3(50.0, 0.0, 50.0));

      final where = held.position.clone();
      for (var i = 0; i < 60; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(held.position.x, closeTo(where.x, 1e-6));
      expect(held.position.z, closeTo(where.z, 1e-6));
      expect(sent.position.x, greaterThan(20.0), reason: 'the other one went');
    });

    test('builds one field for a hundred units sent to one place', () {
      // Two hundred units, two goals inside one grid cell: the step must build
      // one field, not two hundred. Mutation: key the fields by the goal's
      // coordinates — the same walk then costs a field a unit, which is the
      // difference between half a millisecond and a hundred of them.
      final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
      for (var i = 0; i < 200; i++) {
        sim
            .add(Unit(position: Vector3(2.0 + i % 20 * 0.9, 0.0, 2.0)))
            .order = UnitOrder.moveTo(
          Vector3(50.0 + (i.isEven ? 0.1 : -0.1), 0.0, 50.0),
        );
      }

      // Nothing exposes the count, so this asks the only question a caller can:
      // that a step of two hundred is not two hundred times the work. A field
      // per unit takes seconds; one field takes milliseconds.
      final watch = Stopwatch()..start();
      sim.step(1.0 / 60.0);
      watch.stop();

      expect(
        watch.elapsedMilliseconds,
        lessThan(200),
        reason: 'one field for one destination cell',
      );
    });
  });

  group('a crowd', () {
    test('does not stand inside itself', () {
      // Mutation: drop the separation pass. Every unit descends the same field
      // to the same cell, so without shoving they converge to one point and
      // this fails by an order of magnitude.
      final sim = StrategySimulation(random: GameRandom(1), ground: _ground());
      for (var i = 0; i < 40; i++) {
        sim
            .add(
              Unit(
                position: Vector3(20.0 + i % 8 * 0.9, 0.0, 20.0 + i ~/ 8 * 0.9),
              ),
            )
            .order = UnitOrder.moveTo(
          Vector3(40.0, 0.0, 40.0),
        );
      }

      for (var i = 0; i < 240; i++) {
        sim.step(1.0 / 60.0);
      }

      for (var a = 0; a < sim.units.length; a++) {
        for (var b = a + 1; b < sim.units.length; b++) {
          final one = sim.units[a];
          final other = sim.units[b];
          final dx = one.position.x - other.position.x;
          final dz = one.position.z - other.position.z;
          expect(
            dx * dx + dz * dz,
            greaterThan(0.05),
            reason: 'units $a and $b are in the same place',
          );
        }
      }
    });

    test('steps the same way twice', () {
      // The genre's own norm: a strategy whose replay is not the match is a
      // strategy with no replay. Mutation: bucket the crowd by
      // `identityHashCode` — two runs then shove in a different order and the
      // positions drift apart in the third decimal.
      List<double> run() {
        final sim = StrategySimulation(
          random: GameRandom(1),
          ground: _ground(),
        );
        for (var i = 0; i < 50; i++) {
          sim
              .add(
                Unit(
                  position: Vector3(
                    10.0 + i % 10 * 0.8,
                    0.0,
                    10.0 + i ~/ 10 * 0.8,
                  ),
                ),
              )
              .order = UnitOrder.moveTo(
            Vector3(45.0, 0.0, 45.0),
          );
        }
        for (var i = 0; i < 120; i++) {
          sim.step(1.0 / 60.0);
        }
        return <double>[
          for (final unit in sim.units) ...<double>[
            unit.position.x,
            unit.position.y,
            unit.position.z,
          ],
        ];
      }

      expect(run(), run());
    });
  });

  group('the ground', () {
    test('is what a unit stands on, however the map rises', () {
      // Mutation: drop `_sit`. Units then keep the height they were added at
      // and walk through the hill rather than over it.
      final sim = StrategySimulation(
        random: GameRandom(1),
        ground: _ground((column, row) => column * 0.4),
      );
      final unit = sim.add(Unit(position: Vector3(4.0, 0.0, 30.0)));
      unit.order = UnitOrder.moveTo(Vector3(40.0, 0.0, 30.0));

      expect(unit.position.y, closeTo(sim.ground.heightAt(4.0, 30.0), 1e-6));

      for (var i = 0; i < 180; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(
        unit.position.y,
        closeTo(sim.ground.heightAt(unit.position.x, unit.position.z), 1e-6),
        reason: 'it is on the ground it is over',
      );
      expect(unit.position.y, greaterThan(1.0), reason: 'it climbed');
    });
  });
}
