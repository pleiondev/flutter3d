/// The sky, drawn.
///
///     flutter test test/sky_frame_test.dart
///
/// `sky.dart` is arithmetic and flags; whether any of it reaches the frame is a
/// different question, and it is the one that has gone wrong before. A dome
/// wound the wrong way is culled and simply absent. A dome that writes depth
/// erases the level behind it. A dome that is a shadow caster darkens the
/// ground it is nowhere near. None of those are visible in a unit test and all
/// of them are one pixel count away from obvious.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
      )!;
  return (
    device: device,
    renderer: Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    ),
  );
}

/// Blue above, dark below, and a red glow at the sun so that "which way is the
/// camera looking" is answerable from the pixels.
SkyGradient _gradient() => SkyGradient(
      zenith: Vector3(0.05, 0.10, 0.60),
      horizon: Vector3(0.30, 0.36, 0.45),
      nadir: Vector3(0.02, 0.02, 0.03),
      directionToSun: Vector3(1.0, 0.2, 0.0),
      sunColour: Vector3(1.0, 0.1, 0.1),
      glowStrength: 0.9,
      glowExponent: 8.0,
    );

/// A red wall forty metres out, a camera at the origin, and optionally a sky.
({Scene scene, CameraNode camera}) _world({
  required bool sky,
  bool wall = true,
}) {
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene();

  if (wall) {
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(30.0, 30.0, 1.0)).build(),
        ),
        engine.Material(
          name: 'wall',
          baseColor: Vector4(0.0, 1.0, 0.0, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'wall',
      )..setPosition(0.0, 0.0, 40.0),
    );
  }

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.2,
      near: 0.3,
      far: 500.0,
    ),
  )..lookAt(Vector3(0.0, 0.0, 1.0));
  scene.add(camera);

  if (sky) {
    final mesh = const SkyDome(rings: 24, segments: 32).build();
    paintSky(mesh, _gradient().colour);
    final node = skyNode(DeviceMesh.upload(device, mesh));
    scene.add(node);
    followCamera(node, camera);
  }

  return (scene: scene, camera: camera);
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer}) it,
  ({Scene scene, CameraNode camera}) world, {
  ShadowSettings shadows = const ShadowSettings(),
  FogSettings fog = const FogSettings(),
}) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: world.scene,
    views: <RenderView>[
      RenderView(
        camera: world.camera,
        // Black, so that anything not black in the frame was drawn.
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      shadows: shadows,
      fog: fog,
      bloom: const BloomSettings(enabled: false),
      tonemap: false,
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

int _count(Uint8List rgba, bool Function(int r, int g, int b) test) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (test(rgba[i], rgba[i + 1], rgba[i + 2])) count++;
  }
  return count;
}

int _green(Uint8List rgba) =>
    _count(rgba, (int r, int g, int b) => g > 60 && g > r * 2 && g > b * 2);

int _black(Uint8List rgba) =>
    _count(rgba, (int r, int g, int b) => r < 6 && g < 6 && b < 6);

/// Mean of one channel over a band of rows, 0 to 255.
///
/// Means rather than thresholded counts, and that is a correction: the first
/// draft of this file counted "blue pixels" as `b > 2r && b > 2g`, which a real
/// sky never is. A horizon is grey-blue — (0.30, 0.36, 0.45) here — and every
/// assertion built on saturated colour counted zero of them while the frame was
/// perfectly correct.
double _mean(
  Uint8List rgba, {
  required int channel,
  int fromRow = 0,
  int? toRow,
}) {
  var total = 0.0;
  var count = 0;
  for (var y = fromRow; y < (toRow ?? _height); y++) {
    for (var x = 0; x < _width; x++) {
      total += rgba[(y * _width + x) * 4 + channel];
      count++;
    }
  }
  return total / count;
}

