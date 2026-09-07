/// Two policies on one map, and what a long run of them is worth as a test.
///
/// A match here is doing three jobs at once, which is why the phase was cheap:
/// it is the load (thousands of steps with a growing crowd), it is the
/// reproducibility check (two runs of the same start, compared to the bit), and
/// it is the fairness check (mirrored sides must not drift apart, because a
/// drift is a bias in the order the step walks its collections).
///
/// [flat], [mirror], [play], [run] and [digestOf] are public because
/// `snapshot_test.dart` and `orders_test.dart` import them. A save is only
/// worth anything if a match carries on after it, and "carries on" is measured
/// with the same arrangement this file compares two runs with — a second
/// likeness of it would be a second thing to keep right.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Heightfield flat() => Heightfield(
  columns: 41,
  rows: 41,
  cellSize: 2.0,
  heights: Float32List(41 * 41),
);

/// Two camps, one translated forty metres along Z from the other.
///
/// Everything a side has is the same shape as everything the other has, so any
/// difference in the result comes from a difference that was asked for — a seam
/// further away, a seam with less in it — and never from being side one.
/// [policies] stages the same map with nobody playing it, which is what a
/// replay is: the tape gives every order the two bots gave, so a second run
/// that still had them would come out right with an empty tape and prove
/// nothing.
Match mirror({
  double seamOne = 20.0,
  double seamTwo = 20.0,
  double amountOne = 500.0,
  double amountTwo = 500.0,
  double target = 300.0,
  int workers = 3,
  bool produce = true,
  bool policies = true,
}) {
  final sim = StrategySimulation(random: GameRandom(1), ground: flat());
  final bots = <Bot>[];
  for (var side = 0; side < 2; side++) {
    final double z = 16.0 + side * 40.0;
    final base = sim.build(
      Building(
        centre: Vector3(16.0, 0.0, z),
        width: 6.0,
        depth: 6.0,
        name: 'base',
        side: side,
      ),
    );
    sim.addResource(
      ResourceNode(
        at: Vector3(16.0 + (side == 0 ? seamOne : seamTwo), 0.0, z),
        amount: side == 0 ? amountOne : amountTwo,
      ),
    );
    for (var i = 0; i < workers; i++) {
      sim.add(Unit(position: Vector3(22.0, 0.0, z - 1.0 + i), side: side));
    }
    if (produce) {
      sim.addProducer(Producer(building: base));
    }
    if (policies) bots.add(Bot(side: side, base: base));
  }
  return Match(
    simulation: sim,
    bots: bots,
    goal: MatchGoal(delivered: target),
  );
}

/// Everything a step can have changed, flattened.
///
/// Compared with `==` rather than `closeTo`: the point of the comparison is
/// that two runs of one start are the *same* run, and a tolerance would let
/// through exactly the drift it is looking for.
List<double> digestOf(StrategySimulation sim) => <double>[
  sim.delivered[0],
  sim.delivered[1],
  sim.stock[0].amount,
  sim.stock[1].amount,
  sim.units.length.toDouble(),
  // What each side knows, counted. Fog is a rule of the simulation rather than
  // a coat on the picture, so a run that ends with the same crowd and a
  // different map is a run that did not replay — and the cheapest way to say
  // that is to make the map part of what is compared.
  for (var side = 0; side < 2; side++)
    for (final bool now in <bool>[true, false])
      _cellsKnown(sim, side, visible: now),
  for (final ResourceNode node in sim.resources) node.amount,
  for (final Unit unit in sim.units) ...<double>[
    unit.position.x,
    unit.position.y,
    unit.position.z,
  ],
];

/// How many cells a side can see now, or has ever seen.
double _cellsKnown(StrategySimulation sim, int side, {required bool visible}) {
  var count = 0;
  for (var cell = 0; cell < sim.fog.cellCount; cell++) {
    if (visible
        ? sim.fog.isVisible(side, cell)
        : sim.fog.isExplored(side, cell)) {
      count++;
    }
  }
  return count.toDouble();
}

/// Runs [match] to its end, or to [cap] steps, and says how many it took.
int play(Match match, {int cap = 6000}) {
  const double dt = 1.0 / 30.0;
  for (var i = 0; i < cap; i++) {
    if (match.standing.isOver) return i;
    match.step(dt);
  }
  return cap;
}

/// Runs [steps] of [match] whether or not it finishes.
void run(Match match, int steps) {
  for (var i = 0; i < steps; i++) {
    match.step(1.0 / 30.0);
  }
}

/// A world as the bytes it travels in.
///
/// **What the replay below compares, in place of the hand-made digest it used
/// to.** A list of the fields somebody thought of is a comparison that goes on
/// passing when a field arrives that nobody added to it, and this genre has
/// already grown three that way — the fog, the running totals, a producer's
/// progress. The save is the whole of what a step reads, it is kept right by
/// `snapshot_test.dart`, and jsonEncode of it is one string: a field added to
/// the world is a field in the comparison the same afternoon.
String bytesOf(Snapshot snapshot) => jsonEncode(snapshot.toJson());

