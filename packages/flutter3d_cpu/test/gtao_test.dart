/// Ground-truth ambient occlusion finds the crease and leaves the open floor
/// alone — `L5`.
///
///     dart test test/gtao_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

final class _AoProbe extends RenderNode {
  _AoProbe(this._device);

  final CpuDevice _device;
  Float32List? last;
  int width = 0;

  @override
  String get name => 'ao probe';

  @override
  FramePhase get preferredPhase => FramePhase.present;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.frame,
    FrameResourceIds.ao,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    final ao = frame.resources.texture(FrameResourceIds.ao);
    last = _device.readHdrPixels(ao);
    width = ao.width;
    frame.resources.provide(
      FrameResourceIds.frame,
      frame.resources.texture(FrameResourceIds.frame),
    );
  }
}

/// The occlusion of a floor with a wall standing on it across the back.
({Float32List ao, int width}) _occlusion(AmbientOcclusionMethod method) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final cube = DeviceMesh.upload(device, CuboidShape().build());
  MeshNode slab(Vector3 at, Vector3 scale) => MeshNode(cube, Material())
    ..setPosition(at.x, at.y, at.z)
    ..setScale(scale.x, scale.y, scale.z);
  final camera = CameraNode()
    ..setPosition(0.0, 2.5, 3.0)
    ..lookAt(Vector3(0.0, 0.0, -0.5));
  final scene = Scene()
    ..add(slab(Vector3(0.0, -0.05, 0.0), Vector3(8.0, 0.1, 8.0)))
    ..add(slab(Vector3(0.0, 1.0, -1.0), Vector3(8.0, 2.0, 0.2)))
    ..add(camera);
  final probe = _AoProbe(device);
  (Renderer.create(device: device)..addNode(probe)).render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      ambientOcclusion: AmbientOcclusionSettings(
        enabled: true,
        radius: 0.6,
        method: method,
      ),
    ),
  );
  return (ao: probe.last!, width: probe.width);
}

double _column(({Float32List ao, int width}) it, int row) {
  final x = it.width ~/ 2;
  return it.ao[(row * it.width + x) * 4];
}

void main() {
  test('the crease is darker than the open floor', () {
    final it = _occlusion(AmbientOcclusionMethod.gtao);
    final rows = it.ao.length ~/ 4 ~/ it.width;
    // Scan up the middle column from the bottom (the open floor near the
    // camera) and find the darkest point, which should be at the foot of the
    // wall.
    final open = _column(it, rows - 2);
    var darkest = 1.0;
    for (var row = 0; row < rows; row++) {
      final v = _column(it, row);
      if (v < darkest) darkest = v;
    }
    // Mutation: return 1.0 from `_gtao`. Nothing is dark anywhere.
    expect(open, greaterThan(0.85));
    expect(darkest, lessThan(open - 0.2));
  });

  test('the method is a choice, and the kernel stays the default', () {
    expect(
      const AmbientOcclusionSettings().method,
      AmbientOcclusionMethod.ssao,
    );
    final kernel = _occlusion(AmbientOcclusionMethod.ssao).ao;
    final horizons = _occlusion(AmbientOcclusionMethod.gtao).ao;
    expect(horizons, isNot(kernel));
  });
}
