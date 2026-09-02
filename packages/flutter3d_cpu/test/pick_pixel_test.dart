/// Picking by pixel, drawn: the node under a point is the node whose pixels
/// are there.
///
///     flutter test test/pick_pixel_test.dart
///
/// The pass is pinned against the fake device in
/// `flutter3d/test/pick_pixel_test.dart`; this is the pass run through the
/// software rasteriser, with `object_id.frag`'s transcription writing the ids
/// and a real readback of one pixel reading them, so the answer is a node
/// because the rasteriser put it there and for no other reason.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

({CpuDevice device, Renderer renderer, Scene scene, RenderView view})
_twoBoxes() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  MeshNode box(String name, double x) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: Vector3.all(3.0)).build()),
    Material(name: name, lighting: LightingModel.unlit),
    name: name,
  )..setPosition(x, 0.0, -6.0);
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 100.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -1.0));
  final scene = Scene()
    ..add(box('left', -2.0))
    ..add(box('right', 2.0))
    ..add(camera);
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    view: RenderView(camera: camera),
  );
}

void main() {
  test('answers the node whose pixels are under the point', () async {
    // Two boxes either side of the middle, and the gap between them. At
    // z = −6 with a field of view of one radian the frame is about ten metres
    // wide, so a quarter of the way across lands on the left box, three
    // quarters on the right, and the exact middle on nothing.
    //
    // Mutation: decode the id from the green byte rather than the red — every
    // answer becomes null; number the draws from zero — the left box reads
    // as nothing and the right as the left.
    final it = _twoBoxes();
    final left = it.renderer.pickPixel(0.25, 0.5);
    final right = it.renderer.pickPixel(0.75, 0.5);
    final gap = it.renderer.pickPixel(0.5, 0.5);
    final sky = it.renderer.pickPixel(0.5, 0.02);
    it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[it.view],
    );

    expect((await left)?.name, 'left');
    expect((await right)?.name, 'right');
    expect(await gap, isNull);
    expect(await sky, isNull);
  });

  test('the nearer of two overlapping meshes wins', () async {
    // A small box in front of the left one, on the same line of sight: a
    // quarter of the way across is x = −2.46 at z = −6 and x = −1.23 at
    // z = −3, halfway there. The depth test is what decides, exactly as it
    // did for the picture. Mutation: leave depth writes off in the id pass —
    // the box drawn last wins whatever its distance, and the scene draws
    // front to back, so the far one is last.
    final it = _twoBoxes();
    final near = MeshNode(
      DeviceMesh.upload(it.device, CuboidShape(size: Vector3.all(0.6)).build()),
      Material(name: 'near', lighting: LightingModel.unlit),
      name: 'near',
    )..setPosition(-1.23, 0.0, -3.0);
    it.scene.add(near);

    final at = it.renderer.pickPixel(0.25, 0.5);
    it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[it.view],
    );
    expect((await at)?.name, 'near');
  });

  test('an instanced batch answers as the batch', () async {
    final it = _twoBoxes();
    for (final mesh in List<MeshNode>.of(it.scene.meshes)) {
      it.scene.remove(mesh);
    }
    final batch = InstancedMeshNode(
      DeviceMesh.upload(it.device, CuboidShape(size: Vector3.all(3.0)).build()),
      Material(name: 'batch', lighting: LightingModel.unlit),
      capacity: 2,
      name: 'batch',
    );
    batch.addInstance(Matrix4.translation(Vector3(-2.0, 0.0, -6.0)));
    batch.addInstance(Matrix4.translation(Vector3(2.0, 0.0, -6.0)));
    it.scene.add(batch);

    final left = it.renderer.pickPixel(0.25, 0.5);
    final gap = it.renderer.pickPixel(0.5, 0.5);
    it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[it.view],
    );
    expect(identical(await left, batch), isTrue);
    expect(await gap, isNull);
  });

  test('the picture is not touched by the pass', () async {
    // The id pass draws into a target of its own. Mutation: draw into the
    // frame — the frame comes back as ids.
    final it = _twoBoxes();
    final plain = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[it.view],
    );
    final before = (await it.device.readPixels(
      plain.frame,
    ))!.buffer.asUint8List();
    it.renderer.pickPixel(0.25, 0.5).ignore();
    final picked = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[it.view],
    );
    final after = (await it.device.readPixels(
      picked.frame,
    ))!.buffer.asUint8List();
    expect(after, equals(before));
  });
}
