/// `gfx-67n`: a run of identical opaque draws becomes one instanced call.
///
///     flutter test test/auto_batch_test.dart
///
/// **The run is already there to be found.** `SortMode.stateThenDepth` orders
/// the opaque half by pipeline and then by material, so a hundred nodes sharing
/// a geometry and a material arrive next to each other. What `gfx-67n` does is
/// notice, fill a pooled batch with their world transforms and draw it once.
///
/// **The row asked for byte for byte, and on the backend this file can measure
/// it holds.** That was not the expectation. The two stages do not compute the
/// same expressions: a plain mesh clips with `(viewProjection * model) *
/// position` and a batch with `viewProjection * (instance * position)`, because
/// the node's own matrix is where the instance transform came from, and the
/// instanced stage normalises the normal where the plain one does not. Both
/// tests below were written with the golden set's budget of eight and then
/// tightened to nought when they passed at nought — including the case with a
/// rotation and a scale on every node, which is where the two have the most
/// room to disagree.
///
/// **That is a statement about the software rasteriser and not about the other
/// three backends.** It computes in Dart doubles; Impeller, WebGL and WebGPU
/// compute in 32-bit floats, where those two expressions have far less room
/// before they part. Nothing here can run them, so the setting stays off by
/// default — which is also what keeps the seventy-eight goldens where they are.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A grid of [count] cubes, all sharing one mesh and one material.
Scene _field(
  CpuDevice device, {
  required int count,
  Material? material,
  bool sameMaterial = true,
  bool turned = false,
}) {
  final mesh = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3.all(0.6)).build(),
  );
  final shared = material ?? Material(name: 'shared');
  final scene = Scene();
  // A square grid rather than a long row, and the camera far enough back to
  // hold all of it: the first draft laid a hundred cubes out fifty wide, the
  // cull threw away eighty-two of them, and the batch it measured was the
  // eighteen that were left.
  final side = math.sqrt(count).ceil();
  for (var i = 0; i < count; i++) {
    scene.add(
      MeshNode(
          mesh,
          sameMaterial ? shared : Material(name: 'own $i'),
          name: 'cube $i',
        )
        ..setPosition(
          ((i % side) - side / 2) * 0.8,
          ((i ~/ side) - side / 2) * 0.8,
          0.0,
        )
        ..setRotationYawPitchRoll(
          turned ? i * 0.17 : 0.0,
          turned ? i * 0.09 : 0.0,
          turned ? i * 0.05 : 0.0,
        )
        ..setUniformScale(turned ? 0.7 + (i % 5) * 0.1 : 1.0),
    );
  }
  return scene
    ..add(
      LightNode(intensity: 4.0)
        ..setPosition(2.0, 4.0, 6.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 0.0, 16.0)
        ..lookAt(Vector3.zero()),
    );
}

Future<({List<int> pixels, FrameResult frame})> _draw(
  Scene scene,
  CpuDevice device, {
  required bool batched,
}) async {
  final renderer = Renderer.create(device: device);
  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(batchIdenticalDraws: batched),
  );
  final bytes = await device.readPixels(frame.frame);
  return (
    pixels: <int>[
      for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
    ],
    frame: frame,
  );
}

