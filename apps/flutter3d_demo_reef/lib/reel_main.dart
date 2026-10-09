/// Films the wreck for the release reel: the ship on the sand, the
/// caustics moving over it and the floor, a diver finning past with breath
/// rising, and the eye gliding along the hull; then the reef's wall, the
/// eye drifting along it from the sand at its foot.
///
///     flutter run -d macos --profile -t lib/reel_main.dart \
///         --dart-define=REEL_OUT=<dir>
///
/// Steps the dive at a fixed thirtieth of a second, renders each step at
/// 1280×720 and writes `<dir>/wreck/frame_NNNN.png` and
/// `<dir>/wall/frame_NNNN.png`, then exits.
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
import 'src/wreck.dart' show wreckFloor;

const double _dt = reelFrameStep;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preparePhysics();
  final (frames, wall) = await _wreck(
    'wreck',
    'wall',
    seconds: 8.0,
    wallSeconds: 4.0,
  );
  stdout.writeln('wreck: $frames frames, wall: $wall frames');
  exit(0);
}

Future<(int, int)> _wreck(
  String name,
  String wallName, {
  required double seconds,
  required double wallSeconds,
}) async {
  final sunAlong = Vector3(0.3, -0.85, -0.42);
  final sunLight = Vector3(2.0, 1.95, 1.85);
  final device = await openDevice(width: 1280, height: 720);
  final renderer = Renderer.create(device: device);
  final reel = Reel(renderer: renderer, out: _reelOut);
  final surface =
      await LiquidLook.load(
          device: device,
          renderer: renderer,
          bundle: await rootBundle.load(LiquidLook.asset),
        )
        ..sun(along: sunAlong, light: sunLight)
        ..optics = LiquidOptics.pureWater;
  final floor =
      await SeabedLook.load(
          device: device,
          renderer: renderer,
          bundle: await rootBundle.load(SeabedLook.asset),
        )
        ..sun(along: sunAlong, light: sunLight)
        ..optics = LiquidOptics.pureWater;
  final camera = CameraNode(name: 'reel');
  final scene = Scene()
    ..ambientIntensity = 0.5 * Photometric.legacyUnit
    ..ambientColor = LinearColor(0.75, 0.85, 1.0)
    ..add(
      LightNode(name: 'sun', intensity: 2.0 * Photometric.legacyUnit)
        ..setLocalForward(sunAlong),
    )
    ..add(camera);
  final elements =
      await Elements.adopt(
          NativeWorld(),
          device: device,
          renderer: renderer,
          scene: scene,
          load: rootBundle.load,
          lights: FireLights.none,
        )
        ..sun(along: sunAlong, light: sunLight);
  final run = ReefRun(
    device: device,
    scene: scene,
    elements: elements,
    surface: surface,
    floor: floor,
    looks: await ReefLooks.load(device),
  );
  // The hull's own axes, as `wreck.dart` turns it, −heading about the up:
  // along its keel, and across it to starboard, the side clear of the mast
  // that lies to port.
  final along = Vector3(math.cos(wreckHeading), 0.0, math.sin(wreckHeading));
  final across = Vector3(-math.sin(wreckHeading), 0.0, math.cos(wreckHeading));
  final middle = Vector3(wreckX, wreckFloor, wreckZ);
  // The diver starts off the bow, four metres over the sand, and fins aft
  // along the hull's side.
  final heading = math.atan2(-along.z, along.x);
  // The diver between the eye and the ship: off the bow, a body's length
  // out from the starboard side and over the height of the posts.
  run.diver.restart(
    middle -
        along * (wreckHalfLength + 3.0) +
        across * (wreckHalfBeam + 1.5) +
        Vector3(0, _hullTop + 0.5, 0),
  );
  final breath = _Breath(scene, device);
  void step() {
    run.step(_dt, swim: along * 0.7, fill: 0.0, dump: 0.0, heading: heading);
    breath.step(_dt, from: run.diver.position + Vector3(0, 0.35, 0));
  }

  // Settled: the current up, the ripples running, the diver under way.
  for (var i = 0; i < 90; i++) {
    _place(camera, run, 0.0, middle, along, across);
    step();
  }
  final total = (seconds / _dt).round();
  final shot = reel.shot(name);
  for (var i = 0; i < total; i++) {
    _place(camera, run, reelEase(i / (total - 1)), middle, along, across);
    step();
    await shot.film(scene: scene, camera: camera, settings: _underWater);
  }

  // The wall: the diver set down over its foot, finning north along it,
  // and the eye a few metres off the face behind them, drifting the same
  // way, looking along the face so the light rakes across its relief.
  final north = Vector3(0.0, 0.0, 1.0);
  run.diver.restart(Vector3(wallFoot - 3.0, -9.0, 20.0));
  final wallTotal = (wallSeconds / _dt).round();
  final wallShot = reel.shot(wallName);
  for (var i = 0; i < wallTotal + 30; i++) {
    final t = math.max(i - 30, 0) / (wallTotal - 1);
    final z = 18.0 + 8.0 * t;
    final face = Vector3(wallTop + 3.0, -9.0, z + 7.0);
    final eye = run.clearView(face, Vector3(wallFoot - 1.5, -8.0, z - 3.0));
    camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(face);
    run.eye.setFrom(eye);
    run.step(
      _dt,
      swim: north * 0.6,
      fill: 0.0,
      dump: 0.0,
      heading: -math.pi / 2,
    );
    breath.step(_dt, from: run.diver.position + Vector3(0, 0.35, 0));
    // A second to settle the diver into the swim before the first frame.
    if (i < 30) continue;
    await wallShot.film(scene: scene, camera: camera, settings: _underWater);
  }
  return (total, wallTotal);
}

