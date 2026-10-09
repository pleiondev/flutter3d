/// The valley filmed for a reel: the waterfall into the pool, then a stone
/// dropped into the pond, each a fixed 1/30 s a frame, written as PNGs.
///
///     flutter run -d macos --profile -t lib/reel_main.dart \
///         --dart-define=REEL_OUT=<dir>
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game_ui/capture.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show preparePhysics;

import 'src/staging.dart';
import 'src/valley.dart';

const int _width = 1280, _height = 720;
const double _dt = reelFrameStep;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preparePhysics();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Color(0xFF14161A),
        child: Center(
          child: Text('filming…', style: TextStyle(color: Colors.white)),
        ),
      ),
    ),
  );
  try {
    await _film();
  } catch (error, stack) {
    stderr
      ..writeln('reel: $error')
      ..writeln(stack);
    exit(1);
  }
  exit(0);
}

/// Where the sun shines along: as the game has it.
final Vector3 _sunAlong = Vector3(0.35, -0.7, -0.6);

/// The game's own render settings.
RenderSettings get _settings => RenderSettings(
  exposure: 0.7,
  bloom: const BloomSettings(enabled: false),
  sky: SkySettings(
    enabled: true,
    zenith: LinearColor(0.22, 0.42, 0.78),
    horizon: LinearColor(0.68, 0.79, 0.92),
    nadir: LinearColor(0.30, 0.32, 0.30),
  ),
);

Future<void> _film() async {
  final device = await openDevice(width: _width, height: _height);
  final renderer = Renderer.create(device: device);
  // In tiles of 1024, as photo mode draws a picture.
  final reel = Reel(
    renderer: renderer,
    out: _reelOut,
    width: _width,
    height: _height,
    tileWidth: 1024,
    tileHeight: 1024,
  );
  final camera = CameraNode(name: 'eye');
  final scene = Scene()
    ..ambientIntensity = 0.45 * Photometric.legacyUnit
    ..ambientColor = LinearColor(0.70, 0.80, 1.0)
    ..add(
      LightNode(name: 'sun', intensity: 2.0 * Photometric.legacyUnit)
        ..setLocalForward(_sunAlong),
    )
    ..add(camera);
  final elements = await Elements.open(
    device: device,
    renderer: renderer,
    scene: scene,
    load: rootBundle.load,
  );
  final run = WaterRun(
    device,
    scene,
    elements,
    sun: (along: _sunAlong, light: Vector3(2.0, 1.95, 1.85)),
  );
  run.eye.setValues(16.0, 6.0, 30.0);

  // Warm up until the spring has filled the stream and it pours off the
  // cliff, and then a little more so the pool below is churning.
  var warm = 0;
  while (warm < 900 || (run.sprayInFlight == 0 && warm < 4500)) {
    run.step(_dt);
    warm++;
  }
  for (var i = 0; i < 150; i++) {
    run.step(_dt);
  }

  // The falls: from low by the pool, rising past the lip.
  final fallsX = streamX(cliffTop);
  final lip = groundAt(fallsX, cliffTop - 0.3);
  final foot = run.pondLevel;
  final waterfall = await _shot(
    'waterfall',
    seconds: 6.0,
    run: run,
    reel: reel,
    scene: scene,
    camera: camera,
    eyeAt: (t) {
      final yaw = 0.35 - 0.5 * t;
      final rise = foot + 0.6 + (lip + 1.5 - foot) * t;
      return Vector3(
        fallsX + 7.5 * math.sin(yaw),
        rise,
        cliffFoot + 7.5 * math.cos(yaw),
      );
    },
    lookAt: (t) =>
        Vector3(fallsX, foot + (lip - foot) * (0.35 + 0.4 * t), cliffTop),
  );

  // The stone: dropped into the open pond from five metres, seen from just
  // over the water, the camera drifting round as the rings spread.
  final drop = Vector3(pondX + 2.5, run.pondLevel, pondZ + 2.0);
  var dropped = false;
  final stone = await _shot(
    'stone',
    seconds: 5.0,
    run: run,
    reel: reel,
    scene: scene,
    camera: camera,
    before: (frame) {
      // Half a second in, so the still pond is seen first.
      if (!dropped && frame == 15) {
        run.dropStone(drop);
        dropped = true;
      }
    },
    eyeAt: (t) {
      final yaw = 2.6 + 0.45 * t;
      return Vector3(
        drop.x + 5.5 * math.sin(yaw),
        drop.y + 0.5 + 0.3 * t,
        drop.z + 5.5 * math.cos(yaw),
      );
    },
    lookAt: (t) => Vector3(drop.x, drop.y + 0.6 * (1.0 - t) + 0.1, drop.z),
  );

  stdout
    ..writeln('reel: waterfall $waterfall frames')
    ..writeln('reel: stone $stone frames');
  elements.dispose();
}

/// [seconds] of the valley, a frame each 1/30 s after a step, through a
/// camera at [eyeAt] looking at [lookAt], both of the eased time; [before]
/// is told each frame's number before it is stepped. How many frames.
Future<int> _shot(
  String name, {
  required double seconds,
  required WaterRun run,
  required Reel reel,
  required Scene scene,
  required CameraNode camera,
  required Vector3 Function(double t) eyeAt,
  required Vector3 Function(double t) lookAt,
  void Function(int frame)? before,
}) async {
  final shot = reel.shot(name);
  final frames = (seconds / _dt).round();
  for (var frame = 0; frame < frames; frame++) {
    before?.call(frame);
    final t = reelEase(frame / math.max(frames - 1, 1));
    final eye = eyeAt(t);
    camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(lookAt(t));
    run.eye.setFrom(eye);
    run.step(_dt);
    await shot.film(
      scene: scene,
      camera: camera,
      settings: _settings,
      clearColorSrgb: Vector4(0.62, 0.76, 0.9, 1.0),
    );
  }
  return frames;
}

/// Where the frames go: `--dart-define=REEL_OUT=<dir>`, or `reel` in the
/// working directory.
const String _reelOut = String.fromEnvironment(
  'REEL_OUT',
  defaultValue: 'reel',
);
