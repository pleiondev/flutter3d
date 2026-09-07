/// What a side knows, what it can see, and what it does about the difference.
library;

import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Heightfield _flat({int samples = 41}) => Heightfield(
  columns: samples,
  rows: samples,
  cellSize: 2.0,
  heights: Float32List(samples * samples),
);

void main() {
  group('a lattice', () {
    test('starts knowing nothing', () {
      final fog = FogOfWar(ground: _flat());

      expect(fog.knows(0, 40.0, 40.0), isFalse);
      expect(fog.sees(0, 40.0, 40.0), isFalse);
      expect(fog.nearestUnexplored(0, 40.0, 40.0), greaterThanOrEqualTo(0));
    });

    test('uncovers a disc and not the square around it', () {
      // Mutation: drop the radius test in `reveal` and keep the bounds. The
      // corner of the box is a radius times root two away — half again as far
      // as the sight the caller asked for — and a crowd then walks around
      // inside a lit rectangle.
      final fog = FogOfWar(ground: _flat(), cellSize: 2.0);
      fog.reveal(0, 40.0, 40.0, 10.0);

      expect(fog.knows(0, 45.0, 40.0), isTrue, reason: 'five metres along X');
      expect(fog.knows(0, 40.0, 47.0), isTrue, reason: 'seven along Z');
      expect(
        fog.knows(0, 48.0, 48.0),
        isFalse,
        reason: 'the corner is eleven away, not ten',
      );
      expect(fog.knows(0, 60.0, 40.0), isFalse, reason: 'twenty away');
    });

    test('forgets what it can see and keeps what it has seen', () {
      // The whole reason there are two states. Mutation: have `forgetVisible`
      // clear both bits — the map then goes black behind a crowd that walks
      // away from it, and a side loses the seam it found a minute ago.
      final fog = FogOfWar(ground: _flat());
      fog.reveal(0, 40.0, 40.0, 10.0);
      expect(fog.sees(0, 40.0, 40.0), isTrue);

      fog.forgetVisible();

      expect(fog.sees(0, 40.0, 40.0), isFalse, reason: 'still watching it');
      expect(fog.knows(0, 40.0, 40.0), isTrue, reason: 'it forgot the place');
    });

    test('keeps one side out of the other side sight', () {
      // Mutation: drop the `side * cellCount` offset. One lattice then serves
      // both sides, and the bot plays the whole match with the player's map.
      final fog = FogOfWar(ground: _flat());
      fog.reveal(0, 40.0, 40.0, 10.0);

      expect(fog.knows(0, 40.0, 40.0), isTrue);
      expect(fog.knows(1, 40.0, 40.0), isFalse);

      // A third side gets a layer of its own as well: the lattice is as many
      // as it was asked for rather than always two, and the offset keeps them
      // apart however many there are.
      final three = FogOfWar(ground: _flat(), sides: 3);
      three.reveal(2, 40.0, 40.0, 10.0);

      expect(three.knows(2, 40.0, 40.0), isTrue);
      expect(three.knows(0, 40.0, 40.0), isFalse);
      expect(three.knows(1, 40.0, 40.0), isFalse);
    });

    test('answers false off the map rather than throwing', () {
      final fog = FogOfWar(ground: _flat());
      fog.reveal(0, 40.0, 40.0, 10.0);

      expect(fog.knows(0, -5.0, 40.0), isFalse);
      expect(fog.sees(0, 400.0, 400.0), isFalse);
      expect(fog.cellAt(-5.0, 40.0), -1);
    });
  });

  group('a simulation', () {
    test('lets a thing see where it stands the moment it exists', () {
      // Mutation: take the `reveal` out of `add` and `build` and leave the
      // refresh in the step. Everything staged before the first step is then
      // blind for a tenth of a second, and a policy asked for its opening
      // orders sends the whole crowd out to explore its own front garden.
      final sim = StrategySimulation(ground: _flat());
      sim.build(
        Building(centre: Vector3(20.0, 0.0, 20.0), width: 6.0, depth: 6.0),
      );

      expect(sim.fog.knows(0, 22.0, 22.0), isTrue);
      expect(sim.fog.knows(1, 22.0, 22.0), isFalse);

      // And the count the simulation was built with reaches the lattice.
      // Mutation: stop passing `sides` to the fog. The layer side two writes
      // into is then past the end of a two-side lattice, and staging a third
      // camp throws instead of revealing anything.
      final wide = StrategySimulation(ground: _flat(), sides: 3);
      wide.build(
        Building(
          centre: Vector3(20.0, 0.0, 20.0),
          width: 6.0,
          depth: 6.0,
          side: 2,
        ),
      );

      expect(wide.fog.sides, 3);
      expect(wide.fog.knows(2, 22.0, 22.0), isTrue);
      expect(wide.fog.knows(0, 22.0, 22.0), isFalse);
    });

    test('loses sight of ground its crowd has walked away from', () {
      final sim = StrategySimulation(ground: _flat());
      final scout = sim.add(
        Unit(position: Vector3(10.0, 0.0, 10.0), sight: 8.0),
      );

      for (var i = 0; i < 12; i++) {
        sim.step(1.0 / 60.0);
      }
      expect(sim.fog.sees(0, 12.0, 10.0), isTrue);

      scout.order = UnitOrder.moveTo(Vector3(70.0, 0.0, 10.0));
      for (var i = 0; i < 60 * 20; i++) {
        sim.step(1.0 / 60.0);
      }

      expect(sim.fog.sees(0, 12.0, 10.0), isFalse, reason: 'it is still there');
      expect(sim.fog.knows(0, 12.0, 10.0), isTrue, reason: 'it forgot home');
      expect(
        sim.fog.sees(0, 68.0, 10.0),
        isTrue,
        reason: 'it sees where it is',
      );
    });
  });

  group('a bot in the dark', () {
    /// A camp with its only seam well outside anybody's sight.
    ({Match match, Unit worker, ResourceNode seam}) camp() {
      final sim = StrategySimulation(ground: _flat(samples: 21));
      final base = sim.build(
        Building(
          centre: Vector3(8.0, 0.0, 8.0),
          width: 4.0,
          depth: 4.0,
          sight: 10.0,
        ),
      );
      final seam = sim.addResource(
        ResourceNode(at: Vector3(32.0, 0.0, 8.0), amount: 200.0),
      );
      final worker = sim.add(
        Unit(position: Vector3(12.0, 0.0, 8.0), sight: 7.0),
      );
      return (
        match: Match(
          simulation: sim,
          bots: <Bot>[Bot(side: 0, base: base)],
          goal: const MatchGoal(delivered: 10000.0),
        ),
        worker: worker,
        seam: seam,
      );
    }

    test('will not dig a seam nobody has found', () {
      // Mutation: drop the `fog.knows` test in `_nearestSeam`. The policy then
      // hands the worker a job for ore it has never laid eyes on, which is the
      // oldest cheat in the genre and invisible in the picture — the worker
      // simply walks the right way.
      final blind = camp();
      for (var i = 0; i < 120; i++) {
        blind.match.step(1.0 / 30.0);
      }

      expect(blind.worker.job, isNull, reason: 'it was given ore to dig');
      expect(blind.seam.amount, 200.0);
    });

    test('goes and looks, and digs what it finds', () {
      // Mutation: make `_scout` return without giving an order. The worker then
      // stands beside a map full of ore it is not allowed to have heard of, for
      // ever, and the side never earns anything.
      final blind = camp();
      var found = -1;
      for (var i = 0; i < 6000; i++) {
        blind.match.step(1.0 / 30.0);
        if (found < 0 && blind.worker.job != null) found = i;
      }

      expect(found, greaterThan(0), reason: 'it never found the seam');
      expect(
        blind.match.simulation.delivered[0],
        greaterThan(0.0),
        reason: 'it found the seam and did nothing with it',
      );
    });
  });
}
