/// A live target for `run_timeline_extensions_test.dart`: a toy simulation
/// stepping on its own clock, with its `RunTimeline` registered on the VM
/// service — everything `run_timeline_extensions_test.dart` connects to from
/// outside the process, the way an editor eventually would.
///
///     flutter test --enable-vmservice test/fixtures/timeline_target.dart
///
/// **Not named `*_test.dart` on purpose**, so `flutter test` run over the
/// whole package (`tool/ci.sh`'s own loop included) never picks this up on
/// its own — it does nothing useful run alone, and would either hang waiting
/// for a client that never connects or exit having proved nothing. It is
/// meant to be started by `run_timeline_extensions_test.dart`, which knows to
/// name it explicitly and to kill it when done.
library;

import 'dart:async';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);
  final GameRandom dice;
  double x = 0.0;

  void step(InputState input) => x += 1.0;

  Snapshot save() => Snapshot(<String, Object?>{'x': x, 'random': dice.state});

  void restore(Snapshot snapshot) {
    x = snapshot.data.number('x');
    dice.state = snapshot.data.integer('random');
  }
}

void main() {
  test('a live target for an external VM service client', () async {
    final toy = _Toy(1);
    final input = InputState();
    final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
    final timeline = RunTimeline(
      rewind: rewind,
      input: input,
      stepSim: (dt) => toy.step(input),
      restore: toy.restore,
    );
    final frameTimes = StepTimeTrace();
    var stepNumber = 0;
    registerTimelineExtensions(
      timeline,
      frameTimes: frameTimes,
      bugReport: () => <String, Object?>{'x': toy.x, 'step': stepNumber},
    );

    // A game loop, driven by a timer rather than by the test framework's own
    // clock — this process is meant to look like a running game to whatever
    // connects to it, and a running game's loop does not wait for anyone.
    final ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (timeline.isPaused) return;
      rewind.recorder.record(input);
      input.beginStep();
      if (rewind.keyframeDue) rewind.keyframe(toy.save());
      frameTimes.record(++stepNumber, () => toy.step(input));
      input.endStep();
    });

    // Long enough for a client to connect, drive the timeline through every
    // extension and disconnect; `run_timeline_extensions_test.dart` kills
    // this process well before the ten seconds are up rather than waiting
    // for it.
    await Future<void>.delayed(const Duration(seconds: 10));
    ticker.cancel();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
