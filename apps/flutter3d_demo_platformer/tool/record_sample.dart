/// `tpl-02`'s own sample recording: `site/assets/samples/platformer.f3drun`,
/// built from the exact staging and route `test/demo_test.dart` already
/// proves round-trips — this script only adds the write.
///
/// `N5`: the same bytes go to `test/tapes/ascent.f3drun`, which
/// `test/replay_test.dart` replays. One recording in two places rather than
/// the test reading the site's, so the game's tests do not reach outside the
/// game; and one script, so the two cannot be recorded from different runs.
///
/// A `flutter test`-shaped generator rather than `dart run`, for the reason
/// `rp-05`'s own row now documents at length: `flutter3d_game_platformer`
/// names `flutter: sdk: flutter`, and plain `dart run` fails compiling the
/// framework itself before this file's own code ever runs.
///
///     flutter test tool/record_sample.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show usePhysics;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;
const int _steps = 600;

Level _shipped() => Level.fromJson(
  jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
      as Map<String, Object?>,
);

({PlatformerSimulation sim, InputState input}) _stage() {
  final level = _shipped();
  final world = CollisionWorld();
  level.addTo(world);
  final input = InputState();
  final staged = stage(
    level,
    world,
    input: input,
    registry: platformerRegistry(),
  );
  world.update();
  return (sim: staged.sim, input: input);
}

/// The same route `demo_test.dart` plays — every kind of input the tape
/// carries, not a route to anywhere in particular.
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

void main() {
  test('records site/assets/samples/platformer.f3drun and the replay '
      "test's tape", () {
    final levelHash = _shipped().digestHex;
    final live = _stage();
    final start = live.sim.save();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    final checkpoints = DigestTrace();
    for (var i = 0; i < _steps; i++) {
      _play(live.input, i);
      recorder.record(live.input);
      live.sim.step(_dt);
      checkpoints.observe(recorder.tape.steps, live.sim.save().toJson());
      live.input.endStep();
    }

    final demo = Demo(
      level: 'assets/levels/ascent.json',
      levelHash: levelHash,
      start: start,
      tape: recorder.tape,
      buildStamp: 'tpl-02-sample',
      checkpoints: checkpoints,
      // What it replays on: see `Demo.physics`.
      physics: usePhysics().name,
    );

    final json = jsonEncode(demo.toJson());
    for (final path in <String>[
      '../../site/assets/samples/platformer.f3drun',
      'test/tapes/ascent.f3drun',
    ]) {
      final outFile = File(path)..writeAsStringSync(json);
      // ignore: avoid_print
      print('wrote ${outFile.path} (${outFile.lengthSync()} bytes)');
    }
  });
}
