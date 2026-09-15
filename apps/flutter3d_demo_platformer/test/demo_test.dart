/// A run through the shipped level, written down and played back to the same
/// bytes and the same checkpoints.
///
///     flutter test test/demo_test.dart
///
/// The `rp-01` round trip, on the game that ships rather than on a toy: the
/// level as authored, the runner's coyote time and double jump, the dice the
/// snapshot carries. See `apps/flutter3d_demo_dungeon/test/demo_test.dart` for
/// the sibling this mirrors and the reason it exists in the app rather than in
/// the package — the shipped level lives here, not there.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;

Level _shipped() => Level.fromJson(
  jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
      as Map<String, Object?>,
);

({PlatformerSimulation sim, InputState input}) _stage() {
  final level = _shipped();
  final world = CollisionWorld();
  level.addTo(world);
  final input = InputState();
  final staged = stage(level, world, input: input, registry: platformerRegistry());
  world.update();
  return (sim: staged.sim, input: input);
}

/// A route that touches forward movement, jumping and the drop-through key —
/// not a route to anywhere in particular, a run that reaches every kind of
/// input the tape carries.
void _play(InputState input, int step) {
  if (step % 30 < 22) {
    input.press(GameAction.moveForward);
  } else {
    input.release(GameAction.moveForward);
  }
  if (step % 60 == 0) input.press(GameAction.jump);
  if (step % 60 == 3) input.release(GameAction.jump);
  if (step % 90 == 45) input.press(PlatformerActions.dropThrough);
  if (step % 90 == 46) input.release(PlatformerActions.dropThrough);
}

String _bytes(Snapshot snapshot) => jsonEncode(snapshot.toJson());

void main() {
  test('a run through the shipped level replays to the same snapshot and '
      'digests', () {
    const steps = 600;
    final levelHash = _shipped().digestHex;

    final live = _stage();
    final start = live.sim.save();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    final liveCheckpoints = DigestTrace();
    for (var i = 0; i < steps; i++) {
      _play(live.input, i);
      recorder.record(live.input);
      live.sim.step(_dt);
      liveCheckpoints.observe(recorder.tape.steps, live.sim.save().toJson());
      live.input.endStep();
    }
    final ending = _bytes(live.sim.save());
    expect(
      ending,
      isNot(_bytes(start)),
      reason: 'a run in which nothing happened would prove nothing',
    );

    final sent = jsonEncode(
      Demo(
        level: 'assets/levels/ascent.json',
        levelHash: levelHash,
        start: start,
        tape: recorder.tape,
        buildStamp: 'test-build',
        checkpoints: liveCheckpoints,
      ).toJson(),
    );
    final demo = Demo.fromJson(jsonDecode(sent) as Map<String, Object?>);
    expect(demo.steps, steps);
    expect(demo.levelHash, levelHash);

    final replay = _stage();
    replay.sim.restore(demo.start);
    final playback = InputTapePlayback(demo.tape);
    final replayCheckpoints = DigestTrace();
    var replayedSteps = 0;
    while (!playback.isFinished) {
      playback.applyTo(replay.input);
      replay.sim.step(_dt);
      replayedSteps++;
      replayCheckpoints.observe(replayedSteps, replay.sim.save().toJson());
      replay.input.endStep();
    }

    expect(_bytes(replay.sim.save()), ending);
    expect(
      replayCheckpoints.divergenceFromHex(demo.checkpoints.hexDigests),
      isNull,
      reason:
          'the replay should check out against the document\'s own trace, '
          'not only end at the same byte',
    );
  });
}
