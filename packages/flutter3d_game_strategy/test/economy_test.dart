/// Taking things off the map and turning them into units.
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

/// A base, a seam twenty metres from it, and one worker between them.
({StrategySimulation sim, Unit worker, ResourceNode seam, Building base})
_camp({double amount = 1000.0}) {
  final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
  final base = sim.build(
    Building(centre: Vector3(20.0, 0.0, 20.0), width: 6.0, depth: 6.0),
  );
  final seam = sim.addResource(
    ResourceNode(at: Vector3(40.0, 0.0, 20.0), amount: amount),
  );
  final worker = sim.add(Unit(position: Vector3(26.0, 0.0, 20.0)));
  worker.job = HarvestJob(node: seam, dropOff: base);
  return (sim: sim, worker: worker, seam: seam, base: base);
}

void main() {
  group('a worker', () {
    test('fills up at the seam and empties at the base', () {
      // Mutation: drop the `isFull` branch. The worker then stands at the seam
      // for ever with a full load and the stockpile never moves.
      final camp = _camp();

      for (var i = 0; i < 60 * 40; i++) {
        camp.sim.step(1.0 / 60.0);
      }

      expect(
        camp.sim.stock[0].amount,
        greaterThan(0.0),
        reason: 'nothing was ever delivered',
      );
      expect(
        camp.seam.amount,
        lessThan(1000.0),
        reason: 'nothing was ever dug',
      );
    });

    test('takes no more than the seam holds', () {
      // Mutation: let `take` return what was asked for. The stockpile then
      // grows past what the map ever had, which is the bug nobody notices
      // until a match is decided by it.
      final camp = _camp(amount: 12.0);

      for (var i = 0; i < 60 * 60; i++) {
        camp.sim.step(1.0 / 60.0);
      }

      expect(camp.seam.amount, 0.0);
      expect(camp.sim.stock[0].amount, closeTo(12.0, 1e-6));
    });

    test('stops when the seam runs dry rather than pacing an empty hole', () {
      final camp = _camp(amount: 8.0);

      for (var i = 0; i < 60 * 60; i++) {
        camp.sim.step(1.0 / 60.0);
      }
      final where = camp.worker.position.clone();
      for (var i = 0; i < 60 * 5; i++) {
        camp.sim.step(1.0 / 60.0);
      }

      expect(camp.worker.position.x, closeTo(where.x, 0.01));
      expect(camp.worker.position.z, closeTo(where.z, 0.01));
    });
  });

  group('a stockpile', () {
    test('is not spent twice by two buildings finishing together', () {
      // The reason `spend` is one call. Mutation: split it into a test and a
      // subtraction — both producers then see the same twenty-five and both
      // take it.
      final purse = Stockpile(25.0);

      expect(purse.spend(25.0), isTrue);
      expect(purse.spend(25.0), isFalse);
      expect(purse.amount, 0.0);
    });
  });

  group('a producer', () {
    test('makes a unit when its side can pay for one', () {
      final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
      final hall = sim.build(
        Building(centre: Vector3(20.0, 0.0, 20.0), width: 8.0, depth: 8.0),
      );
      sim.addProducer(Producer(building: hall, cost: 25.0, seconds: 2.0));
      sim.stock[0].amount = 60.0;

      for (var i = 0; i < 60 * 5; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(sim.units.length, 2, reason: 'sixty pays for two at twenty-five');
      expect(sim.stock[0].amount, closeTo(10.0, 1e-6));
    });

    test('makes nothing for a side that cannot pay', () {
      // Mutation: charge after finishing rather than before starting. A side
      // with nothing then gets a free unit every four seconds.
      final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
      final hall = sim.build(
        Building(centre: Vector3(20.0, 0.0, 20.0), width: 8.0, depth: 8.0),
      );
      sim.addProducer(Producer(building: hall));

      for (var i = 0; i < 60 * 20; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(sim.units, isEmpty);
    });

    test('spends its own side and not the other', () {
      // Mutation: read `stock[0]` instead of the building's side. One side then
      // pays for the other's army, which in a mirror match reads as the bot
      // cheating.
      final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
      final theirs = sim.build(
        Building(
          centre: Vector3(60.0, 0.0, 60.0),
          width: 8.0,
          depth: 8.0,
          side: 1,
        ),
      );
      sim.addProducer(Producer(building: theirs, cost: 25.0, seconds: 1.0));
      sim.stock[0].amount = 100.0;

      for (var i = 0; i < 60 * 5; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(sim.units, isEmpty, reason: 'side one had nothing to spend');
      expect(sim.stock[0].amount, closeTo(100.0, 1e-6));

      // A third side has a purse and a running total of its own, because both
      // lists are as long as the simulation was told rather than a literal
      // pair. Mutation: build them as two-element literals again — staging a
      // third camp then reads past the end of both.
      final wide = StrategySimulation(
        random: GameRandom(1),
        ground: _flat(),
        sides: 3,
      );
      final third = wide.build(
        Building(
          centre: Vector3(60.0, 0.0, 60.0),
          width: 8.0,
          depth: 8.0,
          side: 2,
        ),
      );
      wide.addProducer(Producer(building: third, cost: 25.0, seconds: 1.0));
      wide.stock[2].amount = 50.0;

      for (var i = 0; i < 60 * 3; i++) {
        wide.step(1.0 / 60.0);
      }

      expect(wide.delivered.length, 3);
      expect(wide.units, isNotEmpty, reason: 'side two could not pay its own');
      expect(wide.stock[0].amount, 0.0);
      expect(wide.stock[2].amount, closeTo(0.0, 1e-6));
    });

    test('puts a new unit outside the building that made it', () {
      final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
      final hall = sim.build(
        Building(centre: Vector3(30.0, 0.0, 30.0), width: 10.0, depth: 10.0),
      );
      sim.addProducer(Producer(building: hall, cost: 1.0, seconds: 0.5));
      sim.stock[0].amount = 5.0;

      for (var i = 0; i < 60; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(sim.units, isNotEmpty);
      for (final unit in sim.units) {
        expect(
          hall.covers(unit.position.x, unit.position.z),
          isFalse,
          reason: 'born inside the hall',
        );
      }
    });
  });
}
