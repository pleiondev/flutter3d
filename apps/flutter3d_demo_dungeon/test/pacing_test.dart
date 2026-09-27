/// `N3`'s harness on the shipped sample run, with no GPU.
///
///     flutter test test/pacing_test.dart
///
/// `tool/pacing.sh` plays `site/assets/samples/shooter.f3drun` through
/// Impeller from `integration_test/pacing_test.dart`, and a number from there
/// means something only if the tape is really being played: a run that no
/// longer fits the crypt would leave the player at the entrance and time two
/// hundred frames of one view. So this plays the same file through the same
/// [CryptReplay] on the software rasteriser and checks the player walks,
/// then through `replayPacing` to see that every step of the tape became a
/// drawn, timed frame.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_dungeon/src/replay_stage.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sample = '../../site/assets/samples/shooter.f3drun';
const double _dt = 1.0 / 60.0;

Demo _demo() => Demo.fromJson(
  jsonDecode(File(_sample).readAsStringSync()) as Map<String, Object?>,
);

Future<CryptReplay> _crypt() async {
  final it = cpuTestDevice(width: 32, height: 20);
  return CryptReplay.open(
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the sample run walks the player across the crypt', () async {
    final demo = _demo();
    final crypt = await _crypt()
      ..rewind(demo);
    final from = crypt.level.staged.player.body.position.clone();
    final playback = InputTapePlayback(demo.tape);
    var step = 0;
    while (!playback.isFinished) {
      playback.applyTo(crypt.input);
      crypt.step(_dt);
      step++;
      crypt.input.endStep();
    }
    expect(step, demo.tape.frames.length);
    // Fifteen metres from the entrance, measured: the walk the numbers are
    // of. Not the recording's own checkpoints — the sample was recorded in
    // `flutter3d_sim_mcp`'s headless crypt, staged by the shooter package
    // rather than by this game, and the two part at the first checkpoint.
    expect(
      crypt.level.staged.player.body.position.distanceTo(from),
      greaterThan(10.0),
    );
  });

  test('every step of the tape is a drawn and timed frame', () async {
    final demo = _demo();
    final crypt = await _crypt();
    var draws = 0;
    final pacing = await replayPacing(
      demo: demo,
      input: crypt.input,
      rewind: () => crypt.rewind(demo),
      onStep: crypt.step,
      drawFrame: (frame) async {
        final result = crypt.draw(width: 32, height: 20);
        expect(result.drawCalls, greaterThan(0));
        draws++;
        await gpuSettled(crypt.renderer.device);
      },
    );
    expect(draws, demo.tape.frames.length);
    expect(pacing.frames, demo.tape.frames.length);
    expect(pacing.max, greaterThan(0.0));
  });

  test('warmed up the way the harness warms up, the first frames of play '
      'capture no probe and make no target', () async {
    // What the pacing run found on macOS: frames one to three of the first
    // pass at over a hundred milliseconds, after a warm-up that had linked
    // every pipeline. The crypt's four probes were still standing one a
    // frame, and the pool had nothing to lend the frames after the warm-up.
    final demo = _demo();
    final crypt = await _crypt();
    final settings = crypt.settings();
    await crypt.settled();
    crypt
      ..rewind(demo)
      ..placeCamera();
    crypt.renderer.warmUp(
      width: 32,
      height: 20,
      scene: crypt.level.loaded.scene,
      views: crypt.views(),
      settings: settings,
    );
    final probes = crypt.level.loaded.scene.probes;
    expect(probes, hasLength(greaterThan(1)), reason: 'one per room');
    expect(probes.where((p) => !p.isCaptured), isEmpty);

    final made = crypt.renderer.targetPool.createdCount;
    final playback = InputTapePlayback(demo.tape);
    for (var frame = 0; frame < 6; frame++) {
      playback.applyTo(crypt.input);
      crypt.step(_dt);
      crypt.input.endStep();
      crypt.draw(width: 32, height: 20, settings: settings);
    }
    expect(crypt.renderer.targetPool.createdCount, made);
  });
}
