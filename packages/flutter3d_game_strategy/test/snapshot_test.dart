/// `StrategySimulation.save/restore` and `Match.save/restore`, which did not
/// exist.
///
///     flutter test test/snapshot_test.dart
///
/// **This genre could not be saved at all.** The words `save`, `restore`,
/// `Snapshot`, `GameRandom` and `EcsWorld` appeared nowhere in it, while the
/// other three each had a save and a generator. That is not a gap in a feature
/// list: a snapshot is a save file, a network packet and the input to a
/// determinism check all at once, so one missing mechanism was three, and the
/// order tape, the playthrough and the session that every other genre gets for
/// free were all waiting on it.
///
/// The rule the other three files state and this one keeps: **a field is only
/// under test at a moment when it is not zero.** Nothing here is snapshotted on
/// the first step; every state is driven into something interesting first, and
/// the run that carries the whole crowd is saved at a step that is deliberately
/// not on the fog's refresh beat.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart'
    show GameRandom, Snapshot, SnapshotFormatException;
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'match_test.dart' show digestOf, flat, mirror, run;

const double _step = 1.0 / 30.0;

/// A snapshot out to JSON and back, which is what a save file does to it.
///
/// Through [Snapshot.toJson] and [Snapshot.fromJson] rather than around them,
/// so every test below also asserts that the version survives the trip — and
/// through real JSON rather than the map straight back, because the map has
/// never met what a document does to it: a `List<double>` returns as a
/// `List<dynamic>`, and a `Vector3` keeps its components in a `Float32List`, so
/// a position written as a double and read back into one is single precision on
/// the way in and on the way out. "To the bit" means that precision here.
Snapshot roundTrip(Snapshot saved) => Snapshot.fromJson(
  jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>,
);

void _steps(StrategySimulation sim, int count) {
  for (var i = 0; i < count; i++) {
    sim.step(_step);
  }
}

/// One camp: a hall, a seam a walk away, a producer, and a worker digging.
///
/// Small on purpose. The whole-crowd claim is the match above; everything below
/// it puts one field into a state worth reading and reads exactly that field,
/// which is what makes a failure name the field rather than the genre.
typedef Camp = ({
  StrategySimulation sim,
  Building hall,
  ResourceNode seam,
  Producer maker,
  Unit worker,
});

Camp _camp({
  double amount = 100.0,
  double cost = 25.0,
  String name = 'hall',
  double seamAt = 30.0,
}) {
  final sim = StrategySimulation(random: GameRandom(1), ground: flat());
  final hall = sim.build(
    Building(
      centre: Vector3(16.0, 0.0, 16.0),
      width: 6.0,
      depth: 6.0,
      name: name,
    ),
  );
  final seam = sim.addResource(
    ResourceNode(at: Vector3(seamAt, 0.0, 16.0), amount: amount),
  );
  // With a standing order, because a producer nobody has asked for anything
  // makes nothing — see [Producer]. The camp is here to drive a producer's
  // progress into a state worth saving, and an idle one has no state.
  final maker = sim.addProducer(
    Producer(building: hall, cost: cost)..order(UnitType.worker, count: 20),
  );
  final worker = sim.add(Unit(position: Vector3(21.0, 0.0, 16.0)))
    ..job = HarvestJob(node: seam, dropOff: hall);
  return (sim: sim, hall: hall, seam: seam, maker: maker, worker: worker);
}

/// One unit crossing an empty map, which is the cheapest thing that keeps the
/// fog changing every time it is recomputed.
///
/// Quick on its feet — twenty metres a second, against the three a worker
/// walks — so that the ground it uncovers between two refreshes is wider than
/// a fog cell. A slower unit would move a tenth of a cell in that time and two
/// runs a beat apart would light the same cells anyway, which would make the
/// test below pass whatever it was measuring.
({StrategySimulation sim, Unit scout}) _walker() {
  final sim = StrategySimulation(random: GameRandom(1), ground: flat());
  final scout = sim.add(
    Unit(
      position: Vector3(4.0, 0.0, 4.0),
      type: UnitType.worker.copyWith(speed: 20.0),
    )..order = UnitOrder.moveTo(Vector3(76.0, 0.0, 76.0)),
  );
  return (sim: sim, scout: scout);
}

