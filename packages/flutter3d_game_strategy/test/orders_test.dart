/// The queue between the hand that gives an order and the step that obeys it.
///
///     flutter test test/orders_test.dart
///
/// **What this file is really about is the moment an order lands.** Until the
/// queue existed, a policy and a mouse wrote straight onto a unit, so an order
/// took effect at whatever instant the writer happened to run — inside a
/// pointer callback, in the middle of a frame, before or after the step that
/// read it depending on who called whom. Everything below asserts the one
/// property that replaced that: an order given between two steps is carried out
/// at the top of the next one, once, and is then gone.
///
/// `match_test.dart` measures what that buys — a match played back from a
/// document. This measures the mechanism underneath it, so that a failure names
/// the queue rather than the genre.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'match_test.dart' show flat, mirror, run;

const double _step = 1.0 / 30.0;

/// A hall, a seam a walk away, and a worker standing between them doing
/// nothing until somebody says so.
typedef Camp = ({
  StrategySimulation sim,
  Building hall,
  ResourceNode seam,
  Unit worker,
});

Camp _camp() {
  final sim = StrategySimulation(random: GameRandom(1), ground: flat());
  final hall = sim.build(
    Building(centre: Vector3(16.0, 0.0, 16.0), width: 6.0, depth: 6.0),
  );
  final seam = sim.addResource(
    ResourceNode(at: Vector3(36.0, 0.0, 16.0), amount: 100.0),
  );
  final worker = sim.add(Unit(position: Vector3(21.0, 0.0, 16.0)));
  return (sim: sim, hall: hall, seam: seam, worker: worker);
}

