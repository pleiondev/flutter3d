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

import 'dart:math' as math;
import 'dart:typed_data';

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

  test('a hole in a masked material picks what is behind it', () async {
    // A fence in front of the left box, turned to face the camera: a red
    // plane three metres wide at z = −4, textured with two texels — the left
    // one opaque, the right one clear — and masked at a half, so its right
    // half is a hole. A click on the solid half answers the fence; a click
    // through the hole answers the box behind it. And the picture agrees,
    // which is the whole claim of picking by pixel: the pixel through the
    // hole is the box's white, not the fence's red.
    //
    // Where the clicks land: at z = −4 with a field of view of one radian
    // and a 3:2 frame, half the width is 3.28 metres, so x = −2.75 — the
    // middle of the solid half — is 0.08 of the way across and x = −1.25 —
    // the middle of the hole — is 0.31. The box behind spans x from −3.5 to
    // −0.5, so the hole looks onto its face.
    //
    // Mutation: write the id without the discard — both clicks answer the
    // fence; drop the discard from the scene pass instead — the picture shows
    // red where the pick says box, and this test is what tells the two apart.
    final it = _twoBoxes();
    final holes = it.device.createTextureFromPixels(
      width: 2,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[255, 255, 255, 255, 255, 255, 255, 0]),
      ),
    )!;
    final fence =
        MeshNode(
            DeviceMesh.upload(
              it.device,
              const PlaneShape(width: 3.0, depth: 3.0).build(),
            ),
            Material(
              name: 'fence',
              lighting: LightingModel.unlit,
              baseColor: Vector4(1.0, 0.0, 0.0, 1.0),
              albedo: holes,
              albedoSampler: SamplerOptions.nearestClamp,
              alphaMode: MaterialAlphaMode.mask,
              alphaCutoff: 0.5,
            ),
            name: 'fence',
          )
          ..setPosition(-2.0, 0.0, -4.0)
          // The plane lies in XZ facing +Y; a quarter turn about X stands it up
          // facing +Z, towards the camera, with u still running left to right.
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
          );
    it.scene.add(fence);

    final solid = it.renderer.pickPixel(0.08, 0.5);
    final hole = it.renderer.pickPixel(0.31, 0.5);
    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[it.view],
    );
    expect((await solid)?.name, 'fence');
    expect((await hole)?.name, 'left');

    final pixels = (await it.device.readPixels(
      result.frame,
    ))!.buffer.asUint8List();
    int channel(double u, int c) =>
        pixels[((_height ~/ 2) * _width + (u * _width).floor()) * 4 + c];
    // Red against green rather than green against zero: the tone curve pulls
    // a saturated red towards white on its way to the display, so the green
    // is not nought — but it is well under the red, and on the box it is not.
    expect(channel(0.08, 0), greaterThan(150), reason: 'the fence is red');
    expect(channel(0.08, 1), lessThan(channel(0.08, 0) - 80));
    expect(channel(0.31, 1), greaterThan(150), reason: 'the box is white');
  });

  test('a blended surface is picked as though it were opaque', () async {
    // The other half of the rule the fence tests. A hole says "there is
    // nothing here" and is discarded in both passes; blending says "there is
    // something here, faintly", and the pass picks it — glass, a translucent
    // marker, an additive flash all answer with themselves. This is the case
    // where the pick and the eye deliberately disagree, so it is written down
    // as a test rather than left to whichever way the pass happened to fall.
    //
    // A red pane at half alpha, two metres wide and five tall, at z = −4 in
    // front of the left box — whose near face is at z = −4.5, since a cuboid
    // three metres on a side centred at z = −6 reaches half way back to the
    // camera. The frame is 6.56 metres across at the pane and 7.37 at that
    // face, so the pane shows as u 0.04 to 0.35 against the box's 0.03 to
    // 0.43, and the pane overhangs it top and bottom where the box stops at
    // v 0.20. Three points come out of that: (0.25, 0.5) is the pane over the
    // box, (0.25, 0.05) the pane over nothing, and (0.40, 0.5) the box past
    // the pane's edge.
    //
    // Mutation: leave the transparent half out of the id pass — the click on
    // the pane answers "left", and the note on `pickPixel` saying otherwise
    // becomes a description of nothing.
    final it = _twoBoxes();
    final glass =
        MeshNode(
            DeviceMesh.upload(
              it.device,
              const PlaneShape(width: 2.0, depth: 5.0).build(),
            ),
            Material(
              name: 'glass',
              lighting: LightingModel.unlit,
              baseColor: Vector4(1.0, 0.0, 0.0, 0.5),
              alphaMode: MaterialAlphaMode.blend,
            ),
            name: 'glass',
          )
          ..setPosition(-2.0, 0.0, -4.0)
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
          );
    it.scene.add(glass);

    final through = it.renderer.pickPixel(0.25, 0.5);
    final alone = it.renderer.pickPixel(0.25, 0.05);
    final past = it.renderer.pickPixel(0.40, 0.5);
    final result = it.renderer.render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[it.view],
    );
    expect((await through)?.name, 'glass', reason: 'the pane, not the box');
    expect((await alone)?.name, 'glass');
    expect((await past)?.name, 'left', reason: 'past the pane, the box');

    // And the eye does see the box through it, which is what makes this a
    // disagreement worth naming: the pane over the box is far brighter in
    // green than the same pane over the background, because the box's white
    // is what is coming through.
    final pixels = (await it.device.readPixels(
      result.frame,
    ))!.buffer.asUint8List();
    int channel(double u, double v, int c) =>
        pixels[(((v * _height).floor() * _width) + (u * _width).floor()) * 4 +
            c];
    expect(channel(0.25, 0.5, 1), greaterThan(channel(0.25, 0.05, 1) + 60));
    expect(channel(0.25, 0.5, 0), greaterThan(200), reason: 'and it is red');
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
