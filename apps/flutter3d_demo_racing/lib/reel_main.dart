/// The release reel's racing shot, filmed frame by frame: a car driving fast
/// through a ford on a circuit at dusk, throwing its wake and spray, past a
/// wreck burning beside the track; the camera tracking low beside the car.
///
///     flutter run -d macos --profile -t lib/reel_main.dart \
///       --dart-define=REEL_OUT=/path/to/reel
///
/// Writes `$REEL_OUT/racing_ford/frame_%04d.png`, 1280 × 720, a frame every
/// thirtieth of a second of the game's time, and exits.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_game_ui/capture.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show preparePhysics, usePhysics;
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'src/backend.dart';
import 'src/circuits.dart';
import 'src/elements.dart';
import 'src/looks.dart';
import 'src/roadside.dart';
import 'src/staging.dart';

const double _dt = reelFrameStep;

/// The shot's length and its warm-up, in steps.
const int _frames = 240, _warmUp = 90;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preparePhysics();
  runApp(const ColoredBox(color: Colors.black));
  // After the first frame, so the GPU context is up.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final written = await _ford();
      stdout.writeln('racing_ford: $written frames');
      exit(0);
    } catch (error, stack) {
      stderr.writeln('racing_ford: $error\n$stack');
      exit(1);
    }
  });
}

/// A circuit opened as the game opens one, at its own hour.
final class _Circuit {
  _Circuit(this.scene, this.staged, this.sky, this.elements, this.cars);

  final Scene scene;
  final Staged staged;
  final SkyPreset sky;
  final TrackElements elements;
  final List<({SphereVehicle car, SceneNode node, double lift})> cars;
}

Future<_Circuit?> _open(
  GraphicsDevice device,
  Renderer renderer,
  Circuit circuit,
) async {
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
  final staged = stage(document, loaded.collision);
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
  final elements = await TrackElements.open(
    device: device,
    scene: scene,
    renderer: renderer,
    track: staged.track,
    cars: staged.cars,
    sky: document.sky,
    load: rootBundle.load,
  );
  if (elements == null || elements.waterAlong.isEmpty) {
    elements?.dispose();
    return null;
  }
  ModelAsset? asset;
  try {
    asset = await ModelAsset.fromDocument(
      await loadModelAsset(kCarModel),
      device: device,
      name: kCarModel,
    );
  } on Object {
    asset = null;
  }
  final floor = asset == null ? 0.0 : -asset.localBounds.min.y;
  final cars = <({SphereVehicle car, SceneNode node, double lift})>[];
  for (var i = 0; i < staged.cars.length; i++) {
    final car = staged.cars[i];
    final SceneNode node;
    final double lift;
    if (asset == null) {
      node = carBox(device, Looks.rival(i), name: 'car-$i');
      scene.add(node);
      lift = liftFor(car);
    } else {
      final instance = asset.instantiate(
        scene,
        name: 'car-$i',
        shareMaterials: false,
      );
      Looks.paint(instance.meshes, Looks.carPaint(i));
      node = instance.root;
      lift = floor - car.tuning.rideHeight;
    }
    cars.add((car: car, node: node, lift: lift));
  }
  scene.ambientIntensity =
      document.sky.ambientIntensity * Photometric.legacyUnit;
  if (EnvironmentMap.isSupportedOn(device)) {
    final environment = EnvironmentMap.fromSky(device, _skyOf(document.sky));
    scene
      ..environment = environment.texture
      ..environmentLevels = environment.levels;
  }
  return _Circuit(scene, staged, document.sky, elements, cars);
}

SkySettings _skyOf(SkyPreset sky) => SkySettings(
  enabled: true,
  zenith: sky.zenith.toLinearColor(),
  horizon: sky.horizon.toLinearColor(),
  nadir: sky.belowHorizon.toLinearColor(),
  directionToSun: sky.directionToSun,
  sunColor: sky.sunColor.toLinearColor(),
  glowExponent: sky.glowWide,
  glowStrength: sky.glowStrength,
  sunIntensity: sky.sunDisc,
);

/// What the game draws with, looking along [gaze].
RenderSettings _settings(SkyPreset sky, Vector3 gaze) => RenderSettings(
  fog: FogSettings(
    color: sky.inScatterAlong(gaze).toLinearColor(),
    density: sky.fogDensity,
  ),
  exposure: sky.exposure,
  sky: _skyOf(sky),
  shadows: const ShadowSettings(
    cascades: kShadowCascades,
    resolution: kShadowResolution,
  ),
);

