/// `FrameResult.triangles`/`instances` — `view-17`'s own row: a cube plus
/// instanced cubes gives the formula, checked directly rather than read off
/// a picture.
///
/// **The draw counts here are the scene pass's own, not the frame's** — and
/// they used to be the frame's, because the frame's *were* the scene pass's
/// plus the composite. `gfx-01n` found that the shadow map and the whole
/// bloom ladder were drawing and counting nothing, so the totals moved the
/// day they started counting; what these tests are actually about never did.
/// "How many draws did the cube take" is a question about the pass the cube
/// is drawn in, and `FrameResult.passes` lets it be asked that way.
///
/// **And the extra draw these tests attributed to the procedural sky was the
/// composite's.** The header used to say `renderer_sky_pass.dart` draws a
/// full-screen triangle every frame "with no scene environment needed to
/// turn it on", and every count here carried a `+ 1` for it. Asked per pass,
/// a lone cube gives `scene: 1` — the cube — with the sky nowhere, and the
/// `+ 1` that made the old total two was the composite at the end of the
/// frame. Nothing was broken by it, and nothing would have caught it either:
/// two numbers that happen to agree read exactly like one number that is
/// right.
///
/// [FrameResult.triangles]/[FrameResult.instances] still deliberately count
/// neither — a full-screen triangle is a screen-space trick, not scene
/// content, the same reason [FrameResult.culled] and
/// [FrameResult.skinnedDraws] are scoped to meshes rather than to every draw
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

/// The draws the scene pass itself made — what every count in this file is
/// about, told apart from the shadow map and the post chain by name.
int _sceneDraws(FrameResult frame) => frame.passes
    .where((FramePass pass) => pass.name == 'scene')
    .fold<int>(0, (int sum, FramePass pass) => sum + pass.drawCalls);

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
    expect(_sceneDraws(frame), 0, reason: 'nothing to draw, so nothing drawn');
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
    expect(_sceneDraws(frame), 1, reason: 'the cube, and only the cube');
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
    // The lone cube, and the whole batch in one call.
    expect(_sceneDraws(frame), 2);
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
    expect(_sceneDraws(frame), 0, reason: 'nothing to draw, so nothing drawn');
  });
}
