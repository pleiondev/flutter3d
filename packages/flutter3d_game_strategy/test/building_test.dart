/// What a building takes away, and what the crowd does about it.
library;

import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Heightfield _flat() => Heightfield(
  columns: 41,
  rows: 41,
  cellSize: 2.0,
  heights: Float32List(41 * 41),
);

void main() {
  group('a footprint', () {
    test('covers what is under it and nothing beside it', () {
      final building = Building(
        centre: Vector3(20.0, 0.0, 20.0),
        width: 8.0,
        depth: 4.0,
      );

      expect(building.covers(20.0, 20.0), isTrue);
      expect(building.covers(23.9, 21.9), isTrue, reason: 'inside the corner');
      expect(building.covers(24.1, 20.0), isFalse, reason: 'past the width');
      expect(building.covers(20.0, 22.1), isFalse, reason: 'past the depth');
    });
  });

  group('placing one', () {
    test('takes its ground out of the grid', () {
      // Mutation: drop the `blocked` argument in `_bake`. The cells under a
      // building stay walkable and the crowd walks through the walls.
      final sim = StrategySimulation(ground: _flat());
      final under = sim.grid.cellAtPoint(40.0, 40.0);
      expect(sim.grid.isWalkable(under), isTrue, reason: 'open ground first');

      sim.build(
        Building(centre: Vector3(40.0, 0.0, 40.0), width: 10.0, depth: 10.0),
      );

      expect(sim.grid.isWalkable(sim.grid.cellAtPoint(40.0, 40.0)), isFalse);
      expect(
        sim.grid.isWalkable(sim.grid.cellAtPoint(60.0, 40.0)),
        isTrue,
        reason: 'the ground beside it is untouched',
      );
    });

    test('sits the building on the ground it was placed over', () {
      final sim = StrategySimulation(
        ground: Heightfield(
          columns: 41,
          rows: 41,
          cellSize: 2.0,
          heights: Float32List.fromList(<double>[
            for (var row = 0; row < 41; row++)
              for (var column = 0; column < 41; column++) column * 0.25,
          ]),
        ),
      );

      final placed = sim.build(
        Building(centre: Vector3(40.0, 99.0, 40.0), width: 4.0, depth: 4.0),
      );

      expect(placed.centre.y, closeTo(sim.ground.heightAt(40.0, 40.0), 1e-6));
    });

    test('makes the crowd walk round it', () {
      // The whole point of taking the ground away. Mutation: place the
      // building *after* the walk starts and never re-bake — the units then
      // march through the middle of it.
      final sim = StrategySimulation(ground: _flat());
      sim.build(
        Building(centre: Vector3(40.0, 0.0, 40.0), width: 24.0, depth: 8.0),
      );

      final unit = sim.add(Unit(position: Vector3(40.0, 0.0, 20.0)));
      unit.order = UnitOrder.moveTo(Vector3(40.0, 0.0, 60.0));

      var wentThrough = false;
      for (var i = 0; i < 2400; i++) {
        sim.step(1.0 / 60.0);
        if (sim.buildings.first.covers(unit.position.x, unit.position.z)) {
          wentThrough = true;
          break;
        }
      }

      expect(wentThrough, isFalse, reason: 'it walked into the building');
      expect(
        unit.position.z,
        greaterThan(50.0),
        reason: 'and it still got past',
      );
    });
  });
}
