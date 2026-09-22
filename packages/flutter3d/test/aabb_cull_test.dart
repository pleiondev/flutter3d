/// `gfx-61n`: the cull tests the box, not the sphere drawn around it.
///
///     flutter test test/aabb_cull_test.dart
///
/// **The work was already being done and thrown away.**
/// `MeshNode._refreshBounds` fills the world AABB and the bounding sphere in
/// one call, and the cull path reads `worldBoundsCentre`, which triggers that
/// same call. So the exact box was computed on the culling path and then
/// discarded in favour of the sphere derived from it.
///
/// What that cost is worst where a mesh is least like a ball. A sphere around
/// a box has up to `sqrt(3)` times its half extent, so a wall, a corridor
/// floor or a fence reads as a ball the length of its longest side and
/// survives the frustum from well outside it. The pipeline comparison found
/// this and the refuter is the one who priced it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A long thin slab placed at [at], drawn through a narrow camera.
///
/// Thin on two axes and long on the third, which is the shape the sphere lies
/// about: a plank 20 long and 0.1 thick has a bounding sphere of radius 10.
FrameResult _frame(Vector3 at) {
  final renderer = Renderer.create(device: FakeBackend());
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          FakeBackend(),
          CuboidShape(size: Vector3(20, 0.1, 0.1)).build(),
        ),
        Material(name: 'plank'),
      )..setPosition(at.x, at.y, at.z),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 6.0));

  return renderer.render(
    width: 64,
    height: 64,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: const RenderSettings(),
  );
}

/// How many meshes the scene pass actually drew.
int _drawn(FrameResult result) =>
    result.passes.firstWhere((p) => p.name == 'scene').drawCalls;

void main() {
  test('a plank in front of the camera is drawn', () {
    // The control. Without it the test below would pass on a cull that
    // rejects everything.
    expect(_drawn(_frame(Vector3(0.0, 0.0, 0.0))), greaterThan(0));
  });

  test('a plank whose sphere reaches the frustum and whose box does not is '
      'culled', () async {
    // **The row's claim.** The plank is 20 long on x and a tenth thick on the
    // other two, so its bounding sphere has a radius of about 10 while the box
    // is a tenth deep. Pushed far along y, the box is nowhere near the
    // frustum and the sphere still crosses it.
    //
    // Under the old test this mesh was drawn; under the box test it is not.
    expect(_drawn(_frame(Vector3(0.0, 9.0, 0.0))), 0);
  });

  test('a mesh that opts out of culling is drawn wherever it is', () {
    // `frustumCulled` is the caller's own escape hatch and the box test has to
    // leave it alone: a sky dome, a held weapon or an editor gizmo is placed
    // somewhere the frustum says is empty on purpose.
    final renderer = Renderer.create(device: FakeBackend());
    final scene = Scene()
      ..add(
        MeshNode(
            DeviceMesh.upload(
              FakeBackend(),
              CuboidShape(size: Vector3(20, 0.1, 0.1)).build(),
            ),
            Material(name: 'plank'),
          )
          ..setPosition(0.0, 9.0, 0.0)
          ..frustumCulled = false,
      )
      ..add(CameraNode()..setPosition(0.0, 0.0, 6.0));

    final result = renderer.render(
      width: 64,
      height: 64,
      scene: scene,
      views: <RenderView>[RenderView(camera: scene.cameras.single)],
      settings: const RenderSettings(),
    );

    expect(_drawn(result), greaterThan(0));
  });
}
