/// A squad arriving somewhere, and the shape it takes when it does.
library;

import 'dart:math' as math;
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
  _obstacleTests();
  group('an order', () {
    test('takes a worker off the job it was running', () {
      // **The claim this phase rests on is that a bot and a player hold the
      // same handles**, and it was not true until this: a job writes an order
      // every step, so a squad order given to a harvester was overwritten
      // before the crowd moved and the click did nothing at all.
      //
      // Mutation: drop the `job = null` in `Squad.moveTo`. The worker turns
      // round at the next step and goes back to the seam, and the assertion
      // below — that it is walking the other way — fails.
      final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
      final base = sim.build(
        Building(centre: Vector3(20.0, 0.0, 20.0), width: 6.0, depth: 6.0),
      );
      final seam = sim.addResource(
        ResourceNode(at: Vector3(40.0, 0.0, 20.0), amount: 500.0),
      );
      final worker = sim.add(Unit(position: Vector3(26.0, 0.0, 20.0)));
      worker.job = HarvestJob(node: seam, dropOff: base);
      for (var i = 0; i < 120; i++) {
        sim.step(1.0 / 60.0);
      }
      expect(worker.position.x, greaterThan(27.0), reason: 'it never set off');

      Squad(<Unit>[worker]).moveTo(Vector3(20.0, 0.0, 60.0));
      for (var i = 0; i < 600; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(worker.job, isNull);
      expect(
        worker.position.z,
        greaterThan(45.0),
        reason: 'it went back to digging instead',
      );
    });
  });

  group('a block', () {
    test('is centred on the goal rather than growing away from it', () {
      // Mutation: drop the `- (columns - 1) / 2` centring. The squad then
      // starts at the goal and grows along +X and +Z, so an order given at the
      // edge of a cliff puts half of it over the edge.
      const formation = Formation.block(spacing: 2.0, width: 3);
      final slot = Vector3.zero();
      var sumX = 0.0;
      var sumZ = 0.0;
      for (var i = 0; i < 6; i++) {
        formation.slotFor(i, 6, slot);
        sumX += slot.x;
        sumZ += slot.z;
      }

      expect(sumX, closeTo(0.0, 1e-9));
      expect(sumZ, closeTo(0.0, 1e-9));
    });

    test('puts nobody in the same place', () {
      const formation = Formation.block(spacing: 1.5, width: 4);
      final seen = <String>{};
      final slot = Vector3.zero();
      for (var i = 0; i < 11; i++) {
        formation.slotFor(i, 11, slot);
        expect(seen.add('${slot.x},${slot.z}'), isTrue, reason: 'slot $i');
      }
    });

    test('is as wide as it is allowed and no wider', () {
      const formation = Formation.block(spacing: 1.0, width: 3);
      final slot = Vector3.zero();
      final xs = <double>{};
      for (var i = 0; i < 9; i++) {
        formation.slotFor(i, 9, slot);
        xs.add(slot.x);
      }

      expect(xs.length, 3, reason: 'three files, three ranks');
    });
  });

  group('a squad', () {
    test('stands in its slots when it arrives', () {
      // The claim a formation actually makes: not that the squad is *spread*
      // — separation spreads a huddle about as much — but that each member is
      // at its own place relative to the goal. Mutation: drop the
      // `toGoal < arriveWithin` branch and every unit stops at the goal cell
      // instead, so the distances below become the width of a shoved pile.
      final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
      final squad = Squad(<Unit>[
        for (var i = 0; i < 9; i++)
          sim.add(
            Unit(position: Vector3(6.0 + i % 3 * 1.2, 0.0, 6.0 + i ~/ 3 * 1.2)),
          ),
      ], formation: const Formation.block(spacing: 1.6, width: 3));

      const goal = 50.0;
      squad.moveTo(Vector3(goal, 0.0, goal));
      for (var i = 0; i < 1500; i++) {
        sim.step(1.0 / 60.0);
      }

      final slot = Vector3.zero();
      for (var i = 0; i < squad.units.length; i++) {
        squad.formation.slotFor(i, squad.units.length, slot);
        final unit = squad.units[i];
        final dx = unit.position.x - (goal + slot.x);
        final dz = unit.position.z - (goal + slot.z);
        expect(
          math.sqrt(dx * dx + dz * dz),
          lessThan(0.6),
          reason: 'unit $i is not standing in its slot',
        );
      }
    });

    test('is told to stand still all at once', () {
      final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
      final squad = Squad(<Unit>[
        for (var i = 0; i < 4; i++)
          sim.add(Unit(position: Vector3(10.0 + i * 1.0, 0.0, 10.0))),
      ]);

      squad.moveTo(Vector3(60.0, 0.0, 60.0));
      squad.hold();
      final before = <double>[for (final u in squad.units) u.position.x];

      for (var i = 0; i < 60; i++) {
        sim.step(1.0 / 60.0);
      }

      for (var i = 0; i < squad.units.length; i++) {
        expect(squad.units[i].position.x, closeTo(before[i], 1e-6));
      }
    });
  });
}

/// Ground with a wall across it and one way through.
///
/// The ridge is far too steep to stand on, so the bake refuses it and the field
/// has to route round; the gap is the only walkable column through.
Heightfield _ridge() {
  const int samples = 41;
  final heights = Float32List(samples * samples);
  for (var row = 0; row < samples; row++) {
    for (var column = 0; column < samples; column++) {
      final bool inWall = column == 20 && (row < 17 || row > 23);
      heights[row * samples + column] = inWall ? 30.0 : 0.0;
    }
  }
  return Heightfield(
    columns: samples,
    rows: samples,
    cellSize: 2.0,
    heights: heights,
  );
}

void _obstacleTests() {
  group('a march', () {
    test('goes round what it cannot climb', () {
      // **What the arrival radius is actually for.** A squad that steered at
      // its slot from the start would walk into the ridge and stay there; the
      // field is what knows about the gap. Mutation: take the slot branch
      // unconditionally — this fails and the flat-ground tests do not, which
      // is why it exists.
      final sim = StrategySimulation(random: GameRandom(1), ground: _ridge());
      final squad = Squad(<Unit>[
        for (var i = 0; i < 4; i++)
          sim.add(Unit(position: Vector3(10.0, 0.0, 10.0 + i * 1.2))),
      ], formation: const Formation.block(spacing: 1.6, width: 2));

      squad.moveTo(Vector3(60.0, 0.0, 12.0));
      for (var i = 0; i < 3000; i++) {
        sim.step(1.0 / 60.0);
      }

      for (final unit in squad.units) {
        expect(
          unit.position.x,
          greaterThan(42.0),
          reason: 'it is still on the near side of the ridge',
        );
      }
    });
  });
}
