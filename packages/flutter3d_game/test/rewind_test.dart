/// The last few seconds of a run, kept so they can be lived again.
///
///     flutter test test/rewind_test.dart
///
/// What is pinned is the arithmetic a kill camera and a rewind mechanic both
/// rest on: a keyframe and the entries after it reproduce every state between,
/// exactly, and the buffer forgets what a rewind cannot reach.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _fire = GameAction('fire');

/// A simulation small enough to snapshot in a map and large enough to drift:
/// it reads the stick, the latches and the dice, so a wrong keyframe, a
/// dropped entry or a lost die each lands somewhere else.
final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);

  final GameRandom dice;
  double x = 0.0;
  int shots = 0;
  int rolls = 0;

  void step(InputState input) {
    x += input.moveAxis.x;
    if (input.pressed(_fire)) {
      shots++;
      rolls += dice.nextInt(1000);
    }
    if (input.held(_fire)) x += 0.125;
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'x': x,
    'shots': shots,
    'rolls': rolls,
    'random': dice.state,
  });

  void restore(Snapshot snapshot) {
    final data = snapshot.data;
    x = data.number('x');
    shots = data.integer('shots');
    rolls = data.integer('rolls');
    dice.state = data.integer('random');
  }

  String get state => '$x/$shots/$rolls/${dice.state}';
}

void _play(InputState input, int step) {
  input.setStickAxis(step % 3 == 0 ? 1.0 : -0.5, 0.0);
  if (step % 11 == 0) input.press(_fire);
  if (step % 11 == 4) input.release(_fire);
}

/// Plays [steps] steps through a loop with [buffer] attached, keyframing the
/// way a game does, and returns the toy's state before every step.
List<String> _run(_Toy toy, RewindBuffer buffer, int steps) {
  final input = InputState();
  final states = <String>[];
  final loop = GameLoop(
    input: input,
    onStep: (_) {
      if (buffer.keyframeDue) buffer.keyframe(toy.save());
      states.add(toy.state);
      toy.step(input);
    },
  )..recorders.add(buffer.recorder);
  for (var i = 0; i < steps; i++) {
    _play(input, i);
    loop.advance(1 / 60);
  }
  return states;
}

/// Restores [point] into a fresh toy and plays it to the point.
_Toy _arrive(RewindPoint point) {
  final toy = _Toy(0)..restore(point.snapshot);
  final input = InputState();
  final playback = InputTapePlayback(point.tapeToPoint);
  while (!playback.isFinished) {
    playback.applyTo(input);
    toy.step(input);
    input.endStep();
  }
  return toy;
}

void main() {
  test('a rewind to any step lands on the state that step saw', () {
    // The whole claim: not the keyframes only, every step between them.
    final buffer = RewindBuffer(stepsPerSecond: 60, history: 4.0);
    final states = _run(_Toy(5), buffer, 200);

    for (final target in <int>[0, 1, 59, 60, 61, 119, 137, 199, 200]) {
      final point = buffer.rewindTo(target);
      expect(point, isNotNull, reason: 'step $target is within four seconds');
      if (target < states.length) {
        expect(_arrive(point!).state, states[target], reason: 'step $target');
      }
    }
  });

  test('and by seconds, which is how a kill camera asks', () {
    final buffer = RewindBuffer(stepsPerSecond: 60, history: 4.0);
    final states = _run(_Toy(5), buffer, 200);

    final point = buffer.rewindBy(1.5)!;

    expect(point.step, 200 - 90);
    expect(_arrive(point).state, states[200 - 90]);
    expect(
      point.tapeFromPoint.steps,
      90,
      reason: 'what the camera plays after arriving: the way to the present',
    );
  });

  test('forgets what a rewind cannot reach', () {
    final buffer = RewindBuffer(stepsPerSecond: 60, history: 2.0);
    _run(_Toy(5), buffer, 600);

    expect(buffer.available, lessThanOrEqualTo(3.0));
    expect(buffer.available, greaterThanOrEqualTo(2.0));
    expect(buffer.rewindBy(2.0), isNotNull);
    expect(
      buffer.rewindBy(5.0),
      isNull,
      reason: 'ten seconds ago is gone, and says so rather than guessing',
    );
    expect(
      buffer.recorder.tape.steps,
      lessThan(200),
      reason: 'the tape is trimmed with the keyframes, or it grows for ever',
    );
  });

  test('a cut makes the point the present', () {
    // The rewind mechanic: go back, take over, and the future that was
    // recorded is not the one that happens.
    final buffer = RewindBuffer(stepsPerSecond: 60, history: 4.0);
    _run(_Toy(5), buffer, 200);

    final point = buffer.rewindBy(1.0)!;
    buffer.cut(point);

    expect(buffer.step, 140);
    expect(buffer.rewindTo(150), isNull);
    expect(buffer.rewindTo(140), isNotNull);
  });

  test('a reset forgets the level', () {
    final buffer = RewindBuffer(stepsPerSecond: 60, history: 4.0);
    _run(_Toy(5), buffer, 100);

    buffer.reset();

    expect(buffer.step, 0);
    expect(buffer.available, 0.0);
    expect(buffer.rewindTo(0), isNull);
  });

  test('a keyframe is due before the first step and every interval after', () {
    final buffer = RewindBuffer(
      stepsPerSecond: 60,
      history: 4.0,
      keyframeEvery: 10,
    );
    final due = <int>[];
    final input = InputState();
    final loop = GameLoop(
      input: input,
      onStep: (_) {
        if (buffer.keyframeDue) {
          due.add(buffer.step - 1);
          buffer.keyframe(const Snapshot(<String, Object?>{}));
        }
      },
    )..recorders.add(buffer.recorder);
    for (var i = 0; i < 25; i++) {
      loop.advance(1 / 60);
    }

    expect(due, <int>[0, 10, 20]);
    expect(
      buffer.keyframeDue,
      isFalse,
      reason: 'asked between steps it describes the step just run, once',
    );
  });
}
