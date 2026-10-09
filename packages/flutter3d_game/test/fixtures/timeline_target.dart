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
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);
  final GameRandom dice;
  final Tunables tunables = Tunables(const <String, double>{'speed': 1.0});
  double x = 0.0;

  void step(InputState input) {
    tunables.readFrom(input);
    x += tunables['speed'];
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'x': x,
    // `N4`'s tracks read the toy as one entity; restore ignores it, since
    // it repeats `x`.
    'entities': <String, Object?>{
      'toy': <String, Object?>{'x': x},
    },
    'random': dice.state,
    'tunables': tunables.toJson(),
  });

  void restore(Snapshot snapshot) {
    x = snapshot.data.number('x');
    dice.state = snapshot.data.integer('random');
    tunables.restore(snapshot.data['tunables']! as Map<String, Object?>);
  }
}

void main() {
  test('a live target for an external VM service client', () async {
    final toy = _Toy(1);
    final input = InputState();
    final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
    final frameTimes = StepTimeTrace();
    var stepNumber = 0;
    // The toy as one part of the loop's snapshots, under `toy`, and its step
    // a system, timed when it is a live step rather than a replay.
    final loop = EngineLoop(input: input)
      ..snapshots.add(
        SnapshotPart.of(
          id: 'toy',
          capture: () => toy.save().data,
          restore: (Object? data, int _) {
            if (data is Map) {
              toy.restore(Snapshot(data.cast<String, Object?>()));
            }
          },
        ),
      )
      ..addSystem('toy', LoopPhase.rules, (LoopContext step) {
        if (step.isResimulated) {
          toy.step(input);
        } else {
          frameTimes.record(++stepNumber, () => toy.step(input));
        }
      });
    rewind.attach(loop);
    final timeline = RunTimeline(rewind: rewind, loop: loop);
    // `HR3`: a level the toy plays on, taken from outside as the editor
    // sends it. The toy reads nothing from it; what is checked from outside is
    // that a brush change branches the timeline and a look change does not.
    registerLevelExtension(
      LiveLevel(
        level: Level.fromJson(const <String, Object?>{
          'version': 1,
          'brushes': <Object?>[
            <String, Object?>{
              'at': <double>[0, 0, 0],
              'size': <double>[1, 1, 1],
              'material': 'stone',
            },
          ],
        }),
        present: (next, diff) {},
        rebuild: (next) {},
        timeline: timeline,
      ),
    );
    registerTuningExtensions(input, toy.tunables);
    registerTimelineExtensions(
      timeline,
      entityLayout: EntityLayout.rows('entities'),
      trackedPart: 'toy',
      frameTimes: frameTimes,
      bugReport: () => <String, Object?>{'x': toy.x, 'step': stepNumber},
    );

    // A game loop, driven by a timer rather than by the test framework's own
    // clock — this process is meant to look like a running game to whatever
    // connects to it, and a running game's loop does not wait for anyone.
    final ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (timeline.isPaused) return;
      loop.runSteps(1);
    });

    // Long enough for a client to connect, drive the timeline through every
    // extension and disconnect; `run_timeline_extensions_test.dart` kills
    // this process well before the ten seconds are up rather than waiting
    // for it.
    await Future<void>.delayed(const Duration(seconds: 10));
    ticker.cancel();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
