/// `N3` for the circuit: a `.f3drun` played through the renderer on a real
/// device, a step a frame, and every frame timed.
///
///     tool/pacing.sh --demo racing                # macOS, from the root
///     tool/pacing.sh --demo racing -d <device-id> --label a55-racing
///
/// Run through `flutter drive --profile` by that script, which hands the run
/// in as `FLUTTER3D_PACING_RUN` (the file's contents, through
/// `--dart-define-from-file`: a sandboxed desktop app and a phone can read
/// neither the repository nor the host's disk) and writes what this reports
/// into the report kept in the repository. The dungeon's
/// `integration_test/pacing_test.dart` is the same harness for the crypt.
///
/// **The circuit the game races, drawn the way the game draws it**: the
/// scenery through `LevelLoader`, the road and barriers from the spline, the
/// sheds and signs, the car's model, the chase camera, the hour's sky, haze,
/// exposure and shadow cascades. What it leaves out is the presentation on
/// top: the player's reflection probe, the ghost, particles, sound and the
/// HUD. One car, because the tape was recorded with one.
///
/// **This does not fail on a spike.** `integrationDriver` hands its data to
/// the host only when every test passed, and a report of the run that went
/// wrong is the one worth having; the script reads the numbers and fails.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, kProfileMode, kReleaseMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_demo_racing/src/backend.dart'
    show kShadowCascades, kShadowResolution;
import 'package:flutter3d_demo_racing/src/circuits.dart';
import 'package:flutter3d_demo_racing/src/looks.dart';
import 'package:flutter3d_demo_racing/src/roadside.dart';
import 'package:flutter3d_demo_racing/src/staging.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The run, gzipped and in base64, as `tool/pacing_report.dart` hands every
/// run over: a plain one past 64 KiB is not handed over at all.
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
/// seconds of driving.
const int _repeats = int.fromEnvironment(
  'FLUTTER3D_PACING_REPEATS',
  defaultValue: 3,
);

/// Passes played before the timed ones and not counted: the numbers of a
/// race that has been running, not of its first minute.
const int _warmUp = int.fromEnvironment('FLUTTER3D_PACING_WARMUP');

