/// Clustered lights light each part of a floor by the lights that reach it,
/// where the per-draw list runs out at thirty-two — `L6`.
///
///     dart test test/clustered_lights_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

/// A white floor under [side]² small lights on a one-metre grid, seen from
/// above; the frame and where each light's spot lands in it.
({Float32List frame, List<int> spots}) _render(
  int side, {
  required bool clustered,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 9.0, 4.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..add(
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(lighting: LightingModel.lambert),
        )
        ..setPosition(0.0, -0.05, 0.0)
        ..setScale(12.0, 0.1, 12.0),
    )
    ..add(camera);
  final spots = <int>[];
  final viewProjection = camera.viewProjection(_width / _height);
  for (var i = 0; i < side; i++) {
    for (var j = 0; j < side; j++) {
      final x = i - (side - 1) / 2;
      final z = j - (side - 1) / 2;
      scene.add(
        LightNode(type: LightType.point, intensity: 2.0, range: 0.8)
          ..setPosition(x, 0.3, z),
      );
      final clip = viewProjection.transformed(Vector4(x, 0.0, z, 1.0));
      final px = ((clip.x / clip.w * 0.5 + 0.5) * _width).floor();
      final py = ((0.5 - clip.y / clip.w * 0.5) * _height).floor();
      if (px >= 0 && px < _width && py >= 0 && py < _height) {
        spots.add(py * _width + px);
      }
    }
  }
  final result = Renderer.create(device: device).render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      clusteredLights: clustered,
    ),
  );
  return (frame: device.readHdrPixels(result.frame), spots: spots);
}

void main() {
  test('where the list holds every light, the cells change nothing', () {
    // Twelve lights: eight slots and a tail of four, so the list is whole.
    final list = _render(4, clustered: false);
    final cells = _render(4, clustered: true);
    var worst = 0.0;
    for (var i = 0; i < list.frame.length; i++) {
      final d = (list.frame[i] - cells.frame[i]).abs();
      if (d > worst) worst = d;
    }
    // Mutation: drop `InSlots`. The slot lights count twice and the spots
    // under them brighten.
    expect(worst, lessThan(1e-3));
  });

  test('sixty-four lights over a floor: each spot lit only with cells', () {
    final list = _render(8, clustered: false);
    final cells = _render(8, clustered: true);
    double lit(Float32List frame, int at) => frame[at * 4];
    final dark = list.spots.where((at) => lit(list.frame, at) < 1.0).length;
    final darkWithCells = cells.spots
        .where((at) => lit(cells.frame, at) < 1.0)
        .length;
    // The floor's one draw keeps thirty-two lights; the other half of the
    // grid leaves its spots to the ambient alone.
    expect(list.spots.length, 64);
    expect(dark, 32);
    // Mutation: leave `cluster_grid.w` at nought. As dark as the list.
    expect(darkWithCells, 0);
  });
}
