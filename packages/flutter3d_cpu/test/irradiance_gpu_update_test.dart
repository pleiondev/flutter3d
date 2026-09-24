/// The irradiance field is kept current by the renderer — `L4`.
///
///     dart test test/irradiance_gpu_update_test.dart
///
/// A room with a red wall and a lamp, and a field over it that starts black:
/// the renderer draws two probes' views a frame and folds them into the
/// atlas. After every probe has been visited a few times, the probe beside
/// the red wall reads red in the wall's direction, and a static room stops
/// changing.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart' hide encodeOctahedral;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 16;

typedef _Room = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  CameraNode camera,
  IrradianceField field,
});

_Room _room() {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  MeshNode slab(Vector3 size, Vector3 at, Vector4 colour) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    Material(baseColor: colour, lighting: LightingModel.lambert),
  )..setPosition(at.x, at.y, at.z);
  final field =
      IrradianceField(
          origin: Vector3(-1.0, -1.0, -1.0),
          spacing: Vector3(2.0, 2.0, 2.0),
          countX: 2,
          countY: 2,
          countZ: 2,
          tile: 4,
          depthTile: 4,
        )
        ..gpuUpdates = 2
        ..hysteresis = 0.5
        ..fillGutters();
  final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(
      slab(
        Vector3(0.2, 4.0, 4.0),
        Vector3(-1.6, 0.0, 0.0),
        Vector4(1.0, 0.05, 0.05, 1.0),
      ),
    )
    ..add(
      slab(
        Vector3(0.2, 4.0, 4.0),
        Vector3(1.6, 0.0, 0.0),
        Vector4(0.9, 0.9, 0.9, 1.0),
      ),
    )
    ..add(
      LightNode(type: LightType.point, intensity: 40.0, range: 12.0)
        ..setPosition(0.0, 0.0, 0.0),
    )
    ..add(camera)
    ..irradianceField = field;
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
    field: field,
  );
}

void _frames(_Room it, int count) {
  for (var i = 0; i < count; i++) {
    it.renderer.render(
      width: _size,
      height: _size,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
    );
  }
}

/// Probe [probe]'s irradiance towards [direction], out of the atlas the
/// renderer is keeping.
Vector3 _irradiance(_Room it, int probe, Vector3 direction) {
  final layout = it.field.toAtlas();
  final Float32List atlas = it.device.readHdrPixels(
    it.renderer.irradianceAtlas!,
  );
  final uv = encodeOctahedral(direction);
  final tile = it.field.tile;
  final stride = tile + 2;
  final x =
      (probe % layout.columns) * stride +
      1 +
      (uv.x * tile).floor().clamp(0, tile - 1);
  final y =
      (probe ~/ layout.columns) * stride +
      1 +
      (uv.y * tile).floor().clamp(0, tile - 1);
  final at = (y * layout.width + x) * 4;
  return Vector3(atlas[at], atlas[at + 1], atlas[at + 2]);
}

void main() {
  test('the field fills with the room it stands in', () {
    final it = _room();
    _frames(it, 1);
    // One frame in, two of eight probes have been drawn; probe 0 is one.
    _frames(it, 11);
    // Probe 0 stands at (-1, -1, -1), beside the red wall at x = -1.6.
    final towardsRed = _irradiance(it, 0, Vector3(-1.0, 0.0, 0.0));
    // Mutation: return `old` from the convolve kernel's mirror. The atlas
    // stays the black it was seeded with.
    expect(towardsRed.x, greaterThan(0.02));
    expect(towardsRed.x, greaterThan(towardsRed.y * 2.0));
  });

  test('a still room stops changing', () {
    final it = _room();
    _frames(it, 40);
    final before = _irradiance(it, 3, Vector3(0.0, 1.0, 0.0));
    _frames(it, 8);
    final after = _irradiance(it, 3, Vector3(0.0, 1.0, 0.0));
    expect((after - before).length, lessThan(0.02 + before.length * 0.05));
  });

  test('without gpu updates, the bake stands', () {
    final it = _room();
    it.field.gpuUpdates = 0;
    _frames(it, 4);
    expect(
      _irradiance(it, 0, Vector3(-1.0, 0.0, 0.0)).length,
      0.0,
      reason: 'the black the field was baked with',
    );
  });

  test('a frame allowance too small for two probes updates one — N3', () {
    final it = _room()..field.gpuUpdates = 4;
    void frame(int allowance) => it.renderer.render(
      width: _size,
      height: _size,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: RenderSettings(frameWorkBudget: allowance),
    );
    frame(0);
    expect(it.renderer.frameWorkBudget.items, 4);
    // One microsecond fits no probe: the first of a frame runs anyway, the
    // rest wait. Mutation: skip the `spend` in the update loop. All four.
    frame(1);
    expect(it.renderer.frameWorkBudget.items, 1);
    expect(it.renderer.frameWorkBudget.deferred, 1);
  });
}