/// The shot: returns how many frames it wrote.
Future<int> _ford() async {
  final device = await openDevice(width: 1280, height: 720);
  final renderer = Renderer.create(device: device);
  final reel = Reel(renderer: renderer, out: _reelOut);
  // The dusk circuit first; any other with water if it has none.
  const order = <String>['ridge', 'gorge', 'flats', 'ring', 'quarry'];
  _Circuit? circuit;
  for (final name in order) {
    final c = Season.circuits.firstWhere((c) => c.name == name);
    circuit = await _open(device, renderer, c);
    if (circuit != null) break;
  }
  if (circuit == null) throw StateError('no circuit has water');
  final staged = circuit.staged;
  final track = staged.track;
  final cars = staged.cars;
  final ford = circuit.elements.waterAlong.first;
  final frame = TrackFrame();

  // The player some way back from the ford, at speed; the AI drives it.
  final start = track.center.wrap(ford - 170.0);
  track.frameAt(start, frame);
  cars[0].placeAt(
    frame.position.clone()..y += 0.6,
    math.atan2(frame.forward.x, frame.forward.z),
    trackDistance: start,
  );
  cars[0].velocity.setFrom(frame.forward * 30.0);

  // A wreck on the verge past the ford, left by a rival stood there, which
  // then goes back to the grid.
  final wreckAt = track.center.wrap(ford + 45.0);
  track.frameAt(wreckAt, frame);
  final halfWidth = track.widthAt(wreckAt) / 2.0;
  final side = 1.0;
  final verge = frame.position + frame.right * (side * (halfWidth + 1.5));
  final home = cars[1].position.clone();
  final homeYaw = cars[1].headingYaw;
  final homeAlong = cars[1].trackDistance;
  cars[1].placeAt(
    verge.clone()..y += 0.6,
    math.atan2(frame.forward.x, frame.forward.z),
    trackDistance: wreckAt,
  );
  circuit.elements.wreckNow(1);
  final wreck = verge.clone()..y += 1.0;
  cars[1].placeAt(home, homeYaw, trackDistance: homeAlong);

  final camera = CameraNode(
    projection: const PerspectiveProjection(fovY: 0.9, near: 0.3, far: 1600.0),
  );
  circuit.scene.add(camera);
  final gaze = Vector3(0.0, 0.0, 1.0);
  Vector3? held;

  void step() {
    staged.ai.drive(cars[0], staged.sim.inputs[0], others: cars);
    staged.sim.step(_dt);
    circuit!.elements.stepped(_dt);
    for (final c in circuit.cars) {
      final at = c.car.position + c.car.visualBasis.getColumn(1) * c.lift;
      c.node
        ..setPositionFrom(at)
        ..setRotation(Quaternion.fromRotation(c.car.visualBasis));
    }
  }

  void aim(double t) {
    final car = cars[0];
    final right = car.visualBasis.getColumn(0);
    final up = car.visualBasis.getColumn(1);
    final forward = car.visualBasis.getColumn(2);
    // Low beside the car, on the side away from the wreck, a little behind
    // its nose; easing in from further back at the start.
    final come = reelEase(t / 0.15);
    final tracking =
        car.position +
        right * (-side * (3.2 + 2.0 * (1.0 - come))) +
        up * 0.55 -
        forward * (1.0 + 3.0 * (1.0 - come));
    // From two thirds in, the camera slows to a stop and turns from the car
    // to the wreck burning on the far verge.
    final hold = reelEase((t - 0.62) / 0.3);
    if (t >= 0.62 && held == null) held = tracking.clone();
    final eye = held == null ? tracking : tracking + (held! - tracking) * hold;
    final onCar = car.position + forward * 2.5 + up * 0.3;
    final target = onCar + (wreck - onCar) * hold;
    camera
      ..setPositionFrom(eye)
      ..lookAt(target);
    gaze
      ..setFrom(target)
      ..sub(eye);
  }

  for (var i = 0; i < _warmUp; i++) {
    step();
    aim(0.0);
    circuit.elements.frame(
      _dt,
      eye: camera.readWorldPosition(),
      progress: staged.race.progress,
    );
  }
  final shot = reel.shot('racing_ford');
  for (var f = 0; f < _frames; f++) {
    step();
    aim(f / (_frames - 1));
    circuit.elements.frame(
      _dt,
      eye: camera.readWorldPosition(),
      progress: staged.race.progress,
    );
    final sky = circuit.sky.colorAt(gaze);
    await shot.film(
      scene: circuit.scene,
      camera: camera,
      settings: _settings(circuit.sky, gaze),
      clearColorSrgb: Vector4(sky.x, sky.y, sky.z, 1.0),
    );
  }
  return _frames;
}

/// Where the frames go: `--dart-define=REEL_OUT=<dir>`, or `reel` in the
/// working directory.
const String _reelOut = String.fromEnvironment(
  'REEL_OUT',
  defaultValue: 'reel',
);
