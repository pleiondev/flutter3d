/// Which units a click and a drag mean.
library;

import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Heightfield _flat() => Heightfield(
  columns: 21,
  rows: 21,
  cellSize: 2.0,
  heights: Float32List(21 * 21),
);

/// A crowd standing in a row along +X, four metres apart.
StrategySimulation _row(int count) {
  final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
  for (var i = 0; i < count; i++) {
    sim.add(Unit(position: Vector3(4.0 + i * 4.0, 0.0, 10.0)));
  }
  return sim;
}

void main() {
  group('a click', () {
    test('finds the unit under it', () {
      final sim = _row(4);
      final picked = Selection(
        sim.units,
      ).unitAt(Vector3(8.0, 20.0, 10.0), Vector3(0.0, -1.0, 0.0));

      expect(picked, same(sim.units[1]), reason: 'the one at x = 8');
    });

    test('finds nothing where nobody stands', () {
      // Mutation: drop the `acrossSquared > radius * radius` test — every ray
      // then hits whichever unit is nearest along it, and clicking empty
      // ground selects somebody across the map.
      final sim = _row(4);
      final picked = Selection(
        sim.units,
      ).unitAt(Vector3(8.0, 20.0, 30.0), Vector3(0.0, -1.0, 0.0));

      expect(picked, isNull);
    });

    test('takes the nearest along the ray when two line up', () {
      // Mutation: compare centres rather than the entry point. Two units on
      // one line then resolve by which is nearer to the *centre*, and a unit
      // standing behind a wider one wins the click it should have lost.
      final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
      final near = sim.add(Unit(position: Vector3(10.0, 0.0, 10.0)));
      sim.add(
        Unit(
          position: Vector3(20.0, 0.0, 10.0),
          type: UnitType.worker.copyWith(radius: 1.5),
        ),
      );

      final picked = Selection(
        sim.units,
      ).unitAt(Vector3(0.0, 0.4, 10.0), Vector3(1.0, 0.0, 0.0));

      expect(picked, same(near));
    });

    test('ignores what is behind the pointer', () {
      // A ray points one way. Mutation: drop the `along < 0.0` test and a
      // click selects the crowd behind the camera.
      final sim = _row(3);
      final picked = Selection(
        sim.units,
      ).unitAt(Vector3(4.0, 0.4, 10.0), Vector3(-1.0, 0.0, 0.0));

      expect(picked, isNull, reason: 'everybody is the other way');
    });
  });

  group('a drag', () {
    test('takes everybody inside the rectangle', () {
      final sim = _row(6);
      final chosen = Selection(
        sim.units,
      ).unitsWithin(Vector3(6.0, 0.0, 6.0), Vector3(18.0, 0.0, 14.0));

      expect(chosen.length, 3, reason: 'x of 8, 12 and 16');
      expect(chosen.first.position.x, closeTo(8.0, 1e-9));
    });

    test('does not care which corner was dragged from', () {
      // Mutation: use the corners as given rather than sorting them. A drag
      // from bottom right then selects nothing, which reads as a broken mouse.
      final sim = _row(6);
      final forwards = Selection(
        sim.units,
      ).unitsWithin(Vector3(6.0, 0.0, 6.0), Vector3(18.0, 0.0, 14.0));
      final backwards = Selection(
        sim.units,
      ).unitsWithin(Vector3(18.0, 0.0, 14.0), Vector3(6.0, 0.0, 6.0));

      expect(backwards.length, forwards.length);
    });

    test('keeps the order the simulation steps in', () {
      // A selection that came back in a different order every time would give
      // orders in a different order, and two runs of one tape would part.
      final sim = _row(6);
      final chosen = Selection(
        sim.units,
      ).unitsWithin(Vector3(0.0, 0.0, 0.0), Vector3(40.0, 0.0, 20.0));

      expect(chosen, orderedEquals(sim.units));
    });
  });
}
