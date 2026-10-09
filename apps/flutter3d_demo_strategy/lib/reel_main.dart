/// The release reel's shot of this game, filmed frame by frame:
///
///     flutter run -d macos --profile -t lib/reel_main.dart \
///         --dart-define=REEL_OUT=<dir>
///
/// **fire** — at dusk, a hall of the near camp shot with a fire arrow: its
/// timber catches, the fire grows and spreads to the next roof, smoke rises
/// and the firelight falls on the ground round it, while the camera comes
/// down out of the sky towards the village.
///
/// The match is opened as `main.dart` opens it, on the same device and the
/// same render settings, and stepped at a fixed thirtieth of a second; each
/// frame is drawn with `capturePhoto` and written to
/// `$REEL_OUT/fire/frame_%04d.png`. The process exits when it is done.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_game_ui/capture.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'src/backend.dart';
import 'src/effects.dart';
import 'src/level_document.dart';
import 'src/map_world.dart';
import 'src/run.dart' show strategyStep;
import 'src/staging.dart';

/// How the map is drawn: `main.dart`'s settings.
const RenderSettings _settings = RenderSettings(
  shadows: ShadowSettings(
    cascades: kShadowCascades,
    resolution: kShadowResolution,
    viewDistance: 130.0,
    cascadeSplit: 0.45,
  ),
);

const int _width = 1280, _height = 720;

/// A frame's step, s, and how many match steps make one.
const double _dt = reelFrameStep;
final int _matchSteps = (_dt / strategyStep).round();

/// Seconds run before the first frame — the river settled, the arrow's
/// flame held to the timber long enough for it to catch — and seconds
/// filmed.
const double _warmUp = 4.0, _length = 9.0;

/// The sun low in the west at dusk, and the blue of the sky after it.
vm.Vector3 get _sunAlong => vm.Vector3(-0.85, -0.22, 0.35)..normalize();
vm.Vector3 get _sunLight => vm.Vector3(1.0, 0.52, 0.28)..scale(0.35);
final vm.Vector4 _dusk = vm.Vector4(0.05, 0.06, 0.11, 1.0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Reel());
}

class _Reel extends StatefulWidget {
  const _Reel();

  @override
  State<_Reel> createState() => _ReelState();
}

class _ReelState extends State<_Reel> {
  @override
  void initState() {
    super.initState();
    _film();
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFF000000));

  Future<void> _film() async {
    final device = await openDevice(width: _width, height: _height);
    final scene = Scene(name: 'map')
      ..ambientIntensity = 0.12 * Photometric.legacyUnit
      ..ambientColor = LinearColor(0.38, 0.45, 0.70);
    scene.add(
      LightNode(
        type: LightType.directional,
        color: LinearColor(1.0, 0.52, 0.28),
        intensity: 0.35 * Photometric.legacyUnit,
        name: 'sun',
      )..lookAt(_sunAlong),
    );
    final camera = scene.add(CameraNode(name: 'camera'));
    final Staged staged = await stage(
      device: device,
      map: await StrategyMap.load(asset: mapAsset),
    );
    staged.visuals.addTo(scene);
    final renderer = Renderer.create(device: device);
    final world = mapWorldOf(staged.simulation);
    final effects = await MapEffects.open(
      device: device,
      scene: scene,
      renderer: renderer,
      world: world,
      staged: staged,
      sunAlong: _sunAlong,
      sunLight: _sunLight,
    );

    // A hall of the near camp, seen as the player sees it, shot at from a
    // stride off its south-east corner.
    final List<Building> halls = staged.simulation.buildings;
    final int index = halls.indexWhere((Building b) => b.side == viewerSide);
    final Building hall = halls[index < 0 ? 0 : index];
    final vm.Vector3 c = hall.center;
    world.shootAtHall(
      index < 0 ? 0 : index,
      c + vm.Vector3(hall.width, 1.5, hall.depth),
    );

    void step() {
      for (var i = 0; i < _matchSteps; i++) {
        staged.match.step(strategyStep);
      }
      staged.visuals.sync();
    }

    // The camera comes down from high over the camp to a few storeys over
    // its roofs, swinging a quarter of a right angle round it, eased in and
    // out; [t] from nought to one over the shot.
    void place(double t) {
      final double e = t * t * (3.0 - 2.0 * t);
      final double turn = 0.6 + 0.4 * e;
      final double far = 46.0 + (20.0 - 46.0) * e;
      final double high = 34.0 + (9.0 - 34.0) * e;
      final eye =
          c + vm.Vector3(far * math.cos(turn), high, far * math.sin(turn));
      camera
        ..setPositionFrom(eye)
        ..lookAt(c + vm.Vector3(0.0, 2.5, 0.0));
      effects.update(_dt, eye: eye);
    }

    for (var i = 0; i < (_warmUp / _dt).round(); i++) {
      step();
      place(0.0);
    }

    // In tiles of 1024, as photo mode draws a picture.
    final shot = Reel(
      renderer: renderer,
      out: _reelOut,
      width: _width,
      height: _height,
      tileWidth: 1024,
      tileHeight: 1024,
    ).shot('fire');
    final int frames = (_length / _dt).round();
    for (var f = 0; f < frames; f++) {
      step();
      place(f / (frames - 1));
      await shot.film(
        scene: scene,
        camera: camera,
        settings: _settings,
        clearColorSrgb: _dusk,
      );
    }
    stdout.writeln('fire: $frames frames in ${shot.folder}');
    exit(0);
  }
}

/// Where the frames go: `--dart-define=REEL_OUT=<dir>`, or `reel` in the
/// working directory.
const String _reelOut = String.fromEnvironment(
  'REEL_OUT',
  defaultValue: 'reel',
);
