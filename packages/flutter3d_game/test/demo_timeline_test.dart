/// `rp-02`'s other half of "scrub across a whole `.f3drun`": a [RunTimeline]
/// built on [rewindBufferFromDemo] answers `preview`/`releaseAtStep` for any
/// step of a whole recorded run, not only the last few seconds a live
/// [RewindBuffer] keeps.
///
///     flutter test test/demo_timeline_test.dart
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _fire = GameAction('fire');

/// The same shape as `run_timeline_test.dart`'s toy.
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

/// Plays [steps] fixed steps of [toy] on a fresh tape and returns the
/// [Demo] that recording produced, seeded like the tape it wraps.
Demo _record(_Toy toy, int seed, int steps) {
  final input = InputState();
  final recorder = InputTapeRecorder(seed: seed);
  final start = toy.save();
  for (var step = 0; step < steps; step++) {
    _play(input, step);
    recorder.record(input);
    input.beginStep();
    toy.step(input);
    input.endStep();
  }
  return Demo(
    level: 'assets/levels/toy.json',
    levelHash: 'deadbeef',
    start: start,
    tape: recorder.tape,
    buildStamp: 'test',
    checkpoints: DigestTrace(),
  );
}

void main() {
  test('a RunTimeline built on the reconstructed buffer reaches the very '
      'start of a run a live ten-second buffer never would', () {
    final recordingToy = _Toy(7);
    final demo = _record(recordingToy, 7, 600);

    final toy = _Toy(0);
    final input = InputState();
    final buffer = rewindBufferFromDemo(
      demo: demo,
      stepsPerSecond: 60,
      input: input,
      restore: toy.restore,
      save: toy.save,
      stepSim: (dt) => toy.step(input),
    );
    final timeline = RunTimeline(
      rewind: buffer,
      input: input,
      stepSim: (dt) => toy.step(input),
      restore: toy.restore,
    );

    // Ten seconds is the default live history — this run is also ten
    // seconds long (600 steps at 60/s), so scrubbing to a step near its
    // very beginning only reaches this far because the whole tape was
    // replayed into keyframes, not because of a generous default.
    final point = timeline.preview(9.5);
    expect(
      point,
      isNotNull,
      reason: 'the reconstruction keeps the whole run reachable',
    );
    expect(point!.step, lessThan(50));

    timeline.releaseAt(point);

    final independent = _Toy(0)..restore(demo.start);
    final independentInput = InputState();
    for (var step = 0; step < point.step; step++) {
      _play(independentInput, step);
      independentInput.beginStep();
      independent.step(independentInput);
      independentInput.endStep();
    }
    expect(
      toy.state,
      independent.state,
      reason:
          'the reconstructed buffer must land on the same state an '
          'independent replay of the demo to that step does',
    );
  });

  test('preview beyond the end of the tape finds nothing', () {
    final recordingToy = _Toy(3);
    final demo = _record(recordingToy, 3, 120);

    final toy = _Toy(0);
    final input = InputState();
    final buffer = rewindBufferFromDemo(
      demo: demo,
      stepsPerSecond: 60,
      input: input,
      restore: toy.restore,
      save: toy.save,
      stepSim: (dt) => toy.step(input),
    );
    final timeline = RunTimeline(
      rewind: buffer,
      input: input,
      stepSim: (dt) => toy.step(input),
      restore: toy.restore,
    );

    expect(timeline.preview(1000.0), isNull);
  });

  test('restores the InputState mute flag once the replay is done', () {
    final recordingToy = _Toy(1);
    final demo = _record(recordingToy, 1, 60);

    final toy = _Toy(0);
    final input = InputState();
    rewindBufferFromDemo(
      demo: demo,
      stepsPerSecond: 60,
      input: input,
      restore: toy.restore,
      save: toy.save,
      stepSim: (dt) => toy.step(input),
    );

    expect(input.muted, isFalse);
  });
}
