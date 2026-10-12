/// `N3` for the Ascent: a `.f3drun` played through the renderer on a real
/// device, a step a frame, and every frame timed.
///
///     tool/pacing.sh --demo platformer            # macOS, from the root
///     tool/pacing.sh --demo platformer -d <device-id> --label a55-platformer
///
/// Run through `flutter drive --profile` by that script, which hands the run
/// in as `FLUTTER3D_PACING_RUN` (the file's contents, through
/// `--dart-define-from-file`: a sandboxed desktop app and a phone can read
/// neither the repository nor the host's disk) and writes what this reports
/// into the report kept in the repository. The dungeon's
/// `integration_test/pacing_test.dart` is the same harness for the crypt.
///
/// **The level the game plays, drawn the way the game draws it**: `openLevel`
/// and `stage`, the penguin dressed before the first frame, the follow camera,
/// the level's sky and low fog, three cascades of 2048. What it leaves out is
/// the presentation layered on top: the runner's squash and lean, particles,
/// sound and the HUD.
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
import 'package:flutter3d_demo_platformer/src/air.dart';
import 'package:flutter3d_demo_platformer/src/lens.dart';
import 'package:flutter3d_demo_platformer/src/run.dart';
import 'package:flutter3d_demo_platformer/src/runner_visuals.dart';
import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show FixtureVisuals;
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The run, gzipped and in base64: the Ascent's saves carry its water, and
/// at 600 KB the plain file is more than a build can be handed in a define.
const String _runGzip = String.fromEnvironment('FLUTTER3D_PACING_RUN_GZIP');
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

/// Timed passes of the tape. Three passes of the 600-step sample is thirty
/// seconds of play.
const int _repeats = int.fromEnvironment(
  'FLUTTER3D_PACING_REPEATS',
  defaultValue: 3,
);

/// Passes played before the timed ones and not counted: the numbers of a
/// level that has been running, not of its first minute.
const int _warmUp = int.fromEnvironment('FLUTTER3D_PACING_WARMUP');

/// `RenderSettings.frameWorkBudget` for the run, in microseconds.
const int _budget = int.fromEnvironment('FLUTTER3D_PACING_BUDGET');

