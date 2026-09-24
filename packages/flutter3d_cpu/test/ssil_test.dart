/// Screen-space indirect light carries a wall's colour onto the floor at its
/// foot, and still darkens the crease — `L5`.
///
///     dart test test/ssil_test.dart
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

/// A white floor with a wall of [wall]'s colour standing on it across the
/// back, lit from behind the camera.
({Float32List ao, int width, Float32List frame}) _render(
  Vector4 wall, {
  AmbientOcclusionMethod method = AmbientOcclusionMethod.ssil,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final cube = DeviceMesh.upload(device, CuboidShape().build());
  MeshNode slab(Vector3 at, Vector3 scale, Vector4 colour) =>
      MeshNode(
          cube,
          Material(lighting: LightingModel.lambert, baseColor: colour),
        )
        ..setPosition(at.x, at.y, at.z)
        ..setScale(scale.x, scale.y, scale.z);
  final camera = CameraNode()
    ..setPosition(0.0, 2.5, 3.0)
    ..lookAt(Vector3(0.0, 0.0, -0.5));
  final scene = Scene()
    ..add(
      slab(
        Vector3(0.0, -0.05, 0.0),
        Vector3(8.0, 0.1, 8.0),
        Vector4(1.0, 1.0, 1.0, 1.0),
      ),
    )
    ..add(slab(Vector3(0.0, 1.0, -1.0), Vector3(8.0, 2.0, 0.2), wall))
    ..add(LightNode(intensity: 3.0)..setRotationYawPitchRoll(0.0, -0.6, 0.0))
    ..add(camera);
  final probe = _AoProbe(device);
  final result = (Renderer.create(device: device)..addNode(probe)).render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      ambientOcclusion: AmbientOcclusionSettings(
        enabled: true,
        radius: 0.6,
        strength: 1.0,
        method: method,
      ),
    ),
  );
  return (
    ao: probe.last!,
    width: probe.width,
    frame: device.readHdrPixels(result.frame),
  );
}

/// The first row of the occlusion buffer, down the middle column, where the
/// frame shows the white floor rather than the wall: the floor at the wall's
/// foot, which is what the wall bounces onto.
int _foot(({Float32List ao, int width, Float32List frame}) it) {
  final rows = it.ao.length ~/ 4 ~/ it.width;
  return List<int>.generate(rows, (row) => row).firstWhere((row) {
    final at = (row * 2 * _width + _width ~/ 2) * 4;
    return it.frame[at + 1] > it.frame[at] * 0.5;
  });
}

int _at(({Float32List ao, int width, Float32List frame}) it, int row) =>
    (row * it.width + it.width ~/ 2) * 4;

void main() {
  test('a red wall reddens the floor at its foot, and the crease darkens', () {
    final it = _render(Vector4(1.0, 0.1, 0.1, 1.0));
    final at = _at(it, _foot(it));
    // Mutation: drop the scene's radiance from `SsilLight`. No light.
    expect(it.ao[at], greaterThan(0.05));
    expect(it.ao[at], greaterThan(it.ao[at + 1] * 2.0));
    // Mutation: return 1 for the open share. Nothing darkens.
    expect(it.ao[at + 3], lessThan(0.9));
  });

  test('a grey wall bounces grey', () {
    // The same stage, so the same foot; found where the wall is red, since a
    // grey one is as white as the floor to the search.
    final foot = _foot(_render(Vector4(1.0, 0.1, 0.1, 1.0)));
    final it = _render(Vector4(0.5, 0.5, 0.5, 1.0));
    final at = _at(it, foot);
    expect(it.ao[at], greaterThan(0.01));
    expect(it.ao[at], closeTo(it.ao[at + 1], it.ao[at] * 0.05));
  });

  test(
    'the composite adds the bounce where the horizon method only darkens',
    () {
      final lit = _render(Vector4(1.0, 0.1, 0.1, 1.0));
      final dark = _render(
        Vector4(1.0, 0.1, 0.1, 1.0),
        method: AmbientOcclusionMethod.gtao,
      );
      final at = (_foot(lit) * 2 * _width + _width ~/ 2) * 4;
      // The horizon method leaves the white floor white; the indirect one
      // tints it with the wall. Mutation: leave `contact.z` at nought.
      expect(dark.frame[at], closeTo(dark.frame[at + 1], 1e-4));
      expect(lit.frame[at] - lit.frame[at + 1], greaterThan(0.05));
    },
  );
}
