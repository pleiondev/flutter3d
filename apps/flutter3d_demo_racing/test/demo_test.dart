/// A lap through the shipped circuit, written down and played back to the
/// same bytes and the same checkpoints.
///
///     flutter test test/demo_test.dart
///
/// The `rp-01` round trip, on the game that ships rather than on a bare car:
/// the track as authored, the race state, the dice the snapshot carries. See
/// `apps/flutter3d_demo_dungeon/test/demo_test.dart` for the sibling this
/// mirrors and the reason it lives in the app rather than the package — the
/// shipped track lives here, not there.
///
/// **The tape is a keyboard's, not the car's.** `RacingSimulation` reads a
/// `VehicleInput` — throttle, brake, steer, all doubles — but that is not what
/// a `.f3drun` carries; `_readDriver` in `main.dart` is the four lines that
/// turn `InputState` into it, reproduced here rather than imported because it
/// is private. Recording the analogue result instead would be the racer's own
/// counter-example from `flutter3d_game_racing/test/parity_test.dart` in a
/// different shape: a document that skipped the translation layer would stop
/// proving anything about it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_racing/src/circuits.dart';
import 'package:flutter3d_demo_racing/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _handbrake = GameAction('handbrake');

Map<String, Object?> _shippedJson([String circuit = 'ring']) =>
    jsonDecode(File('assets/tracks/$circuit.json').readAsStringSync())
        as Map<String, Object?>;

TrackDocument _shipped([String circuit = 'ring']) =>
    TrackDocument.fromJson(_shippedJson(circuit));

({RacingSimulation sim, InputState input}) _stage() {
  final document = _shipped();
  final world = CollisionWorld();
  document.level?.addTo(world);
  final input = InputState();
  final staged = stage(document, world, cars: 1, laps: 1);
  return (sim: staged.sim, input: input);
}

/// The same four lines as `main.dart`'s private `_readDriver`.
void _readDriver(RacingSimulation sim, InputState input) {
  final driven = sim.inputs[0];
  driven
    ..throttle = input.value(_throttle)
    ..brake = input.value(_brake)
    ..handbrake = input.held(_handbrake)
    ..steer = input.value(_right) - input.value(_left);
}

/// A drive that touches throttle, brake, both steering directions and the
/// handbrake — not a lap anybody would post, a run that reaches every kind of
/// input the tape carries.
///
/// **Always `setActionValue`, never `clearActionValue`, for a value that
/// changes over the run.** `InputTapePlayback._apply` only ever sets a value a
/// frame names; it has no way to say "and this one let go", the same way a
/// polled analogue device — the pad trigger `_readDriver` is written for —
/// never stops reporting once it is live. `clearActionValue` is for a
/// disconnection, not a release, and using it here for "not pressed right
/// now" recorded a value on the way down that the replay then had nothing to
/// take back — found by this test diverging the first time it ran.
void _play(InputState input, int step) {
  input.setActionValue(_throttle, step % 40 < 30 ? 1.0 : 0.0);
  input.setActionValue(
    _brake,
    (step % 200 >= 150 && step % 200 < 170) ? 0.6 : 0.0,
  );
  final steeringRight = step % 80 < 40;
  input.setActionValue(_right, steeringRight ? 0.4 : 0.0);
  input.setActionValue(_left, steeringRight ? 0.0 : 0.4);
  if (step == 300) input.press(_handbrake);
  if (step == 305) input.release(_handbrake);
}

String _bytes(Snapshot snapshot) => jsonEncode(snapshot.toJson());

void main() {
  test('a lap of the shipped circuit replays to the same snapshot and '
      'digests', () {
    const steps = 600;
    // `TrackDocument` has no `toJson()` — reads only — so the document's own
    // JSON, straight off disk, is what is hashed; the parsed object is what
    // is staged.
    final levelHash = contentDigestHex(_shippedJson());

    final live = _stage();
    final start = live.sim.save();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    final liveCheckpoints = DigestTrace();
    for (var i = 0; i < steps; i++) {
      _play(live.input, i);
      recorder.record(live.input);
      _readDriver(live.sim, live.input);
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
        level: 'assets/tracks/ring.json',
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
      _readDriver(replay.sim, replay.input);
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
