/// The irradiance field is read at each pixel, not once per object — `L3`.
///
///     dart test test/irradiance_per_pixel_test.dart
///
/// A field whose left probes hold red light and right probes white, over one
/// floor with no light on it but the field: read per object, the floor took
/// one colour, its middle's; read per pixel, it is red at the left and white
/// at the right.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 48;
const int _height = 32;

IrradianceField _field({double wall = 100.0}) {
  final field = IrradianceField(
    origin: Vector3(-2.0, -1.0, -2.0),
    spacing: Vector3(4.0, 2.0, 4.0),
    countX: 2,
    countY: 2,
    countZ: 2,
    tile: 4,
    depthTile: 4,
  );
  for (var z = 0; z < 2; z++) {
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        final probe = field.probeIndex(x, y, z);
        final colour = x == 0 ? Vector3(1.0, 0.1, 0.1) : Vector3(1.0, 1.0, 1.0);
        for (var ty = 0; ty < field.tile; ty++) {
          for (var tx = 0; tx < field.tile; tx++) {
            field.writeIrradianceTexel(probe, tx, ty, colour);
          }
        }
        // Far walls by default: nothing between any probe and any point.
        for (var ty = 0; ty < field.depthTile; ty++) {
          for (var tx = 0; tx < field.depthTile; tx++) {
            field.writeDepthTexel(probe, tx, ty, wall, wall * wall);
          }
        }
      }
    }
  }
  field.fillGutters();
  return field;
}

Float32List _frame({required bool withField, double wall = 100.0}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final floor = MeshNode(
    DeviceMesh.upload(device, CuboidShape().build()),
    Material(
      lighting: LightingModel.lambert,
      baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
    ),
  )..setScale(3.6, 0.1, 3.6);
  final camera = CameraNode()
    ..setPosition(0.0, 3.0, 0.01)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..ambientIntensity = 1.0
    ..add(floor)
    ..add(camera);
  if (withField) scene.irradianceField = _field(wall: wall);
  final result = Renderer.create(device: device).render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(
      tonemap: false,
      bloom: BloomSettings(enabled: false),
      look: LookSettings(dither: 0.0),
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// The green at column [x] of the middle row: the channel the red probes
/// withhold.
double _green(Float32List frame, int x) =>
    frame[(_height ~/ 2 * _width + x) * 4 + 1];

void main() {
  test('the floor is red by the red probes and white by the white ones', () {
    final frame = _frame(withField: true);
    final left = _green(frame, _width ~/ 6);
    final right = _green(frame, _width - 1 - _width ~/ 6);
    // Mutation: read the field at the node's centre instead, as 0.7 did.
    // Both sides come back the same colour.
    expect(right - left, greaterThan(0.2));
  });

  test('a floor every probe is walled off from still takes their light', () {
    // Each probe sees a wall a hundredth of a unit away, so none can see the
    // floor. Mutation: drop the 0.05 floor on the visibility in the mirror.
    // Every weight falls under 1e-18 and the floor reads black.
    final frame = _frame(withField: true, wall: 0.01);
    final left = _green(frame, _width ~/ 6);
    final right = _green(frame, _width - 1 - _width ~/ 6);
    expect(right, greaterThan(0.2));
    expect(right - left, greaterThan(0.1));
  });

  test('with no field, the hemisphere stands as it did', () {
    final frame = _frame(withField: false);
    expect(
      _green(frame, _width ~/ 6),
      closeTo(_green(frame, _width - 1 - _width ~/ 6), 1e-6),
    );
  });
}