CpuDevice _device() => CpuDevice(
  width: _size,
  height: _size,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// The worst single-channel difference, and how many pixels differ at all.
({int worst, int differing}) _compare(List<int> a, List<int> b) {
  var worst = 0;
  var differing = 0;
  for (var i = 0; i < a.length; i += 4) {
    var here = 0;
    for (var c = 0; c < 3; c++) {
      final delta = (a[i + c] - b[i + c]).abs();
      if (delta > here) here = delta;
    }
    if (here > 0) differing++;
    if (here > worst) worst = here;
  }
  return (worst: worst, differing: differing);
}

void main() {
  test('a hundred identical meshes draw in one call', () async {
    // **The row's own acceptance, in the half that holds.** A hundred nodes
    // sharing a mesh and a material, sorted next to each other, become one
    // instanced draw.
    final device = _device();
    final scene = _field(device, count: 100);
    final batched = await _draw(scene, device, batched: true);
    final plain = await _draw(scene, device, batched: false);

    expect(batched.frame.batchedDraws, 100);
    expect(
      batched.frame.drawCalls,
      lessThan(plain.frame.drawCalls - 90),
      reason: 'the run was found and then drawn one at a time anyway',
    );
  });

  test('and the picture is the same picture, to the byte', () async {
    // Written with the golden set's budget of eight and tightened to nought
    // when it passed at nought. See the library comment: the two stages compute
    // different expressions and this backend's doubles carry both to the same
    // eight-bit answer.
    final device = _device();
    final scene = _field(device, count: 100);
    final batched = await _draw(scene, device, batched: true);
    final plain = await _draw(scene, device, batched: false);

    final diff = _compare(batched.pixels, plain.pixels);
    expect(
      diff.worst,
      0,
      reason: '${diff.differing} pixels differ, worst by ${diff.worst}',
    );
  });

  test('and it holds for nodes that are turned and scaled too', () async {
    // The case where the two stages have the most room to disagree: a rotation
    // and a uniform scale per node is where the instanced stage's `normalize`
    // and the plain stage's un-normalised inverse transpose actually part
    // company, and where the clip association has something to round.
    final device = _device();
    final scene = _field(device, count: 100, turned: true);
    final batched = await _draw(scene, device, batched: true);
    final plain = await _draw(scene, device, batched: false);

    expect(batched.frame.batchedDraws, 100);
    final diff = _compare(batched.pixels, plain.pixels);
    expect(
      diff.worst,
      0,
      reason: '${diff.differing} pixels differ, worst by ${diff.worst}',
    );
  });

  test('nothing is batched unless it is asked for', () async {
    // Which is what keeps the seventy-eight goldens where they are: the default
    // frame is the frame it always was, to the byte.
    final device = _device();
    final scene = _field(device, count: 100);
    final plain = await _draw(scene, device, batched: false);

    expect(plain.frame.batchedDraws, 0);
  });

  test('meshes with materials of their own are not merged', () async {
    // The identity rule, and the one that would silently draw a hundred
    // objects in somebody else's colour if it were a value comparison: two
    // materials that look alike are still two, because a caller can change one
    // of them next frame.
    final device = _device();
    final scene = _field(device, count: 100, sameMaterial: false);
    final batched = await _draw(scene, device, batched: true);

    expect(batched.frame.batchedDraws, 0);
  });

  test('a run shorter than the minimum is left alone', () async {
    // A batch costs the instanced pipeline coming in and the plain one going
    // out, and three draws do not pay for that.
    final device = _device();
    final scene = _field(device, count: 3);
    final batched = await _draw(scene, device, batched: true);

    expect(scene.meshes.length, 3);
    expect(batched.frame.batchedDraws, 0);
  });

  test('a second frame reuses the batch it built', () async {
    // The pool is what keeps this from costing more than it saves: a node and
    // a typed list per run per frame would be the allocation pattern the whole
    // render list was shaped to avoid.
    final device = _device();
    final scene = _field(device, count: 100);
    final renderer = Renderer.create(device: device);

    FrameResult frame() => renderer.render(
      width: _size,
      height: _size,
      scene: scene,
      views: <RenderView>[RenderView(camera: scene.cameras.single)],
      settings: const RenderSettings(batchIdenticalDraws: true),
    );

    expect(frame().batchedDraws, 100);
    expect(frame().batchedDraws, 100);
    expect(frame().batchedDraws, 100);
  });

  test('a mesh that moves moves in the batch too', () async {
    // The batch is refilled from the nodes' world transforms every frame, so
    // this is what catches a pool that kept last frame's placements.
    final device = _device();
    final scene = _field(device, count: 100);
    final before = await _draw(scene, device, batched: true);

    scene.meshes.first.setPosition(0.0, 0.0, 3.0);
    final after = await _draw(scene, device, batched: true);

    expect(after.frame.batchedDraws, 100);
    expect(_compare(before.pixels, after.pixels).differing, greaterThan(0));
  });
}
