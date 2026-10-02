/// `ShadowSettings.caustics`: light through a refracting caster is followed
/// to where it lands.
///
///     flutter test test/caustics_test.dart
///
/// A glass ball over a floor, the sun above it. A ball of glass is a lens: it
/// gathers the light that falls on it into a bright spot under it, brighter
/// than the floor around, and leaves a dark ring round the spot. Without
/// caustics the engine can only take light away, so nothing under the ball is
/// brighter than the lit floor.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 96;

Future<List<int>> _frame({required bool caustics, bool ball = true}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(4, 0.1, 4)).build(),
        ),
        Material(name: 'floor', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      )..setPosition(0.0, -0.05, 0.0),
    )
    ..add(
      LightNode(intensity: 0.4, castsShadow: true)
        ..setLocalForward(Vector3(0.0, -1.0, 0.02)),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 3.0, 0.01)
        ..lookAt(Vector3.zero()),
    );
  if (ball) {
    scene.add(
      MeshNode(
          DeviceMesh.upload(
            device,
            const SphereShape(radius: 0.3, segments: 48, rings: 24).build(),
          ),
          Material(
            name: 'glass ball',
            lighting: LightingModel.pbrLayered,
            baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
            extensions: MaterialExtensions(
              transmission: 1.0,
              ior: 1.5,
              thickness: 0.6,
            ),
          ),
        )
        ..setPosition(0.0, 0.6, 0.0)
        // Seen from above it would hide its own spot.
        ..shadowCasting = ShadowCastingMode.shadowsOnly,
    );
  }
  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      shadows: ShadowSettings(
        translucentCasters: true,
        caustics: caustics,
        cascades: 1,
        causticPhotons: 96,
      ),
      look: const LookSettings(dither: 0),
    ),
  );
  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i)];
}

/// The brightest and darkest red within [radius] pixels of the middle.
(int, int) _extremes(List<int> frame, double radius) {
  var hi = 0, lo = 255;
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      final dx = x - _size / 2, dy = y - _size / 2;
      if (math.sqrt(dx * dx + dy * dy) > radius) continue;
      final r = frame[(y * _size + x) * 4];
      hi = math.max(hi, r);
      lo = math.min(lo, r);
    }
  }
  return (hi, lo);
}

void main() {
  test(
    'a glass ball gathers the sun into a spot brighter than the floor',
    () async {
      final floor = await _frame(caustics: true, ball: false);
      final (litHi, _) = _extremes(floor, 20);
      final lens = await _frame(caustics: true);
      final (hi, lo) = _extremes(lens, 20);
      // Mutation: drop the photon pass, and nothing is brighter than the lit
      // floor; drop the stop in the transmittance stage, and nothing is darker.
      expect(hi, greaterThan(litHi + 10));
      expect(lo, lessThan(litHi - 20));
    },
  );

  test('without caustics nothing under the ball is brighter', () async {
    final floor = await _frame(caustics: false, ball: false);
    final (litHi, _) = _extremes(floor, 20);
    final plain = await _frame(caustics: false);
    final (hi, _) = _extremes(plain, 20);
    expect(hi, lessThanOrEqualTo(litHi + 1));
  });
}