/// A soldier shooting a worker of the other side, which is the cheapest thing
/// that drives health, a reload and an attack order all at once.
///
/// The quarry is given far more health than its kind has so that it is still
/// standing at the moment every test below takes its save: a unit that has been
/// buried is a unit whose health is not in the document to be compared.
({StrategySimulation sim, Unit hunter, Unit quarry}) _skirmish() {
  final sim = StrategySimulation(random: GameRandom(1), ground: flat());
  final quarry = sim.add(
    Unit(
      position: Vector3(24.0, 0.0, 20.0),
      side: 1,
      type: UnitType.worker.copyWith(name: 'stubborn', health: 400.0),
    ),
  );
  final hunter = sim.add(
    Unit(position: Vector3(20.0, 0.0, 20.0), type: UnitType.soldier),
  );
  hunter.order = UnitOrder.attack(quarry);
  return (sim: sim, hunter: hunter, quarry: quarry);
}

Unit _sideOf(StrategySimulation sim, int side) =>
    sim.units.firstWhere((Unit it) => it.side == side);

/// What a side can see this instant, cell by cell.
List<bool> _visible(StrategySimulation sim) => <bool>[
  for (var cell = 0; cell < sim.fog.cellCount; cell++)
    sim.fog.isVisible(0, cell),
];

