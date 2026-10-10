/// `HR3`'s tail: a level swapped under a run is written into the run's demo
/// and played back from it.
///
///     flutter test test/demo_recording_test.dart
///
/// On a toy whose one level property is its speed, so that a swap is a thing
/// the state visibly depends on. The shipped game's version of the claim,
/// through its own loader and its own swap, is the platformer's
/// `demo_level_swap_test.dart`.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// The toy reads its speed off the level's fog density: any number a level
/// document carries will do, and this one needs no brushes.
Level _level(double speed) => Level(name: 'toy', fogDensity: speed);

final class _Toy {
  double speed = 1.0;
  double x = 0.0;

  void step(InputState input) => x += input.moveAxis.x * speed;

  Snapshot save() => Snapshot(<String, Object?>{'x': x, 'random': 0});

  void restore(Snapshot snapshot) => x = snapshot.data.number('x');
}

/// [toy] as one part of a fresh loop's snapshots, under `toy`, and a system
/// in its step, reading [input]; [rewind], when given, attached to it.
EngineLoop _loopOf(_Toy toy, InputState input, [RewindBuffer? rewind]) {
  final loop = EngineLoop(input: input)
    ..snapshots.add(
      SnapshotPart.of(
        id: 'toy',
        capture: () => toy.save().data,
        restore: (Object? data, int _) {
          if (data is Map) toy.restore(Snapshot(data.cast<String, Object?>()));
        },
      ),
    )
    ..addSystem('toy', LoopPhase.rules, (_) => toy.step(input));
  rewind?.attach(loop);
  return loop;
}

void _play(InputState input, int step) =>
    input.setStickAxis(step % 5 == 0 ? -0.25 : 1.0, 0.0);

/// A run of [steps] steps on a live timeline with [edits] made at the steps
/// they are keyed by, recorded the way a game records it.
({DemoRecording demo, _Toy toy, List<int> swappedAt}) _live({
  required int steps,
  Map<int, double> edits = const <int, double>{},
}) {
  final toy = _Toy();
  final input = InputState();
  final rewind = RewindBuffer(stepsPerSecond: 60, keyframeEvery: 20);
  final loop = _loopOf(toy, input, rewind);
  final timeline = RunTimeline(rewind: rewind, loop: loop);
  final demo = DemoRecording(
    level: 'assets/levels/toy.json',
    levelHash: _level(1.0).digestHex,
    start: toy.save(),
    seed: 0,
    checkpointEvery: 10,
  )..attach(loop);
  final swappedAt = <int>[];
  for (var step = 0; step < steps; step++) {
    if (edits[step] case final double speed) {
      final next = _level(speed);
      final at = timeline.swapLevel(
        () => toy.speed = speed,
        levelDigest: next.digestHex,
      );
      swappedAt.add(at);
      expect(demo.levelSwapped(next, stepsAgo: rewind.step - at), isTrue);
    }
    _play(input, step);
    loop.runSteps(1);
    demo.observe(toy.save);
  }
  return (demo: demo, toy: toy, swappedAt: swappedAt);
}

/// Plays [demo] on a fresh toy, [swaps] or not.
({DemoReplay replay, _Toy toy}) _replay(Demo demo, {bool swaps = true}) {
  final toy = _Toy();
  final input = InputState();
  final replay = replayDemoOnLoop(
    demo: demo,
    loop: _loopOf(toy, input),
    part: 'toy',
    swapLevel: swaps ? (level) => toy.speed = level.fogDensity : (level) {},
  );
  return (replay: replay, toy: toy);
}

Demo _sent(DemoRecording demo) => Demo.fromJson(
  jsonDecode(jsonEncode(demo.demo(buildStamp: 'test').toJson()))
      as Map<String, Object?>,
);

