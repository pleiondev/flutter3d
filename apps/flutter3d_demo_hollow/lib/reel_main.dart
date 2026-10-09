/// Films the eruption for the release reel: lava welling from the crater
/// and running glowing down the flank, and a bomb from it coming down on a
/// thatched roof that catches.
///
///     flutter run -d macos --profile -t lib/reel_main.dart \
///         --dart-define=REEL_OUT=<dir>
///
/// A first run, not drawn, finds when a bomb first sets a roof alight; the
/// valley is the same every run, so a second one, from the start, is drawn
/// from five seconds before that to three after, at a fixed thirtieth of a
/// second, 1280×720, into `<dir>/lava/frame_NNNN.png`. Then it exits.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game_ui/capture.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeWorld, preparePhysics;

import 'src/looks.dart';
import 'src/staging.dart';
import 'src/terrain.dart';

const double _dt = reelFrameStep;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preparePhysics();
  final device = await openDevice(width: 1280, height: 720);
  final renderer = Renderer.create(device: device);
  final reel = Reel(renderer: renderer, out: _reelOut);
  final looks = await HollowLooks.load(device);
  final frames = await _lava(device, renderer, looks, reel.shot('lava'));
  stdout.writeln('lava: $frames frames');
  final valley = await _valley(device, renderer, looks, reel.shot('valley'));
  stdout.writeln('valley: $valley frames');
  exit(0);
}

final Vector3 _sunAlong = Vector3(0.45, -0.6, -0.65);

/// A valley from the start, with the camera [camera] in its scene.
Future<HollowRun> _open(
  GraphicsDevice device,
  Renderer renderer,
  HollowLooks looks,
  CameraNode camera,
) async {
  final scene = Scene()
    ..ambientIntensity = 0.6 * Photometric.legacyUnit
    ..ambientColor = LinearColor(0.86, 0.88, 0.94)
    ..add(
      LightNode(name: 'sun', intensity: 2.0 * Photometric.legacyUnit)
        ..setLocalForward(_sunAlong),
    )
    ..add(camera);
  final elements =
      await Elements.adopt(
          NativeWorld(),
          device: device,
          renderer: renderer,
          scene: scene,
          load: rootBundle.load,
        )
        ..sun(along: _sunAlong, light: Vector3(2.0, 1.9, 1.75));
  return HollowRun(
    device: device,
    scene: scene,
    elements: elements,
    looks: looks,
  );
}

/// One step of the valley with nobody at the controls.
void _step(HollowRun run) {
  run.crane.work(lift: 0, swing: 0);
  run.car.drive(throttle: 0, turn: 0, hold: false);
  run.step(_dt);
}

/// Which hut's roof is alight, or null.
int? _alight(HollowRun run) {
  final huts = run.village.huts;
  for (var k = 0; k < huts.length; k++) {
    if (run.world.isBurning(huts[k].roof)) return k;
  }
  return null;
}

Future<int> _lava(
  GraphicsDevice device,
  Renderer renderer,
  HollowLooks looks,
  ReelShot shot,
) async {
  // When, and which roof: within the first five minutes, by which the
  // volcano has erupted twice.
  final dry = await _open(device, renderer, looks, CameraNode(name: 'unused'));
  var steps = 0;
  int? hut;
  while (hut == null && steps < 300 * 30) {
    _step(dry);
    steps++;
    hut = _alight(dry);
  }
  dry.dispose();
  if (hut == null) {
    stdout.writeln('lava: no roof caught in five minutes');
    exit(1);
  }
  final camera = CameraNode(name: 'reel');
  final run = await _open(device, renderer, looks, camera);
  final first = math.max(steps - 5 * 30, 0);
  final total = 8 * 30;
  for (var i = 0; i < first; i++) {
    _step(run);
  }
  final roof = run.village.huts[hut].roofTop;
  final crater = run.volcano.crater;
  for (var i = 0; i < total; i++) {
    _place(camera, run, reelEase(i / (total - 1)), crater, roof);
    _step(run);
    await shot.film(scene: run.scene, camera: camera, settings: _settings);
  }
  run.dispose();
  return total;
}

/// The valley a little after the volcano wakes: rafts on the river, the
/// lagoon under the falls, the huts on the bank, and the volcano smoking
/// over them. The eye starts low over the water downstream of the lagoon,
/// looking up the river, and sweeps up it, rising until the volcano stands
/// behind the falls.
Future<int> _valley(
  GraphicsDevice device,
  Renderer renderer,
  HollowLooks looks,
  ReelShot shot,
) async {
  final camera = CameraNode(name: 'reel');
  final run = await _open(device, renderer, looks, camera);
  // Forty-two seconds in: a raft or two launched, the lava welling.
  for (var i = 0; i < 42 * 30; i++) {
    _step(run);
  }
  const total = 8 * 30;
  for (var i = 0; i < total; i++) {
    final s = reelEase(i / (total - 1));
    final z = 54.0 - 16.0 * s;
    final x = riverX(z) + 4.0 - 6.0 * s;
    final eye = Vector3(x, groundAt(x, z) + 1.2 + 22.0 * s * s, z);
    // Up the river at first, then over the falls to the crater.
    final ahead = Vector3(
      riverX(z - 12.0),
      groundAt(riverX(z - 12.0), z - 12.0),
      z - 12.0,
    );
    final look = ahead + (run.volcano.crater - ahead) * s;
    camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(look);
    run.eye.setFrom(eye);
    _step(run);
    await shot.film(scene: run.scene, camera: camera, settings: _settings);
  }
  run.dispose();
  return total;
}

/// The eye off to the side of the line from the crater to the roof, high
/// enough to see down the lava's flank and over the village, dollying in
/// towards the roof over [t] of the shot and turning from the crater to it.
void _place(
  CameraNode camera,
  HollowRun run,
  double t,
  Vector3 crater,
  Vector3 roof,
) {
  final line = Vector3(roof.x - crater.x, 0.0, roof.z - crater.z);
  final across = Vector3(-line.z, 0.0, line.x).normalized();
  final middle = crater + (roof - crater) * 0.6;
  final eye =
      middle +
      across * (34.0 - 10.0 * t) +
      Vector3(0.0, 16.0 - 4.0 * t, 0.0) +
      line * (0.1 * t);
  final look = crater + (roof - crater) * (0.45 + 0.4 * t);
  camera
    ..setPosition(eye.x, math.max(eye.y, groundAt(eye.x, eye.z) + 3.0), eye.z)
    ..lookAt(look);
  run.eye.setFrom(eye);
}

/// What the valley is drawn with, as `main.dart` draws it.
final RenderSettings _settings = RenderSettings(
  exposure: 0.7,
  bloom: const BloomSettings(enabled: false),
  sky: SkySettings(
    enabled: true,
    zenith: LinearColor(0.22, 0.42, 0.78),
    horizon: LinearColor(0.68, 0.79, 0.92),
    nadir: LinearColor(0.30, 0.32, 0.30),
  ),
);

/// Where the frames go: `--dart-define=REEL_OUT=<dir>`, or `reel` in the
/// working directory.
const String _reelOut = String.fromEnvironment(
  'REEL_OUT',
  defaultValue: 'reel',
);
