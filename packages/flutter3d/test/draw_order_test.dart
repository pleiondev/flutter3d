/// An order between nodes that share a material — `P7`, `MeshNode.drawOrder`.
///
///     flutter test test/draw_order_test.dart
///
/// The material's bucket was the only explicit order there was, and two nodes
/// sharing a material could not be put in one without a copy of it. These
/// claims are about the sort key and about the batching that reads the sorted
/// list: neither may let a node's order be undone.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
// ignore: implementation_imports
import 'package:flutter3d_core/src/engine/render/render_list.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Boxes in a row along the view axis, nearest first, all of [material],
/// each named by its order in [orders].
({Scene scene, CameraNode camera}) _row(
  List<int> orders,
  engine.RenderMaterial material, {
  MeshGeometry? geometry,
}) {
  final scene = Scene();
  final mesh =
      geometry ?? CpuMesh(CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build());
  for (var i = 0; i < orders.length; i++) {
    scene.add(
      MeshNode(mesh, material, name: 'node $i')
        ..drawOrder = orders[i]
        // Spread along the view axis, so a depth term that outranked the
        // order would put them in another order.
        ..setPosition(0.0, 0.0, 10.0 + i * 5.0),
    );
  }
  final camera = scene.add(CameraNode())..lookAt(Vector3(0.0, 0.0, 1.0));
  return (scene: scene, camera: camera);
}

/// The names of the drawn nodes in the order the list sorted them, opaque
/// half or transparent half.
List<String> _sorted(
  List<int> orders, {
  engine.RenderMaterial? material,
  bool transparent = false,
}) {
  final world = _row(
    orders,
    material ??
        engine.RenderMaterial(
          lighting: LightingModel.unlit,
          baseColor: LinearColor.fromSrgb(
            1.0,
            1.0,
            1.0,
            transparent ? 0.5 : 1.0,
          ),
          alphaMode: transparent
              ? MaterialAlphaMode.blend
              : MaterialAlphaMode.opaque,
        ),
  );
  final view = RenderView(camera: world.camera);
  final list = RenderList()
    ..build(
      world.scene,
      view,
      viewMatrix: world.camera.viewMatrix,
      frustum: Frustum.matrix(world.camera.viewProjection(1.0)),
    )
    ..sort(view);
  return <String>[
    for (final index in transparent ? list.transparent : list.opaque)
      list.itemAt(index).requireNode.name ?? '?',
  ];
}

void main() {
  test('nodes sharing a material are drawn in their order, lowest first', () {
    // Mutation: leave `drawOrder` out of the bucket in `_sortKey`, and the
    // shared material sorts them by depth, nearest first.
    expect(_sorted(<int>[2, -1, 0]), <String>['node 1', 'node 2', 'node 0']);
  });

  test('the order holds in the transparent half too', () {
    // Far to near is the transparent half's own sort, so without the order
    // the farthest node would come first.
    expect(_sorted(<int>[-1, 0, 1], transparent: true), <String>[
      'node 0',
      'node 1',
      'node 2',
    ]);
  });

  test("a node's order adds to its material's bucket", () {
    final material = engine.RenderMaterial(
      lighting: LightingModel.unlit,
      drawBucket: 3,
    );
    // Bucket three plus minus four is minus one: before an ordinary node of
    // the same material at nought, which is three.
    expect(_sorted(<int>[0, -4], material: material), <String>[
      'node 1',
      'node 0',
    ]);
  });

  test('nodes of different orders are never one instanced draw', () {
    // Mutation: drop the order from the batching's run test, and a run that
    // crosses from one order to the next is drawn at the first one's place.
    // Six on each side, enough for a run either side to batch on its own.
    const size = 48;
    final device = CpuDevice(
      width: size,
      height: size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final mesh = DeviceMesh.upload(device, CuboidShape().build());
    final world = _row(
      <int>[for (var i = 0; i < 12; i++) i < 6 ? 0 : 1],
      engine.RenderMaterial(lighting: LightingModel.unlit),
      geometry: mesh,
    );
    FrameResult draw({required bool batched}) =>
        Renderer.create(device: device).render(
          width: size,
          height: size,
          scene: world.scene,
          views: <RenderView>[RenderView(camera: world.camera)],
          settings: RenderSettings(batchIdenticalDraws: batched),
        );
    final batched = draw(batched: true);
    final plain = draw(batched: false);
    expect(batched.batchedDraws, 12);
    // Two instanced draws stand for twelve: ten calls fewer. One run of
    // twelve across the boundary would be eleven fewer.
    expect(plain.drawCalls - batched.drawCalls, 10);
  });
}
