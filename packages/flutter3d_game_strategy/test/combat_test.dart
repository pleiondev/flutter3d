/// Kinds of unit, the fight between them, the bodies it leaves, and the
/// finishing line it can reach.
///
///     flutter test test/combat_test.dart
///
/// **What this genre could not do, in one sentence: hurt anybody.** The words
/// health, attack, damage and kill appeared in this package only in doc
/// comments explaining why they were absent — `UnitOrder` had two constructors,
/// `Unit` had no health and no kind, the step had no phase for a fight, and
/// production stamped out one nameless default. So a match had one way to end,
/// a policy had one lever, and half the genre was a promise in prose.
///
/// The rule the rest of this suite keeps and this file keeps too: **a field is
/// only under test at a moment when it is not its default.** Nothing below
/// asserts on a unit at full health or a producer with an empty book.
library;

import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _step = 1.0 / 30.0;

Heightfield _flat({int samples = 41}) => Heightfield(
  columns: samples,
  rows: samples,
  cellSize: 2.0,
  heights: Float32List(samples * samples),
);

StrategySimulation _world({int samples = 41, int sides = 2}) =>
    StrategySimulation(
      random: GameRandom(1),
      ground: _flat(samples: samples),
      sides: sides,
    );

void _steps(StrategySimulation sim, int count) {
  for (var i = 0; i < count; i++) {
    sim.step(_step);
  }
}

/// A soldier that stands still: no reach, so it never picks a fight of its own
/// and only does what a test tells it to.
UnitType get _unarmedGuard =>
    UnitType.soldier.copyWith(damage: 0.0, range: 0.0);

