/// The tape and the document that carries it.
///
///     flutter test test/tape_test.dart
///
/// `match_test.dart` plays a whole match through this and compares the bytes at
/// the end, which is the claim worth making. What it cannot do is say *why* a
/// replay came out wrong when it does, so everything here reads one field of
/// the document at a time: the step an order lands on, the arrangement it
/// carries, and the four ways a file can be broken.
///
/// **The document refuses rather than guesses**, and that is the part worth
/// testing twice. A save is the one document in this repository that must not
/// fail to load — an older build reads what it understands and ignores the
/// rest. A tape is the opposite: a file this build cannot carry out in full is
/// a file that would replay a *different match* and say nothing about it.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'match_test.dart' show flat;

/// A tape out to a string and back, which is what a file does to it.
OrderTape _roundTrip(OrderTape tape) => OrderTape.fromJson(
  jsonDecode(jsonEncode(tape.toJson())) as Map<String, Object?>,
);

void main() {
  group('a tape', () {
    test('numbers its entries by the step, empty ones included', () {
      // **The index is the step, and an empty step is an empty list rather than
      // a gap.** Mutation: record only the steps somebody asked for something
      // on. Every order after the first then lands early — the match replays at
      // a gallop — and nothing in the document says so, because a tape of four
      // entries is a perfectly well formed tape of four entries.
      final sim = StrategySimulation(random: GameRandom(1), ground: flat());
      final unit = sim.add(Unit(position: Vector3(20.0, 0.0, 20.0)));
      final recorder = OrderTapeRecorder(seed: sim.random.state);
      sim.orders.recorder = recorder;

      for (var i = 0; i < 10; i++) {
        if (i == 7) sim.orders.moveTo(<Unit>[unit], Vector3(60.0, 0.0, 60.0));
        sim.step(1.0 / 30.0);
      }

      expect(recorder.tape.steps, 10);
      expect(recorder.tape.frames[7], hasLength(1));
      expect(
        recorder.tape.frames.where((List<StrategyOrder> it) => it.isEmpty),
        hasLength(9),
      );
    });

    test('carries the arrangement the order was given with', () {
      // A squad sent in a line of ten by an application that later changed its
      // default block would come back in fives, which is a replay that is right
      // about every unit and wrong about where each one stands. So the
      // formation travels with the order rather than being a fact about the
      // build that plays it.
      final tape = OrderTape(
        seed: 3,
        frames: <List<StrategyOrder>>[
          <StrategyOrder>[
            MoveOrder(
              units: const <int>[2, 5, 9],
              goal: Vector3(12.0, 0.0, 34.0),
              formation: const Formation.block(spacing: 2.5, width: 10),
            ),
          ],
        ],
      );

      final MoveOrder came = _roundTrip(tape).frames.single.single as MoveOrder;

      expect(came.units, <int>[2, 5, 9]);
      expect(came.goal.x, closeTo(12.0, 1e-9));
      expect(came.goal.z, closeTo(34.0, 1e-9));
      expect(came.formation.spacing, closeTo(2.5, 1e-9));
      expect(came.formation.width, 10);
    });

    test('carries a job with the two indices a job is made of', () {
      final tape = OrderTape(
        seed: 3,
        frames: <List<StrategyOrder>>[
          <StrategyOrder>[
            const AssignOrder(
              unit: 4,
              node: 1,
              dropOff: 2,
              capacity: 12.0,
              rate: 9.0,
            ),
          ],
        ],
      );

      final AssignOrder came =
          _roundTrip(tape).frames.single.single as AssignOrder;

      expect(came.unit, 4);
      expect(came.node, 1);
      expect(came.dropOff, 2);
      expect(came.capacity, closeTo(12.0, 1e-9));
      expect(came.rate, closeTo(9.0, 1e-9));
    });

    test('refuses an order this build cannot carry out', () {
      // **The one reader in this package that throws**, and the reason is what
      // the document is for: a snapshot that skips a field it does not know
      // loads a world with one thing missing and carries on, while a tape that
      // skips an order replays a different match and reports nothing. The
      // person holding the file would be told the engine is not deterministic.
      expect(
        () => orderFromJson(<String, Object?>{'kind': 'besiege'}),
        throwsA(isA<DemoFormatException>()),
      );
    });

    test('runs out rather than looping when the match outlasts it', () {
      final playback = OrderTapePlayback(
        OrderTape(seed: 1, frames: <List<StrategyOrder>>[<StrategyOrder>[]]),
      );
      final sim = StrategySimulation(random: GameRandom(1), ground: flat());

      playback.applyTo(sim.orders);
      expect(playback.step, 1);
      expect(playback.isFinished, isTrue);

      // Past the end, which is a player taking over from a replay: the queue is
      // left alone rather than handed the last frame again.
      playback.applyTo(sim.orders);
      expect(sim.orders.waiting, isEmpty);
      expect(playback.step, 1);
    });
  });

  group('a recorded match', () {
    MatchDemo demo({OrderTape? tape}) => MatchDemo(
      level: 'assets/levels/map_a.json',
      start: const Snapshot(<String, Object?>{'random': 7}),
      tape: tape ?? OrderTape(seed: 7),
    );

    Map<String, Object?> written({OrderTape? tape}) =>
        jsonDecode(jsonEncode(demo(tape: tape).toJson()))
            as Map<String, Object?>;

    test('survives the trip a file makes', () {
      final MatchDemo came = MatchDemo.fromJson(
        written(
          tape: OrderTape(
            seed: 7,
            frames: <List<StrategyOrder>>[
              <StrategyOrder>[],
              <StrategyOrder>[const AssignOrder(unit: 0, node: 0, dropOff: 0)],
            ],
          ),
        ),
      );

      expect(came.level, 'assets/levels/map_a.json');
      expect(came.start.data.integer('random'), 7);
      expect(came.tape.seed, 7);
      expect(came.steps, 2);
      expect(came.tape.frames[1].single, isA<AssignOrder>());
    });

    test('says which format it is in, and refuses a newer one', () {
      // The shape the level, the snapshot and the crypt's demo all have: a
      // document from a newer build is refused with a sentence rather than read
      // field by field and subtly misplayed.
      expect(demo().toJson()['version'], MatchDemo.formatVersion);
      expect(
        () =>
            MatchDemo.fromJson(<String, Object?>{...written(), 'version': 99}),
        throwsA(isA<DemoFormatException>()),
      );
    });

    test('refuses a file that was not written all the way', () {
      // Each missing piece is a different accident and deserves its own
      // sentence: a file that is not a recording at all, one whose writer
      // stopped before the tape, one with no state to start from, and one that
      // names no map — which is a tape played into whatever happened to be
      // open.
      for (final String missing in <String>[
        'version',
        'level',
        'tape',
        'run',
      ]) {
        expect(
          () => MatchDemo.fromJson(<String, Object?>{
            for (final MapEntry<String, Object?> it in written().entries)
              if (it.key != missing) it.key: it.value,
          }),
          throwsA(isA<DemoFormatException>()),
          reason: 'a recording with no $missing was read anyway',
        );
      }
    });

    test('says so when its starting state is from a newer build', () {
      // The nested failure, which is the one that is easy to lose: a snapshot
      // this build cannot read is a demo this build cannot play, and the
      // sentence has to say which half was wrong.
      expect(
        () => MatchDemo.fromJson(<String, Object?>{
          ...written(),
          'run': <String, Object?>{'version': 99},
        }),
        throwsA(
          isA<DemoFormatException>().having(
            (DemoFormatException it) => it.message,
            'message',
            contains('starting state'),
          ),
        ),
      );
    });
  });
}