void main() {
  test('without a sky the background is the clear colour', () async {
    // The control, and the thing being replaced.
    final frame = await _draw(_engine(), _world(sky: false));

    expect(_green(frame), greaterThan(500), reason: 'the wall is drawn');
    expect(_black(frame), greaterThan(1000), reason: 'and around it, nothing');
  });

  test('with a sky there is no background left', () async {
    // Mutation: order the dome's profile bottom-to-top. Every triangle faces
    // out, back-face culling removes the lot, and the frame comes back exactly
    // as the control above — a sky that fails by being absent, with no error
    // anywhere.
    final frame = await _draw(_engine(), _world(sky: true));
    final without = await _draw(_engine(), _world(sky: false));

    expect(_black(frame), lessThan(60), reason: 'the sky covers the void');
    expect(_mean(frame, channel: 2),
        greaterThan(_mean(without, channel: 2) + 40),
        reason: 'and what covers it is a sky rather than more black');
  });

  test('the sky does not clip the world away', () async {
    // Mutation: leave `Material.depthWrite` unset on the sky. A dome ten metres
    // across then writes depth over the whole frame, and a wall at forty metres
    // — and every level ever built — is behind it.
    final withSky = await _draw(_engine(), _world(sky: true));
    final without = await _draw(_engine(), _world(sky: false));

    expect(_green(withSky), closeTo(_green(without), 8),
        reason: 'the wall is as visible as it was');
  });

  test('the gradient is a gradient, and it is the right way up', () async {
    // Mutation: paint every vertex from the raw position rather than the
    // direction, or flip the profile's sense of up. The frame stays full of
    // colour and the sky is upside down, which is exactly the class of bug a
    // "there are blue pixels" test cannot see.
    final frame = await _draw(_engine(), _world(sky: true, wall: false));

    final top = _mean(frame, channel: 2, toRow: _height ~/ 4);
    final bottom = _mean(frame, channel: 2, fromRow: _height - _height ~/ 4);

    expect(top, greaterThan(bottom + 40),
        reason: 'the sky is brighter above than below, not the other way round');
  });

  test('turning the camera turns the view and not the sky', () async {
    // The reason a sky exists at all: looking towards the sun is a different
    // picture from looking away. Mutation: rotate the dome with the camera in
    // `followCamera` — both frames become identical and the sky stops being a
    // place.
    final it = _engine();
    final world = _world(sky: true, wall: false);

    world.camera.lookAt(Vector3(1.0, 0.2, 0.0));
    final intoSun = await _draw(it, world);

    world.camera.lookAt(Vector3(-1.0, 0.2, 0.0));
    final away = await _draw(it, world);

    // Red, because the glow in this fixture is red and the sky it sits in is
    // not: the difference is the sun and nothing else. Absolute redness is not
    // the measure — the sky is grey-blue everywhere, and the sun only tilts it.
    expect(_mean(intoSun, channel: 0) - _mean(away, channel: 0),
        greaterThan(20.0),
        reason: 'the sun is in one of these frames and not the other');
  });

  test('a sky the camera has left behind is still around it', () async {
    // Mutation: never call `followCamera`. At the origin everything looks
    // right, which is why this moves the camera first — a ten-metre sphere left
    // at the origin is a ball the player drives away from.
    final it = _engine();
    final world = _world(sky: true, wall: false);
    final sky = world.scene.meshes.firstWhere((MeshNode n) => n.name == 'sky');

    world.camera.setPosition(0.0, 0.0, -300.0);
    followCamera(sky, world.camera);
    final frame = await _draw(it, world);

    expect(_black(frame), lessThan(60));
  });

  test('the sky casts no shadow and does not coarsen the ones there are',
      () async {
    // Mutation: drop `castsShadow = false`, or drop `castersOnly` from the
    // shadow path. The dome is drawn into the cascade — a sphere around the
    // camera shadows everything inside it — or it sets the scene radius and
    // every shadow in the level is coarsened by a mesh that casts none.
    const shadows = ShadowSettings(cascades: 1, resolution: 512);

    final lit = _lit();
    final litWithSky = _lit(sky: true);

    final without = await _draw(_engine(), lit, shadows: shadows);
    final with_ = await _draw(_engine(), litWithSky, shadows: shadows);

    expect(_shadowed(with_), closeTo(_shadowed(without), 12),
        reason: 'the sky changed the shadows');
  });
}

/// A floor with a slab over it and a sun across both.
({Scene scene, CameraNode camera}) _lit({bool sky = false}) {
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene();

  MeshNode block(Vector3 size, Vector3 at, String name) => MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: size).build()),
        engine.Material(
          name: name,
          baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
          lighting: LightingModel.pbr,
        ),
        name: name,
      )..setPosition(at.x, at.y, at.z);

  scene.add(block(Vector3(40.0, 1.0, 60.0), Vector3(0.0, -0.5, 20.0), 'floor'));
  scene.add(block(Vector3(10.0, 0.6, 6.0), Vector3(0.0, 5.0, 10.0), 'canopy'));
  scene.add(
    LightNode(
      type: LightType.directional,
      intensity: 1.1,
      castsShadow: true,
      name: 'sun',
    )..setLocalForward(Vector3(-0.2, -0.95, 0.25)),
  );

  final camera = CameraNode()
    ..setPosition(0.0, 3.0, -8.0)
    ..lookAt(Vector3(0.0, 1.0, 8.0));
  scene.add(camera);

  if (sky) {
    final mesh = const SkyDome(rings: 16, segments: 24).build();
    paintSky(mesh, _gradient().colour);
    final node = skyNode(DeviceMesh.upload(device, mesh));
    scene.add(node);
    followCamera(node, camera);
  }

  return (scene: scene, camera: camera);
}

/// Pixels that are floor lying in shadow: darker than lit floor, brighter than
/// the background behind it.
int _shadowed(Uint8List rgba) => _count(rgba, (int r, int g, int b) {
      final luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      return luminance > 20 && luminance < 170;
    });
