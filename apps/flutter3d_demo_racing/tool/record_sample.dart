/// `tpl-02`'s own sample recording: `site/assets/samples/racing.f3drun`,
/// built from the exact staging and drive `test/demo_test.dart` already
/// proves round-trips — this script only adds the write.
///
/// A `flutter test`-shaped generator rather than `dart run`, for the reason
/// `rp-05`'s own row now documents at length: `flutter3d_game_racing` names
/// `flutter: sdk: flutter`, and plain `dart run` fails compiling the
/// framework itself before this file's own code ever runs.
///
///     flutter test tool/record_sample.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_racing/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;
const int _steps = 600;

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

/// The same four lines as `main.dart`'s private `_readDriver`, reproduced
/// the way `demo_test.dart` already does.
void _readDriver(RacingSimulation sim, InputState input) {
  final driven = sim.inputs[0];
  driven
    ..throttle = input.value(_throttle)
    ..brake = input.value(_brake)
    ..handbrake = input.held(_handbrake)
    ..steer = input.value(_right) - input.value(_left);
}

/// The same drive `demo_test.dart` plays — every kind of input the tape
/// carries, not a lap anybody would post.
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

void main() {
  test('records site/assets/samples/racing.f3drun', () {
    final levelHash = contentDigestHex(_shippedJson());
    final live = _stage();
    final start = live.sim.save();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    final checkpoints = DigestTrace();
    for (var i = 0; i < _steps; i++) {
      _play(live.input, i);
      recorder.record(live.input);
      _readDriver(live.sim, live.input);
      live.sim.step(_dt);
      checkpoints.observe(recorder.tape.steps, live.sim.save().toJson());
      live.input.endStep();
    }

    final demo = Demo(
      level: 'assets/tracks/ring.json',
      levelHash: levelHash,
      start: start,
      tape: recorder.tape,
      buildStamp: 'tpl-02-sample',
      checkpoints: checkpoints,
    );

    final outFile = File('../../site/assets/samples/racing.f3drun');
    outFile.writeAsStringSync(jsonEncode(demo.toJson()));
    // ignore: avoid_print
    print('wrote ${outFile.path} (${outFile.lengthSync()} bytes)');
  });
}