/// The model the game dresses the runner in; `main.dart`'s `_runnerModel`.
const String _runnerModel = 'assets_src/models/penguin.glb';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a recorded run, frame by frame', (WidgetTester tester) async {
    expect(
      _runGzip,
      isNotEmpty,
      reason:
          'no run to play: tool/pacing.sh passes one as '
          'FLUTTER3D_PACING_RUN_GZIP',
    );
    final demo = Demo.fromJson(
      jsonDecode(utf8.decode(gzip.decode(base64.decode(_runGzip))))
          as Map<String, Object?>,
    );

    final device = await openDevice(width: _width, height: _height);
    final ascent = await _AscentReplay.open(demo, device: device);
    final renderer = Renderer.create(device: device);
    final settings = ascent.settings(frameWorkBudget: _budget);
    final views = ascent.views();

    // The loading screen's work, done before the first timed frame: the
    // penguin and the fixtures are in the scene and every pipeline they need
    // is linked, so a spike below is a spike of play and not of a cold start.
    ascent
      ..rewind(demo)
      ..placeCamera(0.0);
    renderer.warmUp(
      width: _width,
      height: _height,
      scene: ascent.scene,
      views: views,
      settings: settings,
    );
    await gpuSettled(device);

    Future<void> drawFrame(int frame) async {
      ascent.placeCamera(_dt);
      renderer.render(
        width: _width,
        height: _height,
        scene: ascent.scene,
        views: views,
        settings: settings,
      );
      await gpuSettled(device);
    }

    if (_warmUp > 0) {
      await replayPacing(
        demo: demo,
        input: ascent.input,
        repeats: _warmUp,
        rewind: () => ascent.rewind(demo),
        onStep: ascent.step,
        drawFrame: drawFrame,
      );
    }
    final pacing = await replayPacing(
      demo: demo,
      input: ascent.input,
      repeats: _repeats,
      rewind: () => ascent.rewind(demo),
      onStep: ascent.step,
      drawFrame: drawFrame,
    );

    binding.reportData = <String, Object?>{
      'pacing': <String, Object?>{
        ...pacing.toJson(),
        'millis': <double>[
          for (final seconds in pacing.seconds)
            (seconds * 1e6).roundToDouble() / 1000.0,
        ],
      },
      'about': <String, Object?>{
        'run': _runName,
        'steps': demo.tape.frames.length,
        'repeats': _repeats,
        'warmUpPasses': _warmUp,
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

const double _dt = 1.0 / 60.0;

/// The level a run was recorded in, loaded and staged the way
/// `PlatformerRun` does it, with the runner dressed and a camera following.
final class _AscentReplay {
  _AscentReplay._(
    this.loaded,
    this.staged,
    this.fixtures,
    this.visuals,
    this.input,
  ) : follow = FollowCamera(world: loaded.collision);

  static Future<_AscentReplay> open(
    Demo demo, {
    required GraphicsDevice device,
  }) async {
    // On the backend it was recorded on: the two are not promised to agree.
    await startPhysics(asked: demo.physics ?? askedPhysics);
    final input = InputState();
    final (:kinds, :loaded, :fixtures) = await openLevel(
      demo.level,
      device: device,
    );
    final staged = stage(
      loaded.level,
      loaded.collision,
      input: input,
      registry: kinds,
      onFixture: fixtures.add,
    );
    loaded.collision.update();
    final visuals = RunnerVisuals(model: _runnerModel)
      ..box(device, loaded.scene, staged.runner);
    // Awaited, unlike the game: the frames timed are the ones a player sees
    // after the model has arrived, and the coins and gates are models too.
    await visuals.dress(
      device,
      loaded.scene,
      staged.runner,
      stillWanted: () => true,
      onArrived: () {},
    );
    await fixtures.settled;
    return _AscentReplay._(loaded, staged, fixtures, visuals, input);
  }

  final LoadedLevel loaded;
  final Staged staged;
  final FixtureVisuals fixtures;
  final RunnerVisuals visuals;

  /// What the tape is played into.
  final InputState input;

  final FollowCamera follow;
  final CameraNode camera = CameraNode(projection: ascentLens.base);
  double _elapsed = 0.0;

  Scene get scene => loaded.scene;

  /// Puts the run back where [demo] starts, and the camera on the runner.
  ///
  /// `sim.cameraYaw` stays where the recording left it: the game turns it
  /// with the camera, and a tape played against another yaw is another run.
  void rewind(Demo demo) {
    staged.sim.restore(demo.start);
    _elapsed = 0.0;
    follow.cut();
  }

  /// One whole step of the run: the simulation's, then the water's and
  /// the fires'.
  void step(double dt) {
    staged.step(dt);
    _elapsed += dt;
  }

  /// The runner where the simulation left them, the fixtures in step, and
  /// the camera following, [dt] seconds after the last placement.
  void placeCamera(double dt) {
    final runner = staged.runner;
    final at = runner.body.position;
    follow.follow(at, dt, traveling: runner.body.velocity);
    fixtures.sync(_elapsed);
    // By the feet, as the game places the model.
    visuals.node?.setPosition(
      at.x,
      at.y - runner.body.halfExtents.y - visuals.modelFloor,
      at.z,
    );
    camera
      ..setPositionFrom(follow.eye)
      ..lookAt(follow.target)
      ..projection = ascentLens.widened(follow.extraFovY);
    if (camera.parent == null) scene.add(camera);
  }

  /// What the game draws every frame with: the level's sky and fog and its
  /// three cascades. [frameWorkBudget] is `RenderSettings.frameWorkBudget`.
  RenderSettings settings({int frameWorkBudget = 0}) => RenderSettings(
    fog: levelFog(loaded.level),
    sky: levelSky(loaded.level),
    shadows: const ShadowSettings(cascades: 3, resolution: 2048),
    frameWorkBudget: frameWorkBudget,
  );

  List<RenderView> views() => <RenderView>[RenderView(camera: camera)];
}
