/// `N3`: a `.f3drun` played through the renderer on a real device, a step a
/// frame, and every frame timed.
///
///     tool/pacing.sh                       # macOS, from the repository root
///     tool/pacing.sh -d <device-id> --label a55
///
/// Run through `flutter drive --profile` by that script, which hands the run
/// in as `FLUTTER3D_PACING_RUN` (the file's contents, through
/// `--dart-define-from-file`: a sandboxed desktop app and a phone can read
/// neither the repository nor the host's disk) and writes what this reports
/// into the report kept in the repository.
///
/// **This does not fail on a spike.** `integrationDriver` hands its data to
/// the host only when every test passed, and a report of the run that went
/// wrong is the one worth having; the script reads the numbers and fails.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_demo_dungeon/src/replay_stage.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _run = String.fromEnvironment('FLUTTER3D_PACING_RUN');
const String _runName = String.fromEnvironment(
  'FLUTTER3D_PACING_RUN_NAME',
  defaultValue: 'run',
);
const int _width = int.fromEnvironment(
  'FLUTTER3D_PACING_WIDTH',
  defaultValue: 1280,
);
const int _height = int.fromEnvironment(
  'FLUTTER3D_PACING_HEIGHT',
  defaultValue: 720,
);

/// Three passes of a 220-step sample is eleven seconds of play: enough
/// frames for a 99th percentile to be more than the one worst frame.
const int _repeats = int.fromEnvironment(
  'FLUTTER3D_PACING_REPEATS',
  defaultValue: 3,
);

/// `RenderSettings.frameWorkBudget` for the run, in microseconds.
const int _budget = int.fromEnvironment('FLUTTER3D_PACING_BUDGET');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a recorded run, frame by frame', (WidgetTester tester) async {
    expect(
      _run,
      isNotEmpty,
      reason:
          'no run to play: tool/pacing.sh passes one as FLUTTER3D_PACING_RUN',
    );
    final demo = Demo.fromJson(jsonDecode(_run) as Map<String, Object?>);

    final device = await openDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: device);
    final crypt = await CryptReplay.open(device: device, renderer: renderer);
    final settings = crypt.settings(frameWorkBudget: _budget);

    // The loading screen's work, done where the game does it: every
    // pipeline the level needs is linked before the first timed frame, so a
    // spike below is a spike of play and not of a cold start.
    crypt
      ..rewind(demo)
      ..placeCamera();
    renderer.warmUp(
      width: _width,
      height: _height,
      scene: crypt.level.loaded.scene,
      views: <RenderView>[RenderView(camera: crypt.camera)],
      settings: settings,
    );
    await gpuSettled(device);

    final pacing = await replayPacing(
      demo: demo,
      input: crypt.input,
      repeats: _repeats,
      rewind: () => crypt.rewind(demo),
      onStep: crypt.step,
      drawFrame: (frame) async {
        crypt.draw(width: _width, height: _height, settings: settings);
        await gpuSettled(device);
      },
    );

    binding.reportData = <String, Object?>{
      'pacing': <String, Object?>{
        ...pacing.toJson(),
        'millis': <double>[
          for (final ms in pacing.millis)
            (ms * 1000.0).roundToDouble() / 1000.0,
        ],
      },
      'about': <String, Object?>{
        'run': _runName,
        'steps': demo.tape.frames.length,
        'repeats': _repeats,
        'width': _width,
        'height': _height,
        'frameWorkBudget': _budget,
        'device': device.runtimeType.toString(),
        'os':
            '${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}',
        'mode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
      },
    };
  });
}