/// How high the ship stands over the sand at most, m: her stem and stern
/// posts, three metres.
const double _hullTop = 3.0;

/// How far out from her side the eye glides, m: her half beam and a clear
/// margin of five metres.
const double _offSide = wreckHalfBeam + 5.0;

/// The eye gliding along the hull's starboard side at [t] of the way, clear
/// of her, a metre over her posts, looking at her across the diver.
void _place(
  CameraNode camera,
  ReefRun run,
  double t,
  Vector3 middle,
  Vector3 along,
  Vector3 across,
) {
  final eye = _outside(
    middle +
        along * ((2.0 * t - 1.0) * (wreckHalfLength + 2.0)) +
        across * _offSide +
        Vector3(0.0, _hullTop + 1.0 + 0.8 * (1.0 - t), 0.0),
    middle,
    along,
    across,
  );
  final floorThere = floorAt(eye.x, eye.z) + 1.0;
  if (eye.y < floorThere) eye.y = floorThere;
  final look =
      run.diver.position * 0.3 +
      (middle +
              along * ((2.0 * t - 1.0) * wreckHalfLength * 0.6) +
              Vector3(0.0, 1.2, 0.0)) *
          0.7;
  camera
    ..setPosition(eye.x, eye.y, eye.z)
    ..lookAt(look);
  run.eye.setFrom(eye);
}

/// [at], or, inside the ship's box — her length and beam and the mast
/// lying two metres off her port side, up to her posts, all grown by a
/// metre — pushed out to its starboard face.
Vector3 _outside(Vector3 at, Vector3 middle, Vector3 along, Vector3 across) {
  final d = at - middle;
  final a = d.dot(along), c = d.dot(across);
  final inside =
      a.abs() < wreckHalfLength + 1.0 &&
      c > -(wreckHalfBeam + 3.0) &&
      c < wreckHalfBeam + 1.0 &&
      d.y < _hullTop + 1.0;
  if (!inside) return at;
  return at + across * (wreckHalfBeam + 1.0 - c);
}

/// What the dive is drawn with under water, as `main.dart` draws it.
final RenderSettings _underWater = RenderSettings(
  exposure: 0.8,
  shadows: const ShadowSettings(
    resolution: 2048,
    viewDistance: 30.0,
    cascadeSplit: 0.6,
    directionalLightRadius: 0.6,
    strength: 0.8,
  ),
  bloom: const BloomSettings(enabled: false),
  sky: SkySettings(
    enabled: true,
    zenith: LinearColor(0.10, 0.42, 0.52),
    horizon: LinearColor(0.04, 0.24, 0.34),
    nadir: LinearColor(0.01, 0.08, 0.14),
  ),
  lightShafts: LightShaftSettings(
    enabled: true,
    distance: 30.0,
    strength: 0.02,
    color: LinearColor(0.45, 0.85, 0.95),
  ),
);

/// A diver's breath out through the regulator: every four seconds, a
/// second and a half of bubbles a few millimetres to a centimetre across,
/// rising at the terminal speed bubbles of that size share, 0.23 m/s
/// (Clift, Grace and Weber), and swaying as they go.
final class _Breath {
  _Breath(this._scene, GraphicsDevice device)
    : _mesh = DeviceMesh.upload(
        device,
        const SphereShape(radius: 1.0, segments: 8, rings: 6).build(),
      );

  final Scene _scene;
  final List<(MeshNode, double)> _rising = <(MeshNode, double)>[];
  final math.Random _random = math.Random(3);
  final RenderMaterial _air = RenderMaterial(
    name: 'breath',
    baseColor: LinearColor.fromSrgb(0.9, 0.97, 1.0, 0.5),
    roughness: 0.05,
    alphaMode: MaterialAlphaMode.blend,
  );
  final DeviceMesh _mesh;
  double _clock = 0.0;

  void step(double dt, {required Vector3 from}) {
    _clock += dt;
    final breathing = _clock % 4.0 < 1.5;
    if (breathing) {
      for (var k = 0; k < 3; k++) {
        final r = 0.003 + 0.007 * _random.nextDouble();
        final node = MeshNode(_mesh, _air, name: 'bubble')
          ..setPositionFrom(
            from +
                Vector3(
                  0.05 * (_random.nextDouble() - 0.5),
                  0.0,
                  0.05 * (_random.nextDouble() - 0.5),
                ),
          )
          ..setUniformScale(r);
        _scene.add(node);
        _rising.add((node, _random.nextDouble() * 6.28));
      }
    }
    for (var k = _rising.length - 1; k >= 0; k--) {
      final (node, phase) = _rising[k];
      final p = node.readPosition();
      if (p.y > 0.0) {
        node.removeFromParent();
        _rising.removeAt(k);
        continue;
      }
      node.setPosition(
        p.x + 0.02 * math.sin(_clock * 5.0 + phase) * dt,
        p.y + 0.23 * dt,
        p.z + 0.02 * math.cos(_clock * 4.0 + phase) * dt,
      );
    }
  }
}

/// Where the frames go: `--dart-define=REEL_OUT=<dir>`, or `reel` in the
/// working directory.
const String _reelOut = String.fromEnvironment(
  'REEL_OUT',
  defaultValue: 'reel',
);
