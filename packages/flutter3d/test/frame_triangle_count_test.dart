/// `FrameResult.triangles`/`instances` — `view-17`'s own row: a cube plus
/// instanced cubes gives the formula, checked directly rather than read off
/// a picture.
///
/// **`drawCalls` in every test here is one more than the scene's own meshes
/// would suggest** — `renderer_sky_pass.dart` draws a full-screen triangle
/// for the procedural sky every frame, with no scene environment needed to
/// turn it on, and increments `drawCalls` for it outside `_encodeNode`
/// (`renderer_mesh_encode.dart`). [FrameResult.triangles]/[FrameResult.
/// instances] deliberately do not count it: it is a screen-space background
/// trick, not scene content, the same reason [FrameResult.culled] and
/// [FrameResult.skinnedDraws] are scoped to meshes rather than every draw
/// the renderer issues.
///
///     flutter test test/frame_triangle_count_test.dart
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 64;

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  return (device: device, renderer: Renderer.create(device: device));
}

void main() {
  test('an empty scene draws no triangles and no instances', () {
    final engine = _engine();
    final scene = Scene();
    final camera = CameraNode()..setPosition(0.0, 0.0, 4.0);

    final frame = engine.renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );

    expect(frame.triangles, 0);
    expect(frame.instances, 0);
    expect(frame.drawCalls, 1, reason: 'the procedural sky, drawn regardless');
  });

  test('a lone cube draws its own 12 triangles and no instances', () {
    final engine = _engine();
    final scene = Scene();
    final camera = CameraNode()..setPosition(0.0, 0.0, 4.0);
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          engine.device,
          CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
        ),
        Material(name: 'a', baseColor: Vector4(0.7, 0.6, 0.5, 1.0)),
      ),
    );

    final frame = engine.renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );

    expect(frame.triangles, 12);
    expect(frame.instances, 0);
    expect(frame.drawCalls, 2, reason: 'the cube, plus the procedural sky');
  });

  test('a cube plus a batch of N instanced cubes: triangles == 12 + 12*N, '
      'instances == N', () {
    final engine = _engine();
    final scene = Scene();
    final camera = CameraNode()..setPosition(0.0, 0.0, 8.0);

    scene.add(
      MeshNode(
        DeviceMesh.upload(
          engine.device,
          CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
        ),
        Material(name: 'lone', baseColor: Vector4(0.7, 0.6, 0.5, 1.0)),
        name: 'lone',
      ),
    );

    const instanceCount = 5;
    final batch = InstancedMeshNode(
      DeviceMesh.upload(
        engine.device,
        CuboidShape(size: Vector3(0.3, 0.3, 0.3)).build(),
      ),
      Material(name: 'batch', baseColor: Vector4(0.3, 0.4, 0.7, 1.0)),
      capacity: instanceCount,
      name: 'batch',
    );
    for (var i = 0; i < instanceCount; i++) {
      batch.addInstance(
        Matrix4.identity()..setTranslationRaw(i * 0.6 - 1.2, 1.5, 0.0),
      );
    }
    scene.add(batch);

    final frame = engine.renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );

    expect(frame.triangles, 12 + 12 * instanceCount);
    expect(frame.instances, instanceCount);
    // The lone cube, the whole batch in one call, and the procedural sky.
    expect(frame.drawCalls, 3);
  });

  test('an instanced batch with nothing in it draws no triangles, no call', () {
    final engine = _engine();
    final scene = Scene();
    final camera = CameraNode()..setPosition(0.0, 0.0, 4.0);
    scene.add(
      InstancedMeshNode(
        DeviceMesh.upload(
          engine.device,
          CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build(),
        ),
        Material(name: 'empty', baseColor: Vector4(0.7, 0.6, 0.5, 1.0)),
        capacity: 4,
      ),
    );

    final frame = engine.renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );

    expect(frame.triangles, 0);
    expect(frame.instances, 0);
    expect(frame.drawCalls, 1, reason: 'the procedural sky, drawn regardless');
  });
}
