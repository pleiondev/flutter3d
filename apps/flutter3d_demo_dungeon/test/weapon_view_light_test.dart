/// The held weapon is lit by its own studio, not by whatever the room has.
///
///     flutter test test/weapon_view_light_test.dart
///
/// `WeaponView` documents the deal: a weapon is lit by its scene's two lights
/// and reflects `studioEnvironment`, not the room — a crypt has nothing to
/// reflect and its torches are metres behind the camera. For a long time the
/// renderer betrayed that: `encodeScene` bound the *frame's* light buffer,
/// gathered from the world scene, so the studio's lights were never uploaded
/// and every metallic weapon drew very nearly black on every backend at once.
/// This file renders the view-model pass over a deliberately lightless world
/// and asks the two questions that failure hid:
///
///  * are the weapon's pixels actually lit, and
///  * is the weapon at rest before the first simulation step — the frame every
///    start shows — rather than an unposed shape at the origin, inside the
///    camera.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_dungeon/src/weapon_models.dart';
import 'package:flutter3d_game_shooter/bridge.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 120;

/// One frame: an empty, lightless world with the weapon pass drawn over it.
Future<Uint8List> _drawn({required bool stepped}) async {
  final it = cpuTestDevice(width: _width, height: _height);
  final device = it.device;

  // The same gunmetal the game's fallback blocks use: metallic, so with no
  // light of its own and nothing to reflect it is the black this test exists
  // to keep out.
  final block = SceneNode()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(0.12, 0.14, 0.42)).build(),
        ),
        Material(
          baseColor: Vector4(0.56, 0.57, 0.60, 1.0),
          metallic: 1.0,
          roughness: 0.35,
          lighting: LightingModel.pbr,
        ),
      ),
    );

  final studio = studioEnvironment(device);
  final view = WeaponView(
    models: <String, SceneNode>{Weapons.pistol.name: block},
    initial: Weapons.pistol,
    environment: studio?.texture,
    environmentLevels: studio?.levels ?? 0,
  );
  if (stepped) view.step(1 / 60, speed: 0.0, grounded: true);

  // A world with no lights at all, which is the sharpest form of the crypt's
  // situation: if the weapon is lit by the world's buffer, here it is lit by
  // nothing.
  final world = Scene();
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.2,
      near: 0.05,
      far: 50.0,
    ),
  );
  world.add(camera);

  final renderer = Renderer.create(
    device: device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  )..addNode(view.plugin);

  final result = renderer.render(
    width: _width,
    height: _height,
    scene: world,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: const RenderSettings(),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// Pixels brighter than [floor], within the given fraction of the frame.
int _litWithin(
  Uint8List rgba, {
  required double left,
  required double top,
  required double right,
  required double bottom,
  int floor = 24,
}) {
  var lit = 0;
  for (var y = (top * _height).floor(); y < (bottom * _height).ceil(); y++) {
    for (var x = (left * _width).floor(); x < (right * _width).ceil(); x++) {
      final i = (y * _width + x) * 4;
      final luminance =
          (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
      if (luminance > floor) lit++;
    }
  }
  return lit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the weapon is lit by its studio in a lightless world', () async {
    final rgba = await _drawn(stepped: true);
    final lit = _litWithin(rgba, left: 0.0, top: 0.0, right: 1.0, bottom: 1.0);
    expect(
      lit,
      greaterThan(100),
      reason:
          'a metallic weapon under the studio lights drew almost nothing '
          'brighter than the void behind it — the view-model pass is being '
          'lit by the world scene again',
    );
  });

  test('the weapon is at rest before the first step', () async {
    final rgba = await _drawn(stepped: false);
    // At rest the weapon hangs low and to the right. Unposed it is a shape at
    // the origin, swallowing the middle of the screen — so the centre of the
    // upper-left quadrant must stay empty, and the lower-right must not.
    final upperLeft = _litWithin(
      rgba,
      left: 0.05,
      top: 0.05,
      right: 0.45,
      bottom: 0.45,
    );
    final lowerRight = _litWithin(
      rgba,
      left: 0.5,
      top: 0.5,
      right: 1.0,
      bottom: 1.0,
    );
    expect(
      lowerRight,
      greaterThan(50),
      reason: 'no weapon in the lower right: the rest pose is gone',
    );
    expect(
      upperLeft,
      0,
      reason:
          'something drew in the upper left of a frame that holds only the '
          'weapon — the holder is at the origin again, unposed until the '
          'first simulation step',
    );
  });
}