void main() {
  group('an order', () {
    test('waits for the step, and the step obeys it once', () {
      // **The whole contract in one test.** Given between two steps, it is not
      // acted on when it is given; it is acted on by the step that follows; and
      // it is not still waiting afterwards, so a click does not go on being
      // obeyed for the rest of the match.
      final it = _camp();
      it.sim.orders.moveTo(<Unit>[it.worker], Vector3(60.0, 0.0, 40.0));

      expect(
        it.worker.order.goal,
        isNull,
        reason: 'the order took effect before any step ran',
      );
      expect(it.sim.orders.waiting, hasLength(1));

      it.sim.step(_step);

      expect(it.worker.order.goal, isNotNull);
      expect(it.worker.order.goal!.x, closeTo(60.0, 1e-9));
      expect(it.sim.orders.waiting, isEmpty, reason: 'it is still queued');
    });

    test('to walk somewhere ends the job it interrupts', () {
      // The rule `Squad.moveTo` states, asserted through the queue that now
      // reaches it: a job writes an order of its own every step, so a move
      // given to a busy harvester that did not cancel the job is overwritten
      // before anybody takes a step — and the player who clicked sees a worker
      // carry on digging.
      final it = _camp();
      it.worker.job = HarvestJob(node: it.seam, dropOff: it.hall);
      it.sim.orders.moveTo(<Unit>[it.worker], Vector3(60.0, 0.0, 40.0));

      it.sim.step(_step);

      expect(it.worker.job, isNull);
      expect(it.worker.order.goal!.x, closeTo(60.0, 1e-9));
    });

    test('to work names its seam by where it sits in the map', () {
      // The other half of what a side asks for. The two indices are the ones
      // `HarvestJob.save` writes, so a job handed out by a tape and a job read
      // back from a snapshot cannot disagree about which seam is which.
      final it = _camp();
      it.sim.orders.assign(it.worker, node: it.seam, dropOff: it.hall);

      it.sim.step(_step);

      expect(it.worker.job, isNotNull);
      expect(it.worker.job!.node, same(it.seam));
      expect(it.worker.job!.dropOff, same(it.hall));
    });

    test('about a unit or a seam this map does not have is dropped', () {
      // A tape is a document and a match moves on: an order can name a worker
      // that has since gone, or a seam that belongs to a different map. A step
      // that threw there would turn a stale click into a crash, so the step
      // drops what it cannot find — and drops only that. The order beside it,
      // which names a unit that is here, is still obeyed.
      final it = _camp();
      it.sim.orders
        ..add(const AssignOrder(unit: 4096, node: 0, dropOff: 0))
        ..add(AssignOrder(unit: it.worker.entity.index, node: 7, dropOff: 0))
        ..add(MoveOrder(units: const <int>[4096], goal: Vector3.zero()))
        ..assign(it.worker, node: it.seam, dropOff: it.hall);

      it.sim.step(_step);

      expect(it.worker.job, isNotNull, reason: 'the good order went too');
      expect(it.worker.job!.node, same(it.seam));
      // Walking to its seam, which is its job's doing — and not to the origin,
      // which is where the move order naming nobody was pointing.
      expect(it.worker.order.goal!.x, closeTo(36.0, 1e-9));
    });

    test('given between a save and a step is in the save', () {
      // **The window is real and it belongs to the application.** A pointer
      // callback runs between steps, so a save taken between a click and the
      // frame that obeys it describes a world in which an order has already
      // been given. Mutation: drop `orders` from `StrategySimulation.save`. The
      // crowd comes back carrying on with what it was doing, and the click is
      // lost across a reload — which reads as an order the game ignored.
      final it = _camp();
      it.sim.orders.moveTo(<Unit>[it.worker], Vector3(60.0, 0.0, 40.0));

      final loaded = _camp()..sim.restore(it.sim.save());
      expect(loaded.sim.orders.waiting, hasLength(1));

      loaded.sim.step(_step);
      final Unit came = loaded.sim.units.single;

      expect(came.order.goal, isNotNull, reason: 'the order was not saved');
      expect(came.order.goal!.x, closeTo(60.0, 1e-9));
    });

    test('this build cannot carry out is dropped from a save, not refused', () {
      // **Where a save and a tape part company, deliberately.** A tape that
      // met an order it could not carry out would replay a different match, so
      // it throws; a save is the one document that must not refuse to load, and
      // an order it cannot carry out is one click inside a world it is
      // otherwise describing perfectly. So the click goes and the game loads.
      final it = _camp();
      final Snapshot saved = it.sim.save();
      final restored = Snapshot(<String, Object?>{
        ...saved.data,
        'orders': <Object?>[
          <String, Object?>{'kind': 'besiege', 'unit': 0},
          AssignOrder(
            unit: it.worker.entity.index,
            node: 0,
            dropOff: 0,
          ).toJson(),
        ],
      });

      final loaded = _camp()..sim.restore(restored);

      expect(loaded.sim.orders.waiting, hasLength(1));
      loaded.sim.step(_step);
      expect(loaded.sim.units.single.job, isNotNull);
    });
  });

  group('a policy', () {
    test('asks the queue like anybody else does', () {
      // **The claim `bot.dart` opens with, measured.** A bot is the player's
      // vocabulary driven by a policy, and a bot with a private door into the
      // crowd would be a mirror of nothing — and, more practically, a match
      // that cannot be written down, since what is recorded is what passes
      // through the queue. Mutation: have the policy write `unit.job` directly
      // again. Nothing about the match changes and the tape comes back empty.
      final match = mirror(seamTwo: 34.0);
      final recorder = OrderTapeRecorder(seed: 1);
      match.simulation.orders.recorder = recorder;

      run(match, 40);

      final Iterable<StrategyOrder> asked = recorder.tape.frames.expand(
        (List<StrategyOrder> it) => it,
      );

      expect(
        asked,
        isNotEmpty,
        reason: 'two policies played for forty steps and asked for nothing',
      );
      // Both kinds, because both sides open the same way and their seams are
      // not the same distance off: the near one is put to work, the far one is
      // sent to look for a seam nobody of that side has seen yet.
      expect(asked.whereType<AssignOrder>(), isNotEmpty);
      expect(asked.whereType<MoveOrder>(), isNotEmpty);
    });
  });
}
