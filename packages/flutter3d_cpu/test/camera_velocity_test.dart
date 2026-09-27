/// Every pixel knows how far it moved because the camera did — `R1`.
///
///     dart test test/camera_velocity_test.dart
///
/// Read straight off the velocity resource on the software rasteriser, whose
/// textures keep the floats a shader wrote, by a node of the test's own that
/// reads it after the composite: red and green are the motion in UV units,
/// now minus then.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

const int _width = 48;
const int _height = 32;

const RenderSettings _settings = RenderSettings(
  antiAlias: AntiAliasSettings(temporal: TemporalSettings(enabled: true)),
);

/// Copies the velocity resource out as floats, each frame it runs.
final class _VelocityProbe extends RenderNode {
  _VelocityProbe(this._device);

  final CpuDevice _device;
  Float32List? last;

  @override
  String get name => 'velocity probe';

  @override
  FramePhase get preferredPhase => FramePhase.present;

  // The frame is read and passed on untouched: a node the output does not
  // depend on is culled, and this one has to run.
  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.frame,
    FrameResourceIds.velocity,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    last = _device.readHdrPixels(
      frame.resources.texture(FrameResourceIds.velocity),
    );
    frame.resources.provide(
      FrameResourceIds.frame,
      frame.resources.texture(FrameResourceIds.frame),
    );
  }
}

typedef _Staged = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  CameraNode camera,
  _VelocityProbe probe,
});

_Staged _staged() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final mesh = DeviceMesh.upload(device, CuboidShape().build());
  final camera = CameraNode();
  final scene = Scene()
    ..add(MeshNode(mesh, Material())..setPosition(0.0, 0.0, -5.0))
    ..add(camera);
  final probe = _VelocityProbe(device);
  return (
    device: device,
    renderer: Renderer.create(device: device)..addNode(probe),
    scene: scene,
    camera: camera,
    probe: probe,
  );
}

Float32List _velocity(_Staged it) {
  it.probe.last = null;
  it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[RenderView(camera: it.camera)],
    settings: _settings,
  );
  return it.probe.last!;
}

({double x, double y}) _at(Float32List v, int x, int y) {
  final i = (y * _width + x) * 4;
  return (x: v[i], y: v[i + 1]);
}

void main() {
  test('a still camera over a still scene moves nothing', () {
    final it = _staged();
    _velocity(it);
    final v = _velocity(it);
    for (var i = 0; i < v.length; i += 4) {
      expect(v[i].abs(), lessThan(1e-5), reason: 'pixel ${i ~/ 4} x');
      expect(v[i + 1].abs(), lessThan(1e-5), reason: 'pixel ${i ~/ 4} y');
    }
  });

  test('a camera stepping right moves the box left and leaves the sky', () {
    // Mutation: pass the current matrix as the previous one in
    // `_encodeCameraVelocity`. Every pixel reads zero.
    final it = _staged();
    _velocity(it);
    it.camera.setPosition(0.2, 0.0, 0.0);
    final v = _velocity(it);

    final centre = _at(v, _width ~/ 2, _height ~/ 2);
    // A point five metres off moved 0.2 m to the left of a view whose half
    // width at that depth is 5·tan(fov/2)·aspect: in UV that is half of
    // 0.2 / (that half width), and negative because it went left.
    // The default camera's vertical field of view.
    const fov = math.pi / 4;
    final halfWidth = 5.0 * math.tan(fov / 2) * (_width / _height);
    // The box's front face is half a metre nearer than its centre.
    final nearHalfWidth = 4.5 * math.tan(fov / 2) * (_width / _height);
    expect(centre.x, lessThan(0.0));
    expect(
      -centre.x,
      inInclusiveRange(0.1 / halfWidth - 1e-3, 0.1 / nearHalfWidth + 1e-3),
    );
    expect(centre.y.abs(), lessThan(1e-4));

    // A corner is sky: at infinity, a sideways step does not move it.
    final corner = _at(v, 0, 0);
    expect(corner.x.abs(), lessThan(1e-5));
    expect(corner.y.abs(), lessThan(1e-5));
  });

  test('a camera turning moves the sky too', () {
    final it = _staged();
    _velocity(it);
    it.camera.setRotationYawPitchRoll(0.05, 0.0, 0.0);
    final v = _velocity(it);
    final corner = _at(v, 0, 0);
    expect(corner.x.abs(), greaterThan(1e-3));
  });

  test('without temporal on there is no velocity to show', () {
    final it = _staged();
    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
      settings: const RenderSettings(showVelocity: true),
    );
    expect(
      result.passes.map((p) => p.name),
      isNot(contains('camera velocity')),
    );
  });

  group('a node that moved', () {
    MeshNode box(_Staged it) => it.scene.meshes.first;

    test('writes its own motion where it now stands', () {
      // Mutation: skip `_encodeObjectVelocity` (return 0 at the top). The
      // camera did not move, so every pixel reads zero.
      final it = _staged();
      _velocity(it);
      box(it).setPosition(0.3, 0.0, -5.0);
      final v = _velocity(it);

      // The box's centre moved 0.3 m right at five metres: in UV, half of
      // 0.3 over the half width there, and positive because it went right.
      const fov = math.pi / 4;
      final halfWidth = 5.0 * math.tan(fov / 2) * (_width / _height);
      final nearHalfWidth = 4.5 * math.tan(fov / 2) * (_width / _height);
      // The box's new centre, a little right of the frame's.
      final x = (_width / 2 + 0.3 / (2 * halfWidth) * _width).round();
      final at = _at(v, x, _height ~/ 2);
      expect(
        at.x,
        inInclusiveRange(0.15 / halfWidth - 1e-3, 0.15 / nearHalfWidth + 1e-3),
      );
      expect(at.y.abs(), lessThan(1e-4));
      // The sky around it stood still.
      expect(_at(v, 0, 0).x.abs(), lessThan(1e-6));
    });

    test('stops at a wall in front of it', () {
      final it = _staged();
      // A wall between the camera and the box, covering the middle.
      final device = it.device;
      final wall = MeshNode(
        DeviceMesh.upload(device, CuboidShape().build()),
        Material(),
      )..setPosition(0.0, 0.0, -2.0);
      it.scene.add(wall);
      _velocity(it);
      box(it).setPosition(0.1, 0.0, -5.0);
      final v = _velocity(it);
      // Mutation: drop the depth comparison in `velocity.frag`'s mirror. The
      // box's motion paints over the wall that hides it.
      final centre = _at(v, _width ~/ 2, _height ~/ 2);
      expect(centre.x.abs(), lessThan(1e-6));
    });

    test('a batch moves by the placements it had last frame', () {
      final it = _staged();
      final batch = InstancedMeshNode(
        DeviceMesh.upload(it.device, CuboidShape().build()),
        Material(),
        capacity: 2,
      )..addInstance(Matrix4.translationValues(0.0, 0.0, -5.0));
      it.scene
        ..remove(box(it))
        ..add(batch);
      _velocity(it);
      // The batch's own node stays put; one instance moves.
      batch.setTransform(0, Matrix4.translationValues(0.3, 0.0, -5.0));
      final v = _velocity(it);
      const fov = math.pi / 4;
      final halfWidth = 5.0 * math.tan(fov / 2) * (_width / _height);
      final x = (_width / 2 + 0.3 / (2 * halfWidth) * _width).round();
      expect(_at(v, x, _height ~/ 2).x, greaterThan(0.1 / halfWidth));
    });
  });
}
