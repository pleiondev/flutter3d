/// The renderer remembers where things were a frame ago, and only copies
/// what moved — `G2`.
///
///     dart test test/engine/frame_history_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final device = FakeBackend();
  final mesh = DeviceMesh.upload(device, CuboidShape().build());

  ({Renderer renderer, Scene scene, MeshNode moving, MeshNode still}) staged() {
    final moving = MeshNode(mesh, RenderMaterial())
      ..setPosition(0.0, 0.0, -5.0);
    final still = MeshNode(mesh, RenderMaterial())..setPosition(2.0, 0.0, -5.0);
    final scene = Scene()
      ..add(moving)
      ..add(still)
      ..add(CameraNode());
    final renderer = Renderer.create(device: device)
      ..frameHistory.tracking = true;
    return (renderer: renderer, scene: scene, moving: moving, still: still);
  }

  // One view object across frames: the history is kept per view. Through the
  // camera `staged` made, the first, since a test may add a second one.
  final views = Expando<RenderView>('test view');
  RenderView viewOf(Scene scene) =>
      views[scene] ??= RenderView(camera: scene.cameras.first);

  void draw(Renderer renderer, Scene scene) => renderer.render(
    width: 64,
    height: 48,
    scene: scene,
    views: <RenderView>[viewOf(scene)],
  );

  test('a node moved between two frames reports where it was', () {
    final (:renderer, :scene, :moving, :still) = staged();
    draw(renderer, scene);
    final before = moving.worldMatrix.clone();

    moving.setPosition(1.0, 0.0, -5.0);
    expect(renderer.frameHistory.moved(moving, viewOf(scene)), isTrue);
    expect(renderer.frameHistory.moved(still, viewOf(scene)), isFalse);
    expect(renderer.frameHistory.of(moving, viewOf(scene))!.world, before);
    expect(
      renderer.frameHistory.of(moving, viewOf(scene))!.world,
      isNot(moving.worldMatrix),
    );

    draw(renderer, scene);
    // Recorded again, so the new place is now the past.
    expect(renderer.frameHistory.moved(moving, viewOf(scene)), isFalse);
    expect(
      renderer.frameHistory.of(moving, viewOf(scene))!.world,
      moving.worldMatrix,
    );
    expect(renderer.frameHistory.of(moving, viewOf(scene))!.frame, 1);
  });

  test('an unmoved scene allocates nothing after its first frame', () {
    // Mutation: drop the early return on an unchanged key in `_record`. The
    // buffers are reused, so nothing allocates, but every node is copied
    // again every frame.
    final (:renderer, :scene, moving: _, still: _) = staged();
    final batch = InstancedMeshNode(mesh, RenderMaterial(), capacity: 4)
      ..addInstance(Matrix4.translationValues(0.0, 1.0, -5.0));
    scene.add(batch);
    draw(renderer, scene);
    final after = renderer.frameHistory.allocations;
    final copied = renderer.frameHistory.copies;
    expect(after, greaterThan(0));
    for (var i = 0; i < 3; i++) {
      draw(renderer, scene);
    }
    expect(renderer.frameHistory.allocations, after);
    expect(renderer.frameHistory.copies, copied);
    expect(renderer.frameHistory.of(batch, viewOf(scene))!.instanceCount, 1);
  });

  test('each view keeps last frame\'s view-projection', () {
    final (:renderer, :scene, moving: _, still: _) = staged();
    final camera = scene.cameras.single;
    final view = viewOf(scene);
    expect(renderer.frameHistory.viewProjection(view), isNull);
    draw(renderer, scene);
    final before = renderer.frameHistory.viewProjection(view)!.clone();
    expect(before, camera.viewProjection(64 / 48));
    camera.setPosition(0.0, 1.0, 0.0);
    draw(renderer, scene);
    expect(renderer.frameHistory.viewProjection(view), isNot(before));
    // A view of the same camera that was not drawn last frame has no past.
    expect(
      renderer.frameHistory.viewProjection(RenderView(camera: camera)),
      isNull,
    );
  });

  test('a renderer that is not tracking records nothing', () {
    final (:renderer, :scene, :moving, still: _) = staged();
    renderer.frameHistory.tracking = false;
    draw(renderer, scene);
    expect(renderer.frameHistory.of(moving, viewOf(scene)), isNull);
    expect(renderer.frameHistory.allocations, 0);
  });

  test('views drawn by separate render calls each keep their own past', () {
    // Mutation: answer `viewProjection` only for the renderer's last frame,
    // or keep one node copy for the renderer. The second call then erases
    // the first view's past, and its velocity is computed against nothing.
    final (:renderer, :scene, :moving, still: _) = staged();
    final camera = scene.cameras.single;
    final left = RenderView(camera: camera);
    final right = RenderView(camera: CameraNode()..setPosition(5.0, 0.0, 0.0));
    scene.add(right.camera);
    void drawBoth() {
      renderer
        ..render(width: 64, height: 48, scene: scene, views: [left])
        ..render(width: 64, height: 48, scene: scene, views: [right]);
    }

    drawBoth();
    final leftBefore = renderer.frameHistory.viewProjection(left)!.clone();
    final worldBefore = moving.worldMatrix.clone();
    moving.setPosition(1.0, 0.0, -5.0);
    // Drawing the right view records the moved node for it, and must not
    // make the left view's past the present.
    renderer.render(width: 64, height: 48, scene: scene, views: [right]);
    expect(renderer.frameHistory.viewProjection(left), leftBefore);
    expect(renderer.frameHistory.moved(moving, left), isTrue);
    expect(renderer.frameHistory.of(moving, left)!.world, worldBefore);
    expect(renderer.frameHistory.moved(moving, right), isFalse);
  });

  test('an origin shift is no motion to the history', () {
    // Mutation: skip `_rebase` in `of`, or the matrix fix-up in
    // `viewProjection`. The past is then in the old space, and a floating
    // origin reads as every node and the camera jumping by the shift.
    final (:renderer, :scene, :moving, still: _) = staged();
    final view = viewOf(scene);
    final other = RenderView(camera: CameraNode());
    scene.add(other.camera);
    renderer.render(width: 64, height: 48, scene: scene, views: [view]);
    final world = moving.worldMatrix.clone();
    final seen = renderer.frameHistory
        .viewProjection(view)!
        .transformed(Vector4(0.0, 0.0, -5.0, 1.0));

    // Every node moves ten metres down X in the scene's space. Another
    // view's frame tells the renderer, and `view`'s past is then read in
    // the new space.
    scene.shiftOrigin(const WorldPosition(10.0, 0.0, 0.0));
    renderer.render(width: 64, height: 48, scene: scene, views: [other]);
    final past = renderer.frameHistory.of(moving, view)!.world;
    expect(
      past.getTranslation().x,
      closeTo(world.getTranslation().x - 10.0, 1e-4),
    );
    expect(
      past.getTranslation().x,
      closeTo(moving.worldMatrix.getTranslation().x, 1e-4),
    );
    final now = renderer.frameHistory
        .viewProjection(view)!
        .transformed(Vector4(-10.0, 0.0, -5.0, 1.0));
    expect(now.x / now.w, closeTo(seen.x / seen.w, 1e-5));
    expect(now.y / now.w, closeTo(seen.y / seen.w, 1e-5));
  });

  test('a view nobody draws any more gives its state back', () {
    // Mutation: drop `_evictIdleViewStates` from `render`. Views made afresh
    // every frame for two cameras then keep one state each, for ever.
    final (:renderer, :scene, moving: _, still: _) = staged();
    final other = CameraNode()..setPosition(3.0, 0.0, 0.0);
    scene.add(other);
    final once = RenderView(camera: other);
    renderer.render(width: 64, height: 48, scene: scene, views: [once]);
    expect(renderer.frameHistory.viewProjection(once), isNotNull);
    for (var i = 0; i <= Renderer.viewIdleFrames + 1; i++) {
      draw(renderer, scene);
    }
    expect(renderer.frameHistory.viewProjection(once), isNull);
  });
}
