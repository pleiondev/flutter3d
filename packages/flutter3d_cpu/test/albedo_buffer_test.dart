/// A pass that reads the albedo buffer finds each surface's own colour in
/// it — `L5`.
///
///     dart test test/albedo_buffer_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 16;

final class _AlbedoProbe extends RenderNode {
  _AlbedoProbe(this._device);

  final CpuDevice _device;
  Float32List? last;

  @override
  String get name => 'albedo probe';

  @override
  FramePhase get preferredPhase => FramePhase.present;

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.frame];

  // Optional, which is how a reader that can do without it asks.
  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
    FrameResourceIds.albedoBuffer,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    final albedo = frame.resources.tryTexture(FrameResourceIds.albedoBuffer);
    last = albedo == null ? null : _device.readHdrPixels(albedo);
    frame.resources.provide(
      FrameResourceIds.frame,
      frame.resources.texture(FrameResourceIds.frame),
    );
  }
}

({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) _stage(
  Material material, {
  int attachments = 3,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    maxColorAttachments: attachments,
  );
  final camera = CameraNode();
  final scene = Scene()
    ..add(
      MeshNode(DeviceMesh.upload(device, CuboidShape().build()), material)
        ..setPosition(0.0, 0.0, -2.0),
    )
    ..add(camera);
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

void main() {
  test('a lit surface leaves its own colour, as it was authored', () {
    final it = _stage(
      Material(
        lighting: LightingModel.lambert,
        baseColor: Vector4(0.8, 0.2, 0.1, 1.0),
      ),
    );
    final probe = _AlbedoProbe(it.device);
    it.renderer
      ..addNode(probe)
      ..render(
        width: _size,
        height: _size,
        scene: it.scene,
        views: <RenderView>[RenderView(camera: it.camera)],
      );
    final at = (_size ~/ 2 * _size + _size ~/ 2) * 4;
    final albedo = probe.last!;
    // The tint is authored in sRGB and the buffer stores sRGB, so the round
    // trip through linear lands back on what was written.
    expect(albedo[at], closeTo(0.8, 0.01));
    expect(albedo[at + 1], closeTo(0.2, 0.01));
    expect(albedo[at + 2], closeTo(0.1, 0.01));
    expect(albedo[at + 3], 1.0);
    // The sky around it is the clear: nothing drawn, nothing reflected.
    expect(albedo[3], 0.0);
  });

  test('an unlit surface reflects nothing', () {
    final it = _stage(
      Material(
        lighting: LightingModel.unlit,
        baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
      ),
    );
    final probe = _AlbedoProbe(it.device);
    it.renderer
      ..addNode(probe)
      ..render(
        width: _size,
        height: _size,
        scene: it.scene,
        views: <RenderView>[RenderView(camera: it.camera)],
      );
    final at = (_size ~/ 2 * _size + _size ~/ 2) * 4;
    expect(probe.last![at], 0.0);
  });

  test('a device that opens two attachments has no albedo buffer to read', () {
    final it = _stage(Material(), attachments: 2);
    final probe = _AlbedoProbe(it.device);
    (it.renderer..addNode(probe)).render(
      width: _size,
      height: _size,
      scene: it.scene,
      views: <RenderView>[RenderView(camera: it.camera)],
    );
    expect(probe.last, isNull);
  });
}