void main() {
  group('a bot', () {
    test('puts an idle unit to work without being told twice', () {
      // Mutation: have the policy skip units that already hold a job even when
      // the seam under it is empty. Every worker then stops for good at the
      // hole it emptied, and the second seam on the map is never touched.
      final match = mirror(produce: false, workers: 1, amountOne: 40.0);
      play(match, cap: 900);

      expect(
        match.simulation.delivered[0],
        greaterThan(0.0),
        reason: 'nobody was ever sent to dig',
      );
    });

    test('leaves a loaded worker alone when its seam runs dry', () {
      // A worker walking home with ten in its hands and an empty hole behind
      // it: handing it a new job there is handing it a new pair of hands, and
      // the ten in the old ones is gone. Mutation: remove the `carried > 0`
      // guard — side nought then delivers ten of the twenty its seam held.
      //
      // **The other side's seam has to still be open**, and the first version
      // of this test forgot it: with both seams the same size they run dry
      // together, the policy finds nowhere to send anybody, and the guard it
      // was written for is never asked. Thirty seconds is measured — long
      // enough for both loads to come home, short enough that the worker has
      // not yet finished the long walk to the seam across the map.
      final match = mirror(
        produce: false,
        workers: 1,
        amountOne: 20.0,
        amountTwo: 400.0,
        target: 10000.0,
      );
      run(match, 900);

      expect(match.simulation.delivered[0], closeTo(20.0, 1e-9));
    });

    test('makes the units it is given work too', () {
      // Production hands the bot units it did not ask for. Mutation: have the
      // policy consider only units that already hold a job. The three it
      // started with keep working, so nothing looks broken — the crowd still
      // grows, the stockpile still moves — and the only symptom is that the
      // second half-minute earns no more than the first.
      //
      // Measured over two windows rather than by counting idlers, because the
      // count has a boundary: a unit produced inside the last step has not been
      // asked for orders yet, and failing a test for that would be failing it
      // for arriving on time.
      final match = mirror(
        target: 10000.0,
        amountOne: 5000.0,
        amountTwo: 5000.0,
      );

      run(match, 900);
      final double early = match.simulation.delivered[0];
      run(match, 900);
      final double late = match.simulation.delivered[0] - early;

      expect(match.simulation.units.length, greaterThan(3));
      expect(
        late,
        greaterThan(early * 1.2),
        reason: 'income stayed flat while the crowd grew',
      );
    });
  });

  group('a match', () {
    test('replays to the bit', () {
      // **What this used to measure and no longer does.** The second run was a
      // second mirror played by the same two policies — which measures that
      // running one program twice gives one answer twice, and says nothing
      // about a recording. There was nothing to record: an order was an
      // assignment a bot made from outside the step, so the only second run
      // available was a re-run.
      //
      // Now the first match is played **with a tape running**, and the second
      // is that tape played into a fresh map with nobody at the controls: the
      // replay has no bots at all, so every job handed out and every walk
      // ordered over four thousand steps comes off the document. Compared as
      // the bytes of the save, out through JSON and back the way a file
      // travels.
      //
      // Mutation: add `math.Random().nextDouble() * 1e-6` to the separation
      // push — a die rolled inside the step, which is exactly what the
      // structure rule about clocks and dice forbids and what this test is the
      // backstop for. It fails.
      //
      // **A die of 1e-9 does not fail it, and the reason is worth knowing.**
      // `Vector3` keeps its components in a `Float32List`, so at map
      // coordinates around twenty metres an ulp is about two microns: a
      // perturbation below that is not absorbed by the simulation, it is not
      // representable in the state at all. Measured — a starting position moved
      // by 1e-9 gave a final crowd identical to the last bit, and the same
      // start moved by 1e-6 put units two metres apart by the end. "To the bit"
      // means single precision here, and that is the precision the state has.
      final live = mirror(seamTwo: 34.0);
      final Snapshot start = live.simulation.save();
      final recorder = OrderTapeRecorder(seed: start.data.integer('random'));
      live.simulation.orders.recorder = recorder;

      final int steps = play(live);
      final String ending = bytesOf(live.simulation.save());

      expect(steps, lessThan(6000), reason: 'the match never finished');
      expect(
        ending,
        isNot(bytesOf(start)),
        reason: 'a match in which nothing happened would prove nothing',
      );

      // Through the document as it would travel: a string.
      final String sent = jsonEncode(
        MatchDemo(
          level: 'the mirror',
          start: start,
          tape: recorder.tape,
        ).toJson(),
      );
      final demo = MatchDemo.fromJson(jsonDecode(sent) as Map<String, Object?>);
      expect(demo.steps, steps, reason: 'the tape lost a step');
      expect(
        demo.tape.frames.where((List<StrategyOrder> it) => it.isNotEmpty),
        isNotEmpty,
        reason: 'nobody gave an order all match, so the tape carried nothing',
      );

      // The replay: the same map with nobody playing it, the demo's start
      // restored into it, and the tape in place of the two policies.
      final replay = mirror(seamTwo: 34.0, policies: false);
      replay.simulation.restore(demo.start);
      final playback = OrderTapePlayback(demo.tape);
      while (!playback.isFinished) {
        playback.applyTo(replay.simulation.orders);
        replay.step(1.0 / 30.0);
      }

      expect(bytesOf(replay.simulation.save()), ending);
      expect(replay.standing.winner, live.standing.winner);
    });

    test('is not replayed by a start a centimetre away', () {
      // The companion the test above needs: a comparison that never fails is a
      // comparison that proves nothing. One worker begins one centimetre along
      // and the two runs part company.
      final first = mirror(seamTwo: 34.0);
      final second = mirror(seamTwo: 34.0);
      second.simulation.units.first.position.x += 0.01;

      play(first);
      play(second);

      expect(digestOf(second.simulation), isNot(digestOf(first.simulation)));
    });

    test('is won by the side whose seam is nearer', () {
      final match = mirror(seamTwo: 34.0);
      final int steps = play(match);

      expect(steps, lessThan(6000));
      expect(match.standing.isOver, isTrue);
      expect(match.standing.winner, 0);
      expect(match.simulation.delivered[0], greaterThanOrEqualTo(300.0));

      // **And a third side is judged by the same pass.** Mutation: have the
      // judgement read `delivered[1]` against `delivered[0]` again. The side
      // in front is then invisible to it — both of the sides it looks at are
      // on nought — and a match somebody has won comes back drawn.
      final three = Match(
        simulation: StrategySimulation(
          random: GameRandom(1),
          ground: flat(),
          sides: 3,
        ),
        bots: const <Bot>[],
        goal: const MatchGoal(delivered: 100.0),
      );
      three.simulation.delivered[2] = 120.0;
      three.step(1.0 / 30.0);

      expect(three.standing.isOver, isTrue);
      expect(three.standing.winner, 2, reason: 'the largest total did not win');
    });

    test('is level between sides that are level', () {
      // **The strongest thing in this file.** Two sides running one policy from
      // one arrangement must come out equal; a gap would mean the step favours
      // whoever it walks first — in separation, in the field cache, in
      // production — and that is the bias a replay cannot see but a match can.
      final match = mirror(target: 10000.0);
      final int steps = play(match);

      expect(steps, lessThan(6000), reason: 'the map never ran out');
      expect(match.simulation.delivered[0], closeTo(500.0, 1e-6));
      expect(match.standing.winner, isNull);
      expect(match.standing.isOver, isTrue);
      expect(
        match.simulation.delivered[1],
        match.simulation.delivered[0],
        reason: 'one side out-earned its own mirror image',
      );
    });

    test('ends when the map runs out, below the line', () {
      // Mutation: judge only by the target. With a finishing line the ground
      // cannot pay for, the loop then runs for ever over an empty map — which
      // in a suite is not a red test but a hang.
      final match = mirror(
        produce: false,
        workers: 1,
        amountOne: 120.0,
        amountTwo: 60.0,
        target: 10000.0,
      );
      final int steps = play(match);

      expect(steps, lessThan(6000), reason: 'the match never ended');
      expect(match.standing.winner, 0);
      // **A hundred and eighty went into the ground and a hundred and eighty
      // came out of it**, which is the assertion worth making here — not what
      // each side got. A seam belongs to nobody: the side that empties its own
      // first walks across the map to whatever is left, so the poorer side
      // finishes with more than its own seam held and the richer with less.
      // That is the policy working, not leaking.
      expect(
        match.simulation.delivered[0] + match.simulation.delivered[1],
        closeTo(180.0, 1e-9),
      );
      expect(
        match.simulation.delivered[0],
        greaterThan(match.simulation.delivered[1]),
      );
    });

    test('is drawn when there was never anything to win', () {
      final sim = StrategySimulation(random: GameRandom(1), ground: flat());
      final match = Match(simulation: sim, bots: <Bot>[]);

      match.step(1.0 / 30.0);

      expect(match.standing.isOver, isTrue);
      expect(match.standing.winner, isNull);

      // Level between three, too, and the tie is not between the first two: a
      // pass that only remembered the best total without remembering that
      // something had drawn level with it would hand this to side one.
      final three = Match(
        simulation: StrategySimulation(
          random: GameRandom(1),
          ground: flat(),
          sides: 3,
        ),
        bots: const <Bot>[],
      );
      three.simulation.delivered
        ..[0] = 40.0
        ..[1] = 90.0
        ..[2] = 90.0;
      three.step(1.0 / 30.0);

      expect(three.standing.isOver, isTrue);
      expect(three.standing.winner, isNull, reason: 'a tie was given a winner');
    });

    test('stops changing once it is over', () {
      final match = mirror(seamTwo: 34.0);
      play(match);
      final List<double> ended = digestOf(match.simulation);

      for (var i = 0; i < 200; i++) {
        match.step(1.0 / 30.0);
      }

      expect(digestOf(match.simulation), ended);
    });
  });
}