void main() {
  test('a match carries on from where it was saved', () {
    // **The whole claim, and the only one that needs the crowd.** Two matches
    // identical to the step: one played straight through, one saved in the
    // middle and restored into a map staged fresh from the same recipe. If
    // anything a step reads is missing from the save the two come apart, and
    // they come apart in a way no field-by-field assertion would have
    // predicted — a bot's thinking phase is in the format because of this test
    // and nothing else asks for it.
    //
    // **Saved at step 901, which is on no cycle in this simulation.** A bot
    // thinks every thirty-first step and 901 is two into that cycle, so a phase
    // restored at nought hands out its next job twenty-nine steps late — and by
    // then a worker is somewhere else and is given a different seam. A save
    // taken on the beat would have proved nothing and would have looked exactly
    // as green.
    //
    // The fog's own beat is not measured here and has its own test below: it
    // only moves *visible*, the policy reads *explored*, and explored only ever
    // grows — so a refresh six steps late changes what a side can see for six
    // steps and changes no decision at all.
    final straight = mirror(
      seamTwo: 34.0,
      target: 10000.0,
      amountOne: 5000.0,
      amountTwo: 5000.0,
    );
    final halved = mirror(
      seamTwo: 34.0,
      target: 10000.0,
      amountOne: 5000.0,
      amountTwo: 5000.0,
    );

    run(straight, 901);
    run(halved, 901);

    final saved = roundTrip(halved.save());

    run(straight, 900);

    final resumed = mirror(
      seamTwo: 34.0,
      target: 10000.0,
      amountOne: 5000.0,
      amountTwo: 5000.0,
    )..restore(saved);
    run(resumed, 900);

    // The crowd has to have grown, or the ECS is carrying nothing that a list
    // of six could not have carried and the test is about something else.
    expect(
      straight.simulation.units.length,
      greaterThan(6),
      reason: 'nobody was ever produced, so nothing new was ever restored',
    );
    expect(digestOf(resumed.simulation), digestOf(straight.simulation));
    expect(resumed.standing.isOver, straight.standing.isOver);
  });

  test('and the fog refreshes on the beat it was refreshing on', () {
    // The phase the run above would only report as a divergence, asked
    // directly. Fog is recomputed every seventh step and left alone in
    // between, so two runs whose counters are a step apart are two runs that
    // light different cells on different steps — and the policy that decides
    // where workers go reads exactly that.
    //
    // Mutation: drop `sinceFog` from `save()`. The two lattices agree for the
    // first few steps and part company at the sixth, which is the shape of
    // this defect and the reason a save taken on the beat would miss it.
    final it = _walker();
    _steps(it.sim, 41);

    final loaded = _walker()..sim.restore(roundTrip(it.sim.save()));

    for (var i = 0; i < 21; i++) {
      it.sim.step(_step);
      loaded.sim.step(_step);
      expect(_visible(loaded.sim), _visible(it.sim), reason: 'step $i');
    }
  });

  test('and a seam half dug comes back half dug', () {
    final it = _camp();
    _steps(it.sim, 200);
    expect(it.seam.amount, lessThan(100.0), reason: 'nobody dug anything');
    expect(it.seam.amount, greaterThan(0.0), reason: 'the seam ran out');

    final loaded = _camp()..sim.restore(roundTrip(it.sim.save()));

    expect(loaded.seam.amount, closeTo(it.seam.amount, 1e-9));
  });

  test('and a worker halfway home is still holding what it dug', () {
    // **What is in a worker's hands is not in anybody's pile yet**, and it is
    // the one quantity on this map that exists in neither of the two totals a
    // match is judged on. Restore it at nought and the ore is not spent, not
    // banked and not in the ground: it is gone, and a match that ends when the
    // map runs out ends earlier than it should have.
    final it = _camp();
    var steps = 0;
    while (steps < 600 && (it.worker.job?.carried ?? 0.0) <= 0.0) {
      it.sim.step(_step);
      steps++;
    }
    expect(
      it.worker.job!.carried,
      greaterThan(0.0),
      reason: 'the worker never picked anything up',
    );

    final loaded = _camp()..sim.restore(roundTrip(it.sim.save()));

    // Not the handle taken above: a restore builds the crowd rather than
    // filling it in, so the unit staged by `_camp` is not the unit that came
    // back. See `StrategySimulation.restore`.
    final Unit came = loaded.sim.units.single;
    expect(came.job, isNotNull, reason: 'it came back with no job at all');
    expect(came.job!.carried, closeTo(it.worker.job!.carried, 1e-9));
    expect(
      came.job!.node,
      same(loaded.seam),
      reason: 'the job points at a deposit from the wrong map',
    );
    expect(came.job!.dropOff, same(loaded.hall));
  });

  test('and a producer halfway through a unit does not pay twice', () {
    // Progress is what says the unit has been paid for. Restored at nought the
    // producer has not merely lost a second and a half: it starts again, and
    // charges the stockpile a second time for the same unit.
    final it = _camp();
    it.sim.stock[0].amount = 30.0;
    _steps(it.sim, 45);

    expect(it.maker.progress, greaterThan(0.0), reason: 'it never started');
    expect(it.maker.progress, lessThan(4.0), reason: 'it already finished');
    expect(it.sim.stock[0].amount, closeTo(5.0, 1e-9));

    final loaded = _camp()..sim.stock[0].amount = 30.0;
    loaded.sim.restore(roundTrip(it.sim.save()));

    expect(loaded.maker.progress, closeTo(it.maker.progress, 1e-9));
    expect(loaded.sim.stock[0].amount, closeTo(5.0, 1e-9));
  });

  test('and a side remembers ground it can no longer see', () {
    // **Both halves of the fog at once, which is why it is one test.** A cell
    // the scout walked over and has since left is explored and not visible, and
    // the two states have to come back apart: a lattice restored with
    // everything visible is a side that can see the whole map, and one restored
    // with nothing explored is a side that has to go and find its own seams
    // again.
    //
    // Mutation: drop `fog` from `save()`. The freshly staged map has its own
    // corner lit, so the first assertion fails on a cell that is visible when
    // it should only be remembered, and the third fails on ground nobody in
    // that map has been near.
    final it = _walker();
    _steps(it.sim, 900);
    expect(
      it.scout.position.x,
      greaterThan(40.0),
      reason: 'the scout never left the corner it started in',
    );

    var remembered = -1;
    for (var cell = 0; cell < it.sim.fog.cellCount; cell++) {
      if (!it.sim.fog.isExplored(0, cell)) continue;
      if (it.sim.fog.isVisible(0, cell)) continue;
      remembered = cell;
      break;
    }
    expect(remembered, greaterThanOrEqualTo(0), reason: 'it saw nothing twice');

    final loaded = _walker()..sim.restore(roundTrip(it.sim.save()));

    expect(
      loaded.sim.fog.isVisible(0, remembered),
      isFalse,
      reason: 'a side came back seeing ground it had walked away from',
    );
    expect(loaded.sim.fog.isExplored(0, remembered), isTrue);
    expect(
      loaded.sim.fog.knows(0, it.scout.position.x, it.scout.position.z),
      isTrue,
      reason: 'the far end of the walk was forgotten',
    );
  });

  test('and what a side has earned is not what it has left', () {
    // Two numbers, and only one of them can settle a match. A side that turns
    // everything it digs into units sits on an empty pile while out-earning
    // one that hoards, so a save carrying the pile and deriving the total
    // would hand the match to the wrong side on every load.
    final it = _camp(cost: 10.0);
    var steps = 0;
    while (steps < 900 && it.sim.delivered[0] <= 0.0) {
      it.sim.step(_step);
      steps++;
    }
    _steps(it.sim, 2);

    expect(it.sim.delivered[0], greaterThan(0.0), reason: 'nothing came home');
    expect(
      it.sim.stock[0].amount,
      closeTo(0.0, 1e-9),
      reason: 'the producer never spent it, so the two are not yet different',
    );

    final loaded = _camp(cost: 10.0)..sim.restore(roundTrip(it.sim.save()));

    expect(loaded.sim.delivered[0], closeTo(it.sim.delivered[0], 1e-9));
    expect(loaded.sim.stock[0].amount, closeTo(0.0, 1e-9));
  });

  test('and a unit restored under a hall is not left standing in it', () {
    // **The tail of `restore`, and the reason it is there.** Placing a building
    // takes its cells out of the navigation grid, and a flow field gives no
    // direction out of a cell it cannot reach — so a unit under a footprint
    // stops walking for the rest of the match, silently, with its orders
    // intact. `build` has always evicted whoever it buried; a restore is the
    // other door a position can be set through, and a document can say
    // anything.
    //
    // Mutation: drop `_settle()` from the end of `restore`. The unit comes back
    // inside the hall and stays there, order and all.
    final it = _camp();
    it.worker.position.setValues(16.0, 0.0, 16.0);
    expect(it.hall.covers(16.0, 16.0), isTrue, reason: 'not buried after all');

    final loaded = _camp()..sim.restore(roundTrip(it.sim.save()));
    final Unit came = loaded.sim.units.single;

    expect(
      loaded.hall.covers(came.position.x, came.position.z),
      isFalse,
      reason: 'it came back inside the hall',
    );

    // And what being outside buys: it can be told to go somewhere and it goes.
    came
      ..job = null
      ..order = UnitOrder.moveTo(Vector3(30.0, 0.0, 30.0));
    final double wasX = came.position.x;
    final double wasZ = came.position.z;
    _steps(loaded.sim, 30);

    expect(
      (came.position.x - wasX).abs() + (came.position.z - wasZ).abs(),
      greaterThan(0.5),
      reason: 'it holds an order it can never carry out',
    );
  });

  test('and the dice are where they were left', () {
    // **Nothing in this simulation rolls yet, which is exactly why this is
    // written now.** A generator whose state is not in the save is the one
    // thing in a world that cannot be restored, and the day something here
    // rolls — a fight, a scatter of spawn points, a tie broken between two
    // seams the same distance off — the save would go on loading and every
    // restored match would quietly diverge from the one it came from. Rolled
    // by hand here so the field is under test at a moment when it is not the
    // seed it started as.
    final it = _camp();
    for (var i = 0; i < 5; i++) {
      it.sim.random.nextDouble();
    }
    expect(
      it.sim.random.state,
      isNot(GameRandom(1).state),
      reason: 'the generator never moved, so a stale save would look right',
    );

    final loaded = _camp()..sim.restore(roundTrip(it.sim.save()));

    expect(loaded.sim.random.state, it.sim.random.state);
    expect(loaded.sim.random.nextDouble(), it.sim.random.nextDouble());
  });

  test('and what the save does not carry is what the map says', () {
    // The boundary `Snapshot` draws, in this genre's words: what is *in* the
    // ground is the match's, and *where* it is, is the map's. A hall's name and
    // footprint, a seam's place, the hillside under both — all come back from
    // whatever staged them, which is what lets a map be re-generated under a
    // save rather than frozen by one.
    final it = _camp();
    _steps(it.sim, 200);

    final loaded = _camp(name: 'depot', seamAt: 26.0)
      ..sim.restore(roundTrip(it.sim.save()));

    expect(loaded.hall.name, 'depot', reason: 'the save overwrote the map');
    expect(
      loaded.seam.at.x,
      closeTo(26.0, 1e-6),
      reason: 'the save moved a seam the map had put somewhere else',
    );
    expect(
      loaded.seam.amount,
      closeTo(it.seam.amount, 1e-9),
      reason: 'the seam forgot what had been dug out of it',
    );
  });

  test('and a unit that has been shot comes back as hurt as it was', () {
    // **Health is the one number the fight moves, and aliveness is derived
    // from it rather than kept beside it** — so this assertion is both halves
    // at once. Mutation: drop `health` from `Unit.save`. Every restored unit
    // comes back at full, which is not a rounding error but a battle undone:
    // the side that was one shot from winning has to fight the whole thing
    // again, and `match_test`'s replay parts company at the first exchange.
    final it = _skirmish();
    _steps(it.sim, 90);
    expect(
      it.quarry.health,
      lessThan(400.0),
      reason: 'nobody fired, so health was never off its default',
    );
    expect(it.quarry.health, greaterThan(0.0), reason: 'it is already buried');

    final loaded = _skirmish()..sim.restore(roundTrip(it.sim.save()));
    final Unit came = _sideOf(loaded.sim, 1);

    expect(came.health, closeTo(it.quarry.health, 1e-9));
    expect(came.isAlive, isTrue);
    expect(
      came.type,
      it.quarry.type,
      reason: 'a stubborn worker came back as an ordinary one',
    );
  });

  test('and a reload half spent is still half spent', () {
    // The same argument the fog's beat and a bot's thinking count make, in the
    // one place where being a fraction of a second early wins a fight. Mutation:
    // drop `cooldown` from `Unit.save`. The restored soldier fires the instant
    // it comes back, and the two runs are a shot apart within one step and
    // further apart every step after.
    final it = _skirmish();
    _steps(it.sim, 41);
    expect(
      it.hunter.cooldown,
      greaterThan(0.0),
      reason: 'it was ready to fire anyway, so nothing was under test',
    );

    final loaded = _skirmish()..sim.restore(roundTrip(it.sim.save()));
    final Unit shot = _sideOf(loaded.sim, 1);

    for (var i = 0; i < 40; i++) {
      it.sim.step(_step);
      loaded.sim.step(_step);
      expect(shot.health, closeTo(it.quarry.health, 1e-9), reason: 'step $i');
    }
  });

  test('and a hunter comes back after the same unit, not a stranger', () {
    // **An order that names a body cannot be read back by the body.** The crowd
    // a save describes is being built while each unit is read, so the quarry
    // may not exist yet; the index waits and `_restoreCrowd` hands the object
    // over once everybody is standing.
    //
    // Mutation: write the attack's *goal* as well and let it restore as a walk.
    // The hunter comes back marching to the patch of hillside the quarry was
    // standing on, arrives, and holds there while the thing it was sent to kill
    // walks away — a save that looks perfectly restored and has quietly
    // cancelled an order.
    final it = _skirmish();
    _steps(it.sim, 60);

    final loaded = _skirmish()..sim.restore(roundTrip(it.sim.save()));
    final Unit came = _sideOf(loaded.sim, 1);
    final Unit shooter = _sideOf(loaded.sim, 0);

    expect(shooter.order.target, same(came), reason: 'it is hunting a ghost');
    expect(
      shooter.order.goal,
      same(came.position),
      reason: 'its goal is a copy, so it will follow the quarry nowhere',
    );

    final double was = came.health;
    _steps(loaded.sim, 60);
    expect(came.health, lessThan(was), reason: 'it came back and stood still');
  });

  test('and a hall comes back making what it was making', () {
    // **The order book is the whole of what a side decided to do with its
    // pile.** Mutation: drop it from `Producer.save`. Both economies stop dead
    // on the load and stay stopped until each policy next happens to think —
    // which in a match saved between two thoughts is most of a second of
    // production that the run it was saved from did not lose.
    //
    // The camp it is restored into is deliberately making something else, so
    // that a book which failed to travel would leave the wrong answer standing
    // rather than the right one by luck.
    final it = _camp();
    it.sim.stock[0].amount = 300.0;
    _steps(it.sim, 400);
    expect(it.maker.isWanted, isTrue, reason: 'the book emptied itself');
    expect(it.maker.ordered, lessThan(20), reason: 'it never made anything');

    final loaded = _camp();
    loaded.maker.order(UnitType.soldier, count: 3);
    loaded.sim.restore(roundTrip(it.sim.save()));

    expect(loaded.maker.wanted, UnitType.worker);
    expect(loaded.maker.ordered, it.maker.ordered);
  });

  test('a saved match says which format it is in', () {
    // A bare `Map` would have loaded a document from a newer build field by
    // field and been subtly wrong instead of saying so. The version is put on
    // by `toJson` and taken off by `fromJson`, so nothing below it ever sees a
    // key it did not write.
    final it = mirror();
    run(it, 40);

    expect(it.save().toJson()['version'], Snapshot.formatVersion);
    expect(it.simulation.save().toJson()['version'], Snapshot.formatVersion);
    expect(
      () => Snapshot.fromJson(<String, Object?>{'version': 99}),
      throwsA(isA<SnapshotFormatException>()),
    );
  });
}
