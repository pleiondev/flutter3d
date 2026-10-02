/// `N4`'s divergence bisect: two runs of a tape, and the first step and
/// component at which they stop being the same run.
///
///     flutter test test/tape_bisect_test.dart
///
/// The toy is an `EcsWorld` of three entities with a position and a health
/// each, so the answer is checked in the words a person debugging a desync
/// wants — which entity, which component — and a "build" with a defect
/// planted at a known step stands in for a code change or another platform.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

const GameAction _fire = GameAction('fire');

final class _Position {
  _Position(this.x);
  double x;
}

final class _Health {
  _Health(this.hp);
  int hp;
}

/// One build of the game. [defectAt] makes entity 1 lose a point of health
/// on that step and only that step — a defect that does nothing to the
/// position, so the component named has to be the right one.
final class _Toy {
  _Toy({this.defectAt}) {
    world
      ..register<_Position>(
        'Position',
        encode: (p) => p.x,
        decode: (d) => d is num ? _Position(d.toDouble()) : null,
      )
      ..register<_Health>(
        'Health',
        encode: (h) => h.hp,
        decode: (d) => d is num ? _Health(d.toInt()) : null,
      );
    entities = <Entity>[for (var i = 0; i < 3; i++) world.spawn()];
    for (final (i, entity) in entities.indexed) {
      world
        ..set(entity, _Position(i * 10.0))
        ..set(entity, _Health(100));
    }
  }

  final int? defectAt;
  final EcsWorld world = EcsWorld();
  final GameRandom dice = GameRandom(7);
  late final List<Entity> entities;
  int steps = 0;

  void step(InputState input) {
    for (final entity in entities) {
      world.get<_Position>(entity)!.x += input.moveAxis.x;
    }
    if (input.pressed(_fire)) {
      world.get<_Health>(entities[2])!.hp -= 1 + dice.nextInt(3);
    }
    if (steps == defectAt) world.get<_Health>(entities[1])!.hp -= 1;
    steps++;
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'world': world.save(),
    'random': dice.state,
    'steps': steps,
  });

  void restore(Snapshot snapshot) {
    world.restore(snapshot.data.object('world')!);
    dice.state = snapshot.data.integer('random');
    steps = snapshot.data.integer('steps');
  }
}

/// A tape of [length] steps: the stick swings and fire is pressed now and
/// then. [fireAt] adds one press, for a recording that differs.
InputTape _tape(int length, {int? fireAt}) => InputTape(
  seed: 7,
  frames: <InputFrame>[
    for (var i = 0; i < length; i++)
      InputFrame(
        pressed: <String>[if (i % 37 == 5 || i == fireAt) _fire.name],
        released: <String>[
          if (i % 37 == 6 || (fireAt != null && i == fireAt + 1)) _fire.name,
        ],
        stickX: i % 4 == 0 ? 1.0 : -0.25,
        stickY: 0.0,
      ),
  ],
);

ReplaySide _side(_Toy toy, InputTape tape) {
  final input = InputState();
  return ReplaySide(
    start: toy.save(),
    tape: tape,
    input: input,
    step: () => toy.step(input),
    restore: toy.restore,
    capture: toy.save,
  );
}

final _layout = EntityLayout.ecs(const <String>['world']);