void main() {
  test('a run swapped at step K, saved and replayed, arrives where it did', () {
    final live = _live(steps: 120, edits: const <int, double>{50: 3.0});
    final file = _sent(live.demo);

    expect(file.levelSwaps.single.step, live.swappedAt.single);
    expect(file.levelSwaps.single.step, 40, reason: 'the keyframe before 50');

    final replayed = _replay(file);
    expect(replayed.replay.divergence, isNull);
    expect(replayed.replay.steps, 120);
    expect(replayed.toy.x, live.toy.x);

    // Mutation: a replay that does not swap — the speed it plays at after
    // step 40 is the old one, and the first checkpoint the file holds after
    // it says so: 60, since the one at 50 was taken before the swap went
    // back over it.
    final unswapped = _replay(file, swaps: false);
    expect(unswapped.toy.x, isNot(live.toy.x));
    expect(unswapped.replay.divergence?.step, 60);
  });

  test('a second edit within a keyframe replaces the first', () {
    // Both swaps go back to the keyframe at 40: the second replays the
    // steps the first had replayed, so the first never happened.
    final live = _live(steps: 90, edits: const <int, double>{45: 3.0, 55: 0.5});
    final file = _sent(live.demo);

    // Mutation: keep the earlier swap at the same step — the file is
    // refused on reading, since two swaps at one step are out of order.
    expect(live.swappedAt, <int>[40, 40]);
    expect(file.levelSwaps.single.level.fogDensity, 0.5);
    expect(_replay(file).toy.x, live.toy.x);
  });

  test('the checkpoints after the swap step are forgotten, and the ones '
      'before kept', () {
    final live = _live(steps: 60, edits: const <int, double>{50: 3.0});

    // Mutation: keep the trace whole — the checkpoint at 50 was taken under
    // the old speed, and every honest replay would diverge there.
    expect(live.demo.checkpoints.steps, <int>[10, 20, 30, 40, 60]);
  });

  test('a swap from before the recording began is not written into it', () {
    final demo = DemoRecording(
      level: 'assets/levels/toy.json',
      levelHash: _level(1.0).digestHex,
      start: _Toy().save(),
      seed: 0,
    );
    for (var step = 0; step < 5; step++) {
      demo.recorder.record(InputState());
    }

    // Mutation: clamp the step to zero — the file would say the start was
    // made by the new level, when the old one made it.
    expect(demo.levelSwapped(_level(2.0), stepsAgo: 6), isFalse);
    expect(demo.demo(buildStamp: 'test').levelSwaps, isEmpty);
    expect(demo.levelSwapped(_level(2.0), stepsAgo: 5), isTrue);
    expect(demo.demo(buildStamp: 'test').levelSwaps.single.step, 0);
  });

  test('a demo with swaps is refused where it cannot be played honestly', () {
    final file = _sent(
      _live(steps: 60, edits: const <int, double>{30: 2.0}).demo,
    );
    final toy = _Toy();
    final input = InputState();

    // Mutation: drop either check — the replay plays through the swap and
    // calls the result a divergence of the simulation.
    expect(
      () =>
          replayDemoOnLoop(demo: file, loop: _loopOf(toy, input), part: 'toy'),
      throwsArgumentError,
    );
    expect(
      () => rewindBufferFromDemo(
        demo: file,
        loop: _loopOf(toy, input),
        part: 'toy',
      ),
      throwsArgumentError,
    );
  });

  test('a demo says which physics it was recorded on', () {
    final demo = DemoRecording(
      level: 'assets/levels/toy.json',
      levelHash: _level(1.0).digestHex,
      start: _Toy().save(),
      seed: 0,
    );
    // Mutation: leaving it out, which a replay reads as "whatever is on".
    expect(demo.demo(buildStamp: 'test').physics, 'dart');
    final native = DemoRecording(
      level: 'assets/levels/toy.json',
      levelHash: _level(1.0).digestHex,
      start: _Toy().save(),
      seed: 0,
      physics: const _Named('native'),
    );
    expect(native.demo(buildStamp: 'test').physics, 'native');
  });

  test('a demo records its simulation and a pose record beside the tape', () {
    final toy = _Toy();
    final input = InputState();
    const simulation = SimulationVersion(genre: 'toy', genreVersion: 3);
    final demo = DemoRecording(
      level: 'assets/levels/toy.json',
      levelHash: _level(1.0).digestHex,
      start: toy.save(),
      seed: 0,
      simulation: simulation,
      poseEvery: 5,
      bodies: () => <BodyPose>[
        BodyPose('toy', Vector3(toy.x, 0.0, 0.0), Quaternion.identity()),
      ],
    );
    for (var step = 0; step < 20; step++) {
      _play(input, step);
      demo.recorder.record(input);
      input.beginStep();
      toy.step(input);
      demo.observe(toy.save);
      input.endStep();
    }
    final file = _sent(demo);

    // Mutation: leave either out of `demo()` and the file cannot say which
    // simulation it needs, nor show anything when it is not this one.
    expect(file.simulation, simulation);
    final poses = file.poses!;
    expect(poses.frames.map((f) => f.step), <int>[5, 10, 15, 20]);
    expect(poses.frames.last.bodies.single![0], closeTo(toy.x, 1e-3));
  });

  test('a replay on another simulation is refused with the poses to show', () {
    final toy = _Toy();
    final input = InputState();
    final recording = DemoRecording(
      level: 'assets/levels/toy.json',
      levelHash: _level(1.0).digestHex,
      start: toy.save(),
      seed: 0,
      simulation: const SimulationVersion(genre: 'toy'),
      bodies: () => <BodyPose>[
        BodyPose('toy', Vector3(toy.x, 0.0, 0.0), Quaternion.identity()),
      ],
    );
    for (var step = 0; step < 8; step++) {
      _play(input, step);
      recording.recorder.record(input);
      input.beginStep();
      toy.step(input);
      recording.observe(toy.save);
      input.endStep();
    }
    final file = _sent(recording);
    const newer = SimulationVersion(genre: 'toy', genreVersion: 2);

    // Mutation: drop the check from either and the tape is replayed into the
    // newer rules, parting at the first checkpoint as if the toy were broken.
    for (final replay in <void Function()>[
      () => replayDemoOnLoop(
        demo: file,
        loop: _loopOf(toy, input),
        part: 'toy',
        simulation: newer,
      ),
      () => rewindBufferFromDemo(
        demo: file,
        loop: _loopOf(toy, input),
        part: 'toy',
        simulation: newer,
      ),
    ]) {
      expect(
        replay,
        throwsA(
          isA<ReplayException>()
              .having((r) => r.reason, 'reason', contains('toy 1'))
              .having((r) => r.poses?.frames.length, 'pose frames', 2),
        ),
      );
    }
    // The same simulation still replays, and agrees with itself.
    final same = replayDemoOnLoop(
      demo: file,
      loop: _loopOf(toy, input),
      part: 'toy',
      simulation: const SimulationVersion(genre: 'toy'),
    );
    expect(same.divergence, isNull);
  });

  test('a replay that names no simulation is checked against the loop\'s', () {
    final toy = _Toy();
    final input = InputState();
    final recording = DemoRecording(
      level: 'assets/levels/toy.json',
      levelHash: _level(1.0).digestHex,
      start: toy.save(),
      seed: 0,
      simulation: const SimulationVersion(engine: 2),
    );
    for (var step = 0; step < 8; step++) {
      _play(input, step);
      recording.recorder.record(input);
      input.beginStep();
      toy.step(input);
      recording.observe(toy.save);
      input.endStep();
    }
    final file = _sent(recording);

    // Mutation: check only when the caller passes `simulation`, as both did —
    // a tape from a newer engine opens without a word and parts at a
    // checkpoint, or scrubs into states this build never computed.
    for (final replay in <void Function()>[
      () =>
          replayDemoOnLoop(demo: file, loop: _loopOf(toy, input), part: 'toy'),
      () => rewindBufferFromDemo(
        demo: file,
        loop: _loopOf(toy, input),
        part: 'toy',
      ),
    ]) {
      expect(
        replay,
        throwsA(
          isA<ReplayException>().having(
            (r) => r.reason,
            'reason',
            contains('newer than this build'),
          ),
        ),
      );
    }
  });
}

/// A backend that is only its name: what the recording reads of it.
final class _Named extends PhysicsBackend {
  const _Named(this.name);
  @override
  final String name;
}
