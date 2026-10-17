/// A skinning hook placed in the frame (D22b): it writes each claimed mesh's
/// vertices into a buffer resource of the frame, and the scene draws that
/// buffer in place of the mesh's own.
///
///     dart test test/skinning_hook_test.dart
///
/// Mutation: drop the copy from the CPU executor in `_SkinningStep.record`
/// and the fallback test sees no write; claim nothing in
/// `_SkinningState.begin` and the reader is never handed a buffer.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_shaders/kernel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One triangle over two joints: a rigid vertex on each, and one blended
/// across both with weights that sum to 0.7.
MeshData _skinnedTriangle() {
  const layout = VertexLayout.skinned;
  final stride = layout.floatsPerVertex;
  final data = Float32List(3 * stride);
  void vertex(int i, Vector3 position, List<double> joints, List<double> w) {
    final at = i * stride;
    data
      ..[at] = position.x
      ..[at + 1] = position.y
      ..[at + 2] = position.z
      ..[at + 4] = 1.0
      ..[at + 8] = 1.0
      ..[at + 11] = 1.0
      ..setAll(at + 12, const <double>[1, 1, 1, 1])
      ..setAll(at + 16, joints)
      ..setAll(at + 20, w);
  }

  vertex(
    0,
    Vector3(1, 0, 0),
    const <double>[0, 0, 0, 0],
    const <double>[1, 0, 0, 0],
  );
  vertex(
    1,
    Vector3(0, 1, 0),
    const <double>[1, 0, 0, 0],
    const <double>[1, 0, 0, 0],
  );
  vertex(
    2,
    Vector3(0, 0, 1),
    const <double>[0, 1, 0, 0],
    const <double>[0.4, 0.3, 0, 0],
  );
  return MeshData(
    layout: layout,
    vertices: data,
    indices: Uint32List.fromList(<int>[0, 1, 2]),
  );
}

/// A scene holding the triangle, skinned by two joints, the second turned
/// and moved; and the camera that looks at it.
(Scene, MeshNode, CameraNode) _scene(GraphicsDevice device) {
  final root = SceneNode(name: 'root');
  final bent = SceneNode(name: 'bent')
    ..setPosition(0.25, 0.5, 0.0)
    ..setRotation(Quaternion.axisAngle(Vector3(0, 0, 1), 0.6));
  final mesh =
      MeshNode(
          DeviceMesh.upload(device, _skinnedTriangle()),
          RenderMaterial(name: 'skin'),
        )
        ..skeleton = Skeleton(
          joints: <SceneNode>[root, bent],
          inverseBindMatrices: <Matrix4>[
            Matrix4.identity(),
            Matrix4.identity(),
          ],
        );
  final camera = CameraNode()..setPosition(0.0, 0.0, 4.0);
  camera.lookAt(Vector3.zero());
  final scene = Scene()
    ..add(root)
    ..add(bent)
    ..add(mesh)
    ..add(camera);
  return (scene, mesh, camera);
}

/// Hands on the scene's colour, and copies the skinned vertices it is given
/// into a buffer the host can read.
final class _Reader extends RenderNode {
  _Reader(this.copied);

  final List<Float32List> copied;

  @override
  String get name => 'test.skinned reader';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
    FrameResourceIds.skinnedVertices,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) {
    final resources = frame.resources;
    final skinned = resources.tryBuffer(FrameResourceIds.skinnedVertices);
    if (skinned != null) {
      final device = frame.device as CpuDevice;
      final readable = device.createBuffer(
        BufferDescriptor(
          lengthInBytes: skinned.lengthInBytes,
          usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
        ),
      );
      device.beginTransferPass()
        ..copyBufferToBuffer(skinned, 0, readable, 0, skinned.lengthInBytes)
        ..submit();
      final bytes = device.readBufferSync(readable);
      copied.add(
        Float32List.fromList(
          bytes.buffer.asFloat32List(
            bytes.offsetInBytes,
            bytes.lengthInBytes ~/ 4,
          ),
        ),
      );
      device.releaseStorageBuffer(readable);
    }
    resources.provide(
      FrameResourceIds.hdrColor,
      resources.texture(FrameResourceIds.hdrColor),
    );
  }
}

/// Fills its output with twos through a kernel, on whatever it was placed.
final class _Fill extends SkinningHook {
  const _Fill();

  @override
  bool claims(SkinningContext context) => true;

  @override
  List<ComputeKernel> get kernels => ComputeKernel.parseAll('''
compute Fill {
  workgroup 4;
  buffer out: f32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(out) { return; }
    out[i] = 2.0;
  }
}
''');

  @override
  bool record(SkinningContext context) {
    final compute = context.compute!;
    final stage = compute.stage('Fill');
    final floats = context.output!.lengthInBytes ~/ 4;
    compute.beginPass()
      ..bindPipeline(compute.device.createComputePipeline(stage))
      ..bindStorageBuffer(stage, 'out', context.output!)
      ..dispatch((floats + 3) ~/ 4)
      ..submit();
    return true;
  }
}

void main() {
  test('the CPU skinning reaches the scene as the frame\'s buffer', () async {
    const width = 32;
    final device = CpuDevice(
      width: width,
      height: width,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final registry = DeviceRegistry<Object>();
    final renderer = Renderer.create(device: device);
    final (scene, mesh, camera) = _scene(device);
    final copied = <Float32List>[];
    final hook = LinearBlendSkinning();
    registry.adopt(device);
    final placed = renderer.renderSteps.placeSkinningHook(hook);
    await renderer.renderSteps.whenPlaced();
    renderer.renderSteps.addNode(_Reader(copied));
    expect(renderer.hooks.skinningHooks, <SkinningHook>[hook]);

    renderer.render(
      width: width,
      height: width,
      scene: scene,
      views: <CameraView>[CameraView(camera: camera)],
    );

    mesh.skeleton!.update(mesh.worldMatrix);
    final blend = SkinBlend(_skinnedTriangle())
      ..blend(Float32List.fromList(mesh.skeleton!.matrices));
    final expected = standardVertices(blend.vertices, VertexLayout.skinned, 3);
    expect(copied, hasLength(1));
    // Bit for bit: the floats SkinBlend computes are the floats drawn.
    expect(copied.single, expected);
    expect(copied.single[3 * 16 - 16], isNot(0.0));
    placed.cancel();
    expect(renderer.hooks.skinningHooks, isEmpty);
  });

  test('a hook the drawing device cannot run is placed on the CPU, and the '
      'frame reads nothing back', () async {
    final device = FakeBackend(
      maxColorAttachments: 4,
      extraFeatures: const <DeviceFeature>[DeviceFeature.buffers],
    );
    final registry = DeviceRegistry<Object>();
    final cpu = registerCpuBackend(registry);
    addTearDown(cpu.cancel);
    final renderer = Renderer.create(device: device);
    final (scene, _, camera) = _scene(device);
    const hook = _Fill();
    registry.adopt(device);
    renderer.renderSteps.placeSkinningHook(hook);
    await renderer.renderSteps.whenPlaced();

    renderer.render(
      width: 16,
      height: 16,
      scene: scene,
      views: <CameraView>[CameraView(camera: camera)],
    );
    // The CPU's vertices reached the drawing device by an upload, and no
    // texture or buffer of it was read back.
    expect(device.calls.where((c) => c.name == 'writeBuffer'), hasLength(1));
    expect(device.readbacks, isEmpty);
    expect(device.calls.where((c) => c.name == 'readBuffer'), isEmpty);
  });
}