/// `RenderSettings.frameWorkBudget` for the run, in microseconds.
const int _budget = int.fromEnvironment('FLUTTER3D_PACING_BUDGET');

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
    final circuit = await _CircuitReplay.open(demo, device: device);
    final renderer = Renderer.create(device: device);
    final views = circuit.views();

    // The loading screen's work, done before the first timed frame: every
    // model is in the scene and every pipeline it needs is linked, so a spike
    // below is a spike of driving and not of a cold start.
    circuit
      ..rewind(demo)
      ..place(0.0);
    renderer.warmUp(
      width: _width,
      height: _height,
      scene: circuit.scene,
      views: views,
      settings: circuit.settings(
        frameWorkBudget: Duration(microseconds: _budget),
      ),
    );
    await gpuSettled(device);

    Future<void> drawFrame(int frame) async {
      circuit.place(_dt);
      renderer.render(
        width: _width,
        height: _height,
        scene: circuit.scene,
        views: views,
        settings: circuit.settings(
          frameWorkBudget: Duration(microseconds: _budget),
        ),
      );
      await gpuSettled(device);
    }

    if (_warmUp > 0) {
      await replayPacing(
        demo: demo,
        input: circuit.input,
        repeats: _warmUp,
        rewind: () => circuit.rewind(demo),
        onStep: circuit.step,
        drawFrame: drawFrame,
      );
    }
    final pacing = await replayPacing(
      demo: demo,
      input: circuit.input,
      repeats: _repeats,
      rewind: () => circuit.rewind(demo),
      onStep: circuit.step,
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

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _handbrake = GameAction('handbrake');

/// The air the circuit is raced under; `main.dart`'s `_air`.
const PhysicalSky _air = PhysicalSky();

/// The circuit a run was recorded on, loaded the way `main.dart`'s
/// `_loadCircuit` loads it, with one car and a chase camera.
final class _CircuitReplay {
  _CircuitReplay._(
    this.scene,
    this.staged,
    this.sky,
    this.carNode,
    this.lift,
    this.input,
  );

  static Future<_CircuitReplay> open(
    Demo demo, {
    required GraphicsDevice device,
  }) async {
    // On the backend it was recorded on: the two are not promised to agree.
    await startPhysics(asked: demo.physics ?? askedPhysics);
    final circuit = Season.circuits.firstWhere(
      (Circuit c) => c.track == demo.level,
      orElse: () => throw StateError('${demo.level} is no circuit'),
    );
    final document = TrackDocument.fromJson(
      jsonDecode(await rootBundle.loadString(circuit.track))
          as Map<String, Object?>,
    );
    final loaded = await const LevelLoader().load(
      circuit.level,
      device: device,
      physics: usePhysics(),
      registry: EntityRegistry(const <EntityKind>[]),
      sidecars: false,
    );
    final staged = stage(document, loaded.collision, cars: 1, laps: 1);
    final scene = loaded.scene;
    addTrackTo(scene, staged.track, device: device);
    addRoadsideTo(
      scene,
      staged.track,
      device: device,
      ground: loaded.collision,
      buildings: await loadBuildings(device),
      signs: await drawSignFaces(device),
    );
    final sky = document.sky;
    final sunlight = _air.sunlight(sky.directionToSun).toLinearColor();
    for (final light in scene.lights) {
      if (light.type == LightType.directional) light.color = sunlight;
    }

    final car = staged.cars.single;
    final SceneNode carNode;
    final double lift;
    final asset = await _carModel(device);
    if (asset == null) {
      carNode = carBox(device, Looks.rival(0), name: 'player');
      scene.add(carNode);
      lift = liftFor(car);
    } else {
      final instance = asset.instantiate(
        scene,
        name: 'player',
        shareMaterials: false,
      );
      Looks.paint(instance.meshes, Looks.carPaint(0));
      carNode = instance.root;
      lift = -asset.localBounds.min.y - car.tuning.rideHeight;
    }
    return _CircuitReplay._(scene, staged, sky, carNode, lift, InputState());
  }

  static Future<ModelAsset?> _carModel(GraphicsDevice device) async {
    try {
      return await ModelAsset.fromDocument(
        await loadModelAsset(kCarModel),
        device: device,
        name: kCarModel,
      );
    } on Object catch (error) {
      debugPrint('cars: no model, so a box ($error)');
      return null;
    }
  }

  final Scene scene;
  final Staged staged;
  final SkyPreset sky;
  final SceneNode carNode;

  /// How far the car's node sits above the sphere's centre, along the car's
  /// own up.
  final double lift;

  /// What the tape is played into.
  final InputState input;

  final CameraNode camera = CameraNode(
    projection: const PerspectiveProjection(fovY: 1.05, near: 0.3, far: 1600),
  );
  final Vector3 _gaze = Vector3(0.0, 0.0, 1.0);
  final Vector3 _at = Vector3.zero();

  /// Puts the race back where [demo] starts, and the camera behind the car.
  void rewind(Demo demo) {
    staged.sim.restore(demo.start);
    staged.chase.cut();
  }

  /// One step of the race, from the keys the tape holds: `main.dart`'s
  /// `_readDriver`, then the simulation.
  void step(double dt) {
    staged.sim.inputs[0]
      ..throttle = input.value(_throttle)
      ..brake = input.value(_brake)
      ..handbrake = input.held(_handbrake)
      ..steer = input.value(_right) - input.value(_left);
    staged.sim.step(dt);
  }

  /// The car where the simulation left it and the chase camera [dt] seconds
  /// further along.
  void place(double dt) {
    final car = staged.cars.single;
    _at
      ..setFrom(car.position)
      ..addScaled(car.visualBasis.getColumn(1), lift);
    carNode
      ..setPositionFrom(_at)
      ..setRotation(Quaternion.fromRotation(car.visualBasis));
    final chase = staged.chase..follow(car, dt);
    camera
      ..setPositionFrom(chase.eye)
      ..lookAt(chase.target)
      ..projection = PerspectiveProjection(
        fovY: chase.fovY,
        near: 0.3,
        far: 1600,
      );
    if (camera.parent == null) scene.add(camera);
    _gaze
      ..setFrom(chase.target)
      ..sub(chase.eye);
  }

  /// `main.dart`'s `_raceSettings`: the haze along the gaze, the hour's
  /// exposure, the sky and the cascades.
  RenderSettings settings({Duration frameWorkBudget = Duration.zero}) {
    final skySettings = SkySettings(
      enabled: true,
      physical: _air,
      directionToSun: sky.directionToSun,
    );
    return RenderSettings(
      fog: FogSettings(
        color: skySettings
            .sample(Vector3(_gaze.x, 0.0, _gaze.z))
            .toLinearColor(),
        density: sky.fogDensity,
      ),
      exposure: sky.exposure,
      sky: skySettings,
      shadows: const ShadowSettings(
        cascades: kShadowCascades,
        resolution: kShadowResolution,
      ),
      frameWorkBudget: frameWorkBudget,
    );
  }

  List<CameraView> views() => <CameraView>[CameraView(camera: camera)];
}
