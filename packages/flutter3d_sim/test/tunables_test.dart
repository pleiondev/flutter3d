/// `HR4`: a number changed while the game runs is an input, so a run tuned as
/// it was played replays like any other.
///
///     flutter test test/tunables_test.dart
///
/// Mutation: drop `tunes:` from the recorder and the replay runs at the old
/// speed; skip `tunes` in `InputFrame.toJson` and the saved tape forgets it.
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A walker whose speed is a tunable.
final class _Walker {
  final Tunables tunables = Tunables(const <String, double>{'speed': 1.0});
  double x = 0.0;

  void step(InputState input) {
    tunables.readFrom(input);
    x += tunables['speed'] * 0.1;
  }
}

/// Plays [steps] steps, tuning the speed to 3 at step 40, and returns the
/// walker and the tape.
({_Walker walker, InputTape tape}) _played(int steps) {
  final walker = _Walker();
  final input = InputState();
  final recorder = InputTapeRecorder(seed: 1);
  for (var step = 0; step < steps; step++) {
    if (step == 40) input.tune('speed', 3.0);
    recorder.record(input);
    input.beginStep();
    walker.step(input);
    input.endStep();
  }
  return (walker: walker, tape: recorder.tape);
}

double _replayed(InputTape tape) {
  final walker = _Walker();
  final input = InputState();
  final playback = InputTapePlayback(tape);
  while (!playback.isFinished) {
    playback.applyTo(input);
    input.beginStep();
    walker.step(input);
    input.endStep();
  }
  return walker.x;
}

void main() {
  test('a tape with a tunable changed half way reproduces the run', () {
    final run = _played(100);
    // 40 steps at 1, 60 at 3.
    expect(run.walker.x, closeTo(4.0 + 18.0, 1e-9));
    expect(_replayed(run.tape), run.walker.x);
  });

  test('and still does after the tape has been saved and read back', () {
    final run = _played(100);
    final saved = InputTape.fromJson(
      jsonDecode(jsonEncode(run.tape.toJson())) as Map<String, Object?>,
    );
    expect(saved.frames[40].tunes, <String, double>{'speed': 3.0});
    expect(saved.frames[40].isIdle, isFalse);
    expect(_replayed(saved), run.walker.x);
  });

  test('a tune lasts one step on the input and for good on the table', () {
    final walker = _Walker();
    final input = InputState()..tune('speed', 2.0);
    walker.step(input);
    input.endStep();
    expect(input.tunesThisStep, isEmpty);
    walker.step(input);
    expect(walker.x, closeTo(0.4, 1e-9));
  });

  test('a muted input takes no tune, as it takes no key', () {
    final input = InputState()..muted = true;
    input.tune('speed', 9.0);
    expect(input.tunesThisStep, isEmpty);
  });

  test('a name the table does not declare is ignored', () {
    final tunables = Tunables(const <String, double>{'speed': 1.0});
    tunables.readFrom(InputState()..tune('gravity', 5.0));
    expect(tunables.values.keys, <String>['speed']);
    expect(() => tunables['gravity'], throwsArgumentError);
  });

  test('a snapshot holds what was tuned, and a restore puts it back', () {
    final tunables = Tunables(const <String, double>{'speed': 1.0, 'jump': 2.0})
      ..readFrom(InputState()..tune('speed', 4.0));
    final saved = tunables.toJson();
    expect(saved, <String, Object?>{'speed': 4.0});

    tunables.readFrom(InputState()..tune('jump', 7.0));
    tunables.restore(saved);
    expect(tunables.values, <String, double>{'speed': 4.0, 'jump': 2.0});
  });
}