void main() {
  group('a kind', () {
    test('is a row of numbers rather than a class of its own', () {
      // The claim the whole design rests on: a worker, a soldier and a tank
      // differ in what they measure, not in what code runs for them. If that
      // ever stops being true this assertion is the first thing to notice.
      expect(UnitType.worker.isArmed, isFalse, reason: 'a digger with a gun');
      expect(UnitType.soldier.isArmed, isTrue);
      expect(UnitType.tank.health, greaterThan(UnitType.soldier.health));
      expect(UnitType.tank.speed, lessThan(UnitType.soldier.speed));
      expect(
        UnitType.soldier.range,
        lessThan(UnitType.soldier.sight),
        reason: 'a side that cannot see trouble before it can answer it',
      );

      // Mutation: have `isArmed` ask only about damage. A kind with a gun and
      // no reach then joins the fight, every armed unit on the map searches
      // buckets for somebody it could never hit, and the pass that was supposed
      // to skip an economy stops skipping it.
      const UnitType blunted = UnitType(damage: 9.0);
      expect(blunted.isArmed, isFalse, reason: 'reach of nothing reaches');
    });

    test('gives a unit its width, its pace and its eyes', () {
      final unit = Unit(position: Vector3.zero(), type: UnitType.tank);

      expect(unit.radius, UnitType.tank.radius);
      expect(unit.speed, UnitType.tank.speed);
      expect(unit.sight, UnitType.tank.sight);
      expect(unit.health, UnitType.tank.health, reason: 'born half dead');
      expect(unit.isAlive, isTrue);
    });

    test('survives a document as the same kind', () {
      // Kinds travel as their own numbers rather than as a name, so a build
      // that has never heard of this one still restores it exactly. Mutation:
      // drop `type` from `Unit.save` — a restored army comes back as workers,
      // stops shooting, and the match it was winning is drawn.
      final made = UnitType.soldier.copyWith(name: 'sharpshooter', range: 11.0);

      expect(UnitType.fromJson(made.toJson()), made);
      expect(UnitType.fromJson(made.toJson()), isNot(UnitType.soldier));
    });
  });

  group('an attack order', () {
    test('is a target beside the goal, not an order of its own shape', () {
      // The whole of what `unit.dart` asked for: the step still only asks where
      // an order points, and where it points is the quarry's own position.
      final sim = _world();
      final quarry = sim.add(Unit(position: Vector3(40.0, 0.0, 10.0), side: 1));
      final hunter = sim.add(
        Unit(position: Vector3(8.0, 0.0, 10.0), type: UnitType.soldier),
      );
      hunter.order = UnitOrder.attack(quarry);

      expect(hunter.order.target, same(quarry));
      expect(
        hunter.order.goal,
        isNotNull,
        reason: 'the walk has nowhere to go',
      );
      expect(hunter.order.slot, isNull);

      final double was = hunter.position.x;
      _steps(sim, 60);

      expect(
        hunter.position.x,
        greaterThan(was + 2.0),
        reason: 'it never set off after the thing it was told to kill',
      );
    });

    test('follows a quarry that walks away', () {
      // **Why the goal is the target's own vector and not a copy of it.**
      // Mutation: clone the position in `UnitOrder.attack`. The hunter then
      // marches to the patch of ground the quarry was standing on when the
      // order was given and stands there while it walks off.
      //
      // Straight up Z rather than across the map, because a flow field
      // descends a lattice and a diagonal walk is a staircase — which would
      // make this measure the shape of the field rather than the following.
      final sim = _world(samples: 61);
      final quarry = sim.add(
        Unit(
          position: Vector3(30.0, 0.0, 30.0),
          side: 1,
          type: _unarmedGuard.copyWith(speed: 2.0),
        ),
      );
      final hunter = sim.add(
        Unit(
          position: Vector3(30.0, 0.0, 10.0),
          type: UnitType.soldier.copyWith(damage: 0.0, range: 0.0, speed: 3.0),
        ),
      );
      hunter.order = UnitOrder.attack(quarry);
      quarry.order = UnitOrder.moveTo(Vector3(30.0, 0.0, 110.0));

      _steps(sim, 600);

      expect(
        quarry.position.z,
        greaterThan(60.0),
        reason: 'the quarry never ran, so following it proves nothing',
      );
      expect(
        hunter.position.z,
        greaterThan(55.0),
        reason: 'it walked to where the quarry used to be and waited',
      );
    });

    test('goes through the queue and comes back off a tape', () {
      // Third kind, same addressing as the other two, same one entry in the
      // frame it was given on. Mutation: leave 'attack' out of `orderFromJson`
      // — reading the tape throws rather than replaying a different match,
      // which is what that reader is strict for.
      final sim = _world();
      final quarry = sim.add(Unit(position: Vector3(20.0, 0.0, 20.0), side: 1));
      final hunter = sim.add(
        Unit(position: Vector3(24.0, 0.0, 20.0), type: UnitType.soldier),
      );

      sim.orders.attackWith(<Unit>[hunter], quarry);
      final Map<String, Object?> written = sim.orders.waiting.single.toJson();
      sim.step(_step);

      expect(hunter.order.target, same(quarry));
      expect(written['kind'], 'attack');

      final StrategyOrder read = orderFromJson(written);
      expect(read, isA<AttackOrder>());
      expect((read as AttackOrder).target, quarry.entity.index);
    });

    test('takes a worker off its seam the way a move does', () {
      // A harvest loop rewrites the order every step, so a worker told to fight
      // and left on its job would carry on digging and look disobedient.
      final sim = _world();
      final hall = sim.build(
        Building(centre: Vector3(16.0, 0.0, 16.0), width: 6.0, depth: 6.0),
      );
      final seam = sim.addResource(
        ResourceNode(at: Vector3(26.0, 0.0, 16.0), amount: 100.0),
      );
      final quarry = sim.add(Unit(position: Vector3(30.0, 0.0, 30.0), side: 1));
      final digger = sim.add(Unit(position: Vector3(20.0, 0.0, 16.0)))
        ..job = HarvestJob(node: seam, dropOff: hall);

      sim.orders.attackWith(<Unit>[digger], quarry);
      sim.step(_step);

      expect(digger.job, isNull, reason: 'it is still on the payroll');
      expect(digger.order.target, same(quarry));
    });
  });

  group('a fight', () {
    /// Two units of different sides, [apart] metres from each other.
    ({StrategySimulation sim, Unit hunter, Unit quarry}) pair({
      double apart = 3.0,
      UnitType hunter = UnitType.soldier,
      UnitType quarry = UnitType.worker,
      int quarrySide = 1,
    }) {
      final sim = _world();
      final one = sim.add(
        Unit(position: Vector3(20.0, 0.0, 20.0), type: hunter),
      );
      final other = sim.add(
        Unit(
          position: Vector3(20.0 + apart, 0.0, 20.0),
          side: quarrySide,
          type: quarry,
        ),
      );
      return (sim: sim, hunter: one, quarry: other);
    }

    test('takes health off somebody in reach without being told to', () {
      // **The answer nobody orders.** Units that only fired when told would
      // make an unattended side an unattended target, and a policy issuing an
      // order per exchange would be a policy deciding sixty times a second.
      final it = pair();
      final double was = it.quarry.health;
      _steps(it.sim, 30);

      expect(it.quarry.health, lessThan(was), reason: 'nobody fired');
      expect(
        it.hunter.health,
        UnitType.soldier.health,
        reason: 'a digger shot back',
      );
    });

    test('leaves alone somebody out of reach', () {
      // Mutation: drop the range test in `_markFor` and keep the buckets. Every
      // unit in the nine cells around a shooter is then in reach, which at the
      // bucket width is three times the range the kind was measured with.
      final it = pair(apart: UnitType.soldier.range + 4.0);
      _steps(it.sim, 60);

      expect(it.quarry.health, UnitType.worker.health);
    });

    test('does not shoot its own side', () {
      final it = pair(quarrySide: 0);
      _steps(it.sim, 60);

      expect(it.quarry.health, UnitType.worker.health);
    });

    test('fires on its own reload and not every step', () {
      // Mutation: drop `cooldown` from `_fight` — a soldier then empties a
      // worker in a single step, at thirty times the rate its kind was
      // measured at, and a tank kills anything it can see instantly.
      final it = pair();
      _steps(it.sim, 30);

      final double taken = UnitType.worker.health - it.quarry.health;
      final double shots = taken / UnitType.soldier.damage;

      expect(shots, lessThanOrEqualTo(2.0), reason: 'it fired every step');
      expect(shots, greaterThanOrEqualTo(1.0), reason: 'it never fired');
    });

    test('keeps to its order rather than picking off passers-by', () {
      // A squad sent across the map that stops at the first worker it meets
      // never arrives. Mutation: have `_markFor` search regardless of the
      // order's target — the hunter shoots the bystander it is standing next to
      // and the unit it was actually sent for is never touched.
      final sim = _world();
      final bystander = sim.add(
        Unit(position: Vector3(22.0, 0.0, 20.0), side: 1),
      );
      final quarry = sim.add(Unit(position: Vector3(60.0, 0.0, 20.0), side: 1));
      final hunter = sim.add(
        Unit(position: Vector3(20.0, 0.0, 20.0), type: UnitType.soldier),
      );
      hunter.order = UnitOrder.attack(quarry);

      _steps(sim, 30);

      expect(
        bystander.health,
        UnitType.worker.health,
        reason: 'it stopped for the first thing it walked past',
      );
    });

    test('finds its neighbours through the buckets and not the whole crowd', () {
      // Not a timing assertion — a suite is the wrong place for one — but the
      // shape the timing depends on: every unit in reach is found however far
      // apart the crowd is spread, which is what says the nine cells around a
      // shooter are enough. A search that only looked in a shooter's own bucket
      // would miss the pair straddling a boundary; one that walked the crowd
      // would find them and cost the square of it.
      final sim = _world(samples: 61);
      final marks = <Unit>[
        for (var i = 0; i < 8; i++)
          sim.add(Unit(position: Vector3(10.0 + i * 12.0, 0.0, 30.0), side: 1)),
      ];
      for (var i = 0; i < 8; i++) {
        // Just under the soldier's reach, and deliberately not on the bucket
        // grid: half of these pairs sit either side of a boundary.
        sim.add(
          Unit(
            position: Vector3(10.0 + i * 12.0 + 5.0, 0.0, 30.0),
            type: UnitType.soldier,
          ),
        );
      }

      _steps(sim, 30);

      for (var i = 0; i < marks.length; i++) {
        expect(
          marks[i].health,
          lessThan(UnitType.worker.health),
          reason: 'the pair at ${10.0 + i * 12.0} never found each other',
        );
      }
    });
  });

  group('a death', () {
    ({StrategySimulation sim, List<Unit> crowd, Unit doomed}) line() {
      final sim = _world();
      final crowd = <Unit>[
        for (var i = 0; i < 5; i++)
          sim.add(Unit(position: Vector3(4.0 + i * 6.0, 0.0, 4.0))),
      ];
      final doomed = sim.add(
        Unit(
          position: Vector3(30.0, 0.0, 30.0),
          side: 1,
          type: UnitType.worker.copyWith(health: 12.0),
        ),
      );
      sim.add(
        Unit(
          position: Vector3(32.0, 0.0, 30.0),
          type: UnitType.soldier.copyWith(damage: 40.0),
        ),
      );
      return (sim: sim, crowd: crowd, doomed: doomed);
    }

    test('takes the fallen out and leaves the living in their order', () {
      // **The order the crowd is walked in is this simulation's whole claim to
      // replaying.** Mutation: remove each body where it falls instead of in
      // one pass — every index after it then names the wrong unit for the rest
      // of the step, so a shove lands on a stranger.
      final it = line();
      _steps(it.sim, 60);

      expect(it.sim.units.contains(it.doomed), isFalse, reason: 'still up');
      expect(it.doomed.isAlive, isFalse);
      expect(it.doomed.health, 0.0, reason: 'it is deader than dead');
      expect(
        it.sim.units.take(5).toList(),
        it.crowd,
        reason: 'the survivors came back in a different order',
      );
      expect(it.sim.entities.alive(it.doomed.entity), isFalse);
    });

    test('cuts the order that was pointing at it', () {
      // **A body out of the list is still reachable from whatever held it.**
      // Mutation: drop the target sweep at the end of `_bury`. The killer keeps
      // an order whose goal is a corpse's position vector, and walks to where
      // the corpse last stood for the rest of the match.
      final sim = _world();
      final doomed = sim.add(
        Unit(
          position: Vector3(24.0, 0.0, 20.0),
          side: 1,
          type: UnitType.worker.copyWith(health: 10.0),
        ),
      );
      final killer = sim.add(
        Unit(position: Vector3(20.0, 0.0, 20.0), type: UnitType.soldier),
      );
      killer.order = UnitOrder.attack(doomed);

      _steps(sim, 60);

      expect(sim.units, <Unit>[killer]);
      expect(killer.order.target, isNull, reason: 'it is still hunting a body');
      expect(killer.order.goal, isNull, reason: 'it is walking to a grave');
    });

    test('is not something a corpse can be brought back from by producing', () {
      // A hall goes on making units while a battle is lost around it, and each
      // one joins the crowd after the burial rather than being swept up by it.
      final sim = _world();
      final hall = sim.build(
        Building(centre: Vector3(30.0, 0.0, 8.0), width: 6.0, depth: 6.0),
      );
      sim.addProducer(
        Producer(building: hall, cost: 1.0, seconds: 0.4)
          ..order(UnitType.worker, count: 4),
      );
      sim.stock[0].amount = 40.0;
      final doomed = sim.add(
        Unit(
          position: Vector3(20.0, 0.0, 20.0),
          type: UnitType.worker.copyWith(health: 8.0),
        ),
      );
      sim.add(
        Unit(position: Vector3(23.0, 0.0, 20.0), side: 1, type: UnitType.tank),
      );

      _steps(sim, 120);

      expect(sim.units.contains(doomed), isFalse);
      expect(
        sim.units.where((Unit it) => it.side == 0).length,
        4,
        reason: 'the hall lost the units it made to the burial',
      );
    });
  });

  group('a military victory', () {
    test('goes to the side that is the only one left able to act', () {
      // Дмитрий's rule, in its own words: a side is beaten when it has neither
      // a unit nor anything that could make one. Mutation: ask only about
      // units. A side wiped off the field but holding a hall that can still
      // build then loses while it is spending its pile on the answer.
      final sim = _world();
      final theirs = sim.build(
        Building(
          centre: Vector3(30.0, 0.0, 8.0),
          width: 4.0,
          depth: 4.0,
          side: 1,
        ),
      );
      final ours = sim.build(
        Building(centre: Vector3(8.0, 0.0, 8.0), width: 4.0, depth: 4.0),
      );
      // Ore nobody is digging, so that the exhaustion ending stays out of the
      // way and what is measured here is the field alone.
      sim.addResource(ResourceNode(at: Vector3(64.0, 0.0, 64.0), amount: 80.0));
      sim.addProducer(Producer(building: ours));
      sim.add(
        Unit(
          position: Vector3(20.0, 0.0, 20.0),
          side: 1,
          type: UnitType.worker.copyWith(health: 10.0),
        ),
      );
      sim.add(Unit(position: Vector3(23.0, 0.0, 20.0), type: UnitType.soldier));
      final match = Match(
        simulation: sim,
        bots: const <Bot>[],
        goal: const MatchGoal(delivered: 10000.0),
      );

      // While side one still holds a hall that makes units it is still in it,
      // however badly it is losing on the field.
      final maker = sim.addProducer(Producer(building: theirs));
      for (var i = 0; i < 120; i++) {
        match.step(_step);
      }
      expect(sim.units.length, 1, reason: 'the worker survived');
      expect(match.standing.isOver, isFalse, reason: 'it can still build');

      sim.producers.remove(maker);
      match.step(_step);

      expect(match.standing.isOver, isTrue);
      expect(match.standing.winner, 0);
    });

    test('does not end a match on a map with only one camp on it', () {
      // **A side that never had anything is not a side that lost anything.** A
      // simulation carries as many sides as it was asked for whether or not
      // each was given a camp, so without this every one-camp test map would be
      // won on its first step by standing still. Mutation: count every side
      // rather than the contenders — `fog_test`'s lone scout wins instantly and
      // then the match stops stepping, so the fog stops being tested at all.
      final sim = _world();
      sim.build(
        Building(centre: Vector3(8.0, 0.0, 8.0), width: 4.0, depth: 4.0),
      );
      sim.addResource(ResourceNode(at: Vector3(30.0, 0.0, 8.0), amount: 90.0));
      sim.add(Unit(position: Vector3(12.0, 0.0, 8.0)));
      final match = Match(
        simulation: sim,
        bots: const <Bot>[],
        goal: const MatchGoal(delivered: 10000.0),
      );

      for (var i = 0; i < 60; i++) {
        match.step(_step);
      }

      expect(match.standing.isOver, isFalse);
    });

    test('is not called a draw while a battle is still being fought', () {
      // **The exhaustion ending was written when the totals were the only
      // thing a step could move.** With a fight on the map that is no longer
      // true, and the last ore usually runs out well before the last soldier
      // does. Mutation: judge on `_anythingLeft` alone, as it used to. A war
      // over worked-out ground is declared drawn on the step it starts, and
      // the whole military half becomes unreachable on any map that has been
      // dug out — which is most of them, late on.
      final sim = _world();
      sim.build(
        Building(centre: Vector3(8.0, 0.0, 8.0), width: 4.0, depth: 4.0),
      );
      final doomed = sim.add(
        Unit(
          position: Vector3(20.0, 0.0, 20.0),
          side: 1,
          type: UnitType.worker.copyWith(health: 30.0),
        ),
      );
      sim.add(Unit(position: Vector3(23.0, 0.0, 20.0), type: UnitType.soldier));
      final match = Match(
        simulation: sim,
        bots: const <Bot>[],
        goal: const MatchGoal(delivered: 10000.0),
      );

      match.step(_step);
      expect(
        match.standing.isOver,
        isFalse,
        reason: 'the fight was over before a shot landed',
      );
      expect(doomed.health, lessThan(30.0), reason: 'nobody fired');

      for (var i = 0; i < 200; i++) {
        match.step(_step);
      }

      expect(match.standing.winner, 0, reason: 'the war decided nothing');
    });

    test('does not take away a win the economy had already settled', () {
      // The order the three endings are asked in. A side that has brought home
      // what the match was set at has won it, and losing its last worker in the
      // same step should not undo that. Mutation: judge the field first — the
      // match comes back won by the side that was behind.
      final sim = _world();
      sim.build(
        Building(centre: Vector3(8.0, 0.0, 8.0), width: 4.0, depth: 4.0),
      );
      sim.build(
        Building(
          centre: Vector3(30.0, 0.0, 8.0),
          width: 4.0,
          depth: 4.0,
          side: 1,
        ),
      );
      final doomed = sim.add(
        Unit(
          position: Vector3(20.0, 0.0, 20.0),
          type: UnitType.worker.copyWith(health: 6.0),
        ),
      );
      sim.add(
        Unit(position: Vector3(22.0, 0.0, 20.0), side: 1, type: UnitType.tank),
      );
      sim.add(Unit(position: Vector3(28.0, 0.0, 8.0), side: 1));
      final match = Match(
        simulation: sim,
        bots: const <Bot>[],
        goal: const MatchGoal(delivered: 100.0),
      );
      sim.delivered[0] = 140.0;

      match.step(_step);

      expect(doomed.isAlive, isFalse, reason: 'it was meant to be killed');
      expect(match.standing.winner, 0);
    });
  });

  group('a bot with an army', () {
    /// One camp with a hall that makes units, a pile to make them from, and a
    /// seam nobody is asked to dig.
    ///
    /// The seam is there so that the match does not end on its first step: with
    /// nothing in the ground, nothing in anybody's hands and nobody armed yet,
    /// the exhaustion rule would judge a world in which the policy has not had
    /// a single thought. It is placed away from the camp and every plan below
    /// that uses it asks for no diggers, so nothing ever takes any of it.
    ({Match match, StrategySimulation sim, Bot bot}) camp(ArmyPlan plan) {
      final sim = _world();
      final base = sim.build(
        Building(
          centre: Vector3(20.0, 0.0, 10.0),
          width: 4.0,
          depth: 4.0,
          sight: 12.0,
        ),
      );
      sim.addResource(ResourceNode(at: Vector3(64.0, 0.0, 64.0), amount: 80.0));
      sim.addProducer(Producer(building: base, cost: 10.0, seconds: 1.0));
      sim.stock[0].amount = 200.0;
      final bot = Bot(side: 0, base: base, plan: plan);
      return (
        match: Match(
          simulation: sim,
          bots: <Bot>[bot],
          goal: const MatchGoal(delivered: 10000.0),
        ),
        sim: sim,
        bot: bot,
      );
    }

    test('will not attack somebody nobody has seen', () {
      // **The honesty test, and the whole reason it is written the same shape
      // as `fog_test`'s seam.** Mutation: drop the `fog.sees` test in
      // `_nearestFoe`. The policy then hands its soldiers a target on the far
      // side of a dark map — the oldest cheat in the genre and invisible in the
      // picture, because the soldiers simply always turn the right way.
      //
      // Sight cut right down so that neither camp can see the other, and the
      // soldiers made blind rather than merely short-sighted so that the walk
      // they take while looking cannot uncover the answer inside the window.
      const UnitType blind = UnitType(
        name: 'blind soldier',
        sight: 0.5,
        health: 70.0,
        damage: 9.0,
        range: 6.0,
      );
      final sim = _world(samples: 61);
      final base = sim.build(
        Building(
          centre: Vector3(10.0, 0.0, 10.0),
          width: 4.0,
          depth: 4.0,
          sight: 6.0,
        ),
      );
      final mine = sim.add(
        Unit(position: Vector3(14.0, 0.0, 10.0), type: blind),
      );
      final theirs = sim.add(
        Unit(position: Vector3(100.0, 0.0, 100.0), side: 1),
      );
      final match = Match(
        simulation: sim,
        bots: <Bot>[
          Bot(
            side: 0,
            base: base,
            plan: const ArmyPlan(workers: 0, fighters: 1),
          ),
        ],
        goal: const MatchGoal(delivered: 10000.0),
      );

      for (var i = 0; i < 120; i++) {
        match.step(_step);
      }

      expect(
        sim.fog.sees(0, theirs.position.x, theirs.position.z),
        isFalse,
        reason: 'the map lit up, so the fog was never asked anything',
      );
      expect(
        mine.order.target,
        isNull,
        reason: 'it was given a target it has never laid eyes on',
      );
      expect(theirs.health, UnitType.worker.health);
    });

    test('attacks what it can see', () {
      // The companion the test above needs: a policy that never attacks
      // anything would pass it for the wrong reason.
      final sim = _world();
      final base = sim.build(
        Building(centre: Vector3(10.0, 0.0, 10.0), width: 4.0, depth: 4.0),
      );
      final mine = sim.add(
        Unit(position: Vector3(14.0, 0.0, 10.0), type: UnitType.soldier),
      );
      final theirs = sim.add(Unit(position: Vector3(22.0, 0.0, 10.0), side: 1));
      final match = Match(
        simulation: sim,
        bots: <Bot>[
          Bot(
            side: 0,
            base: base,
            plan: const ArmyPlan(workers: 0, fighters: 1),
          ),
        ],
        goal: const MatchGoal(delivered: 10000.0),
      );

      for (var i = 0; i < 60; i++) {
        match.step(_step);
      }

      expect(sim.fog.sees(0, theirs.position.x, theirs.position.z), isTrue);
      expect(mine.order.target, same(theirs));
      expect(theirs.health, lessThan(UnitType.worker.health));
    });

    test('spends its pile on the kinds its plan asks for', () {
      // The second lever, in its first two positions. Mutation: have `_make`
      // ask for a worker whatever the plan says — the army never appears and
      // the military half of the game is unreachable through a policy.
      final it = camp(const ArmyPlan(workers: 2, fighters: 3));
      for (var i = 0; i < 900; i++) {
        it.match.step(_step);
      }

      final List<Unit> mine = it.sim.units;
      expect(
        mine.where((Unit u) => !u.type.isArmed).length,
        2,
        reason: 'it kept making diggers past its plan',
      );
      expect(
        mine.where((Unit u) => u.type.isArmed).length,
        3,
        reason: 'it never raised the army it planned',
      );
    });

    test('saves up once it has what it planned for', () {
      // **The third position of the lever, and the one that could not exist
      // before.** Production used to spend a pile the moment it could, so
      // "keep it" was not a state this game had. Mutation: have `_make` order
      // something whatever the count says — the pile drains into units nobody
      // planned, and a policy's choice collapses back to one option.
      //
      // No diggers in the plan, so nothing comes *in* either and the pile can
      // only move one way: what it is at the end is what was not spent.
      final it = camp(const ArmyPlan(workers: 0, fighters: 2));
      for (var i = 0; i < 300; i++) {
        it.match.step(_step);
      }
      final double settled = it.sim.stock[0].amount;

      expect(it.sim.units.length, 2, reason: 'the plan was two');
      expect(settled, greaterThan(0.0), reason: 'it spent everything anyway');

      for (var i = 0; i < 600; i++) {
        it.match.step(_step);
      }

      expect(it.sim.units.length, 2, reason: 'it started building again');
      expect(
        it.sim.stock[0].amount,
        closeTo(settled, 1e-9),
        reason: 'the pile went on draining after the plan was met',
      );
    });

    test('plays a match out to a military end', () {
      // **The whole half of the game at once, and nothing ordered by hand.** A
      // policy raises an army out of its own pile, finds an enemy it has never
      // seen by going and looking, marches on it, and the match ends because
      // there is nobody left on the other side.
      //
      // The far camp has a hall and no producer, which is what makes the
      // ending reachable at all: buildings cannot be knocked down here, so a
      // side that can still make units can never be finished off. That is
      // Дмитрий's rule read back — a side is beaten when it has neither units
      // nor anything that makes them.
      final sim = _world(samples: 51);
      final mine = sim.build(
        Building(
          centre: Vector3(20.0, 0.0, 10.0),
          width: 4.0,
          depth: 4.0,
          sight: 12.0,
        ),
      );
      final theirs = sim.build(
        Building(
          centre: Vector3(20.0, 0.0, 60.0),
          width: 4.0,
          depth: 4.0,
          side: 1,
          sight: 12.0,
        ),
      );
      sim.addProducer(Producer(building: mine, cost: 10.0, seconds: 1.0));
      // Ore in a far corner, so the exhaustion ending does not judge a match in
      // which the policy has not yet had a thought. No plan below asks for a
      // digger, so none of it is ever taken.
      sim.addResource(ResourceNode(at: Vector3(90.0, 0.0, 90.0), amount: 80.0));
      sim.stock[0].amount = 120.0;
      for (var i = 0; i < 2; i++) {
        sim.add(
          Unit(
            position: Vector3(18.0 + i * 2.0, 0.0, 64.0),
            side: 1,
            type: UnitType.soldier,
          ),
        );
      }
      final match = Match(
        simulation: sim,
        bots: <Bot>[
          Bot(
            side: 0,
            base: mine,
            plan: const ArmyPlan(workers: 0, fighters: 5),
          ),
          Bot(
            side: 1,
            base: theirs,
            plan: const ArmyPlan(workers: 0, fighters: 5),
          ),
        ],
        goal: const MatchGoal(delivered: 10000.0),
      );

      var steps = 0;
      while (steps < 6000 && !match.standing.isOver) {
        match.step(_step);
        steps++;
      }

      expect(steps, lessThan(6000), reason: 'the war never finished');
      expect(match.standing.winner, 0);
      expect(
        sim.units.where((Unit u) => u.side == 1),
        isEmpty,
        reason: 'somebody was still standing on the losing side',
      );
    });
  });
}