void main() {
  test('names the step a defect was planted on, and the component', () {
    // Mutation: return `lo` instead of `hi` from the search — the step named
    // is then the last agreement, and `step - 1` misses the defect by one.
    final result = bisectTapes(
      a: _side(_Toy(), _tape(1000)),
      b: _side(_Toy(defectAt: 613), _tape(1000)),
      layout: _layout,
    );

    expect(result, isA<TapesDiverge>());
    final diverge = result as TapesDiverge;
    expect(diverge.step - 1, 613, reason: 'the tape entry that differed');
    expect(diverge.inputsDiffer, isFalse);
    expect(diverge.component, EntityComponent('1', 'Health'));
    expect(diverge.components, <EntityComponent>[
      EntityComponent('1', 'Health'),
    ], reason: 'the position and the other healths did not move');
    expect(diverge.path, '1.Health');
    expect((diverge.expected, diverge.found), (100, 99));
  });

  test('compares a logarithm of the states, not all of them', () {
    // Mutation: walk `lo` up one step at a time instead of halving. The
    // answer is the same; the probes are six hundred.
    final a = _side(_Toy(), _tape(1000));
    final b = _side(_Toy(defectAt: 613), _tape(1000));
    final diverge = bisectTapes(a: a, b: b) as TapesDiverge;

    expect(diverge.probes, lessThanOrEqualTo(12));
    expect(
      a.stepsRun,
      lessThanOrEqualTo(2000),
      reason:
          'the first pass reaches the end, and each probe after it plays on '
          'from the nearest state already reached: half the bracket, then a '
          'quarter, and so on',
    );
  });

  test('says when the input is what differs', () {
    // Mutation: compare frames at `step` instead of `step - 1`, the entry
    // after the one that made the difference.
    final diverge =
        bisectTapes(
              a: _side(_Toy(), _tape(400)),
              b: _side(_Toy(), _tape(400, fireAt: 250)),
              layout: _layout,
            )
            as TapesDiverge;

    expect(diverge.step - 1, 250);
    expect(diverge.inputsDiffer, isTrue);
    expect(diverge.component, EntityComponent('2', 'Health'));
  });

  test('two identical runs agree, and a longer tape is reported', () {
    // Mutation: compare to the longer tape's end; `stateAfter` asserts past
    // the shorter one.
    final result = bisectTapes(
      a: _side(_Toy(), _tape(300)),
      b: _side(_Toy(), _tape(320)),
    );

    expect(result, isA<TapesAgree>());
    expect((result as TapesAgree).steps, 300);
    expect(result.toString(), contains('20 more'));
  });

  test('runs that start apart diverge at step zero', () {
    // Mutation: start the search without checking the start — bisection
    // between two differing ends then names step one.
    final shifted = _Toy()..dice.nextInt(5);
    final diverge =
        bisectTapes(
              a: _side(_Toy(), _tape(100)),
              b: _side(shifted, _tape(100)),
              layout: _layout,
            )
            as TapesDiverge;

    expect(diverge.step, 0);
    expect(diverge.components, isEmpty, reason: 'only the dice differ');
    expect(diverge.path, 'random');
  });

  test('a bracket that does not hold is widened rather than trusted', () {
    // Mutation: trust `differsAt` — the search between two agreeing ends
    // then names a step that never differed.
    final diverge =
        bisectTapes(
              a: _side(_Toy(), _tape(1000)),
              b: _side(_Toy(defectAt: 613), _tape(1000)),
              agreedAt: 700,
              differsAt: 200,
            )
            as TapesDiverge;

    expect(diverge.step - 1, 613);
  });

  test('two digest traces bracket the search to one checkpoint interval', () {
    // Mutation: drop the `+ 1` that turns a checkpoint step into a count of
    // steps — the bracket's top then agrees and is widened to the end.
    DigestTrace trace(_Toy toy) {
      final input = InputState();
      final playback = InputTapePlayback(_tape(1000));
      final trace = DigestTrace();
      for (var step = 0; !playback.isFinished; step++) {
        playback.applyTo(input);
        input.beginStep();
        toy.step(input);
        input.endStep();
        trace.observe(step, toy.save().data);
      }
      return trace;
    }

    final bracket = bracketFromTraces(
      trace(_Toy()),
      trace(_Toy(defectAt: 613)),
    )!;
    expect(bracket, (agreedAt: 601, differsAt: 626));

    final diverge =
        bisectTapes(
              a: _side(_Toy(), _tape(1000)),
              b: _side(_Toy(defectAt: 613), _tape(1000)),
              agreedAt: bracket.agreedAt,
              differsAt: bracket.differsAt,
            )
            as TapesDiverge;
    expect(diverge.step - 1, 613);
    expect(diverge.probes, lessThanOrEqualTo(7));
  });
}
