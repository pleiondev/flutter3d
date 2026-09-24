/// The renderer remembers where things were a frame ago, and only copies
/// what moved — `G2`.
///
///     dart test test/engine/frame_history_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final device = FakeBackend();
  final mesh = DeviceMesh.upload(device, CuboidShape().build());

  ({Renderer renderer, Scene scene, MeshNode moving, MeshNode still}) staged() {
    final moving = MeshNode(mesh, Material())..setPosition(0.0, 0.0, -5.0);
    final still = MeshNode(mesh, Material())..setPosition(2.0, 0.0, -5.0);
    final scene = Scene()
      ..add(moving)
      ..add(still)
      ..add(CameraNode());
    final renderer = Renderer.create(device: device)
      ..frameHistory.tracking = true;
    return (renderer: renderer, scene: scene, moving: moving, still: still);
  }

  void draw(Renderer renderer, Scene scene) => renderer.render(
    width: 64,
    height: 48,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
  );

  test('a node moved between two frames reports where it was', () {
    final (:renderer, :scene, :moving, :still) = staged();
    draw(renderer, scene);
    final before = moving.worldMatrix.clone();

    moving.setPosition(1.0, 0.0, -5.0);
    expect(renderer.frameHistory.moved(moving), isTrue);
    expect(renderer.frameHistory.moved(still), isFalse);
    expect(renderer.frameHistory.of(moving)!.world, before);
    expect(renderer.frameHistory.of(moving)!.world, isNot(moving.worldMatrix));

    draw(renderer, scene);
    // Recorded again, so the new place is now the past.
    expect(renderer.frameHistory.moved(moving), isFalse);
    expect(renderer.frameHistory.of(moving)!.world, moving.worldMatrix);
    expect(renderer.frameHistory.of(moving)!.frame, 1);
  });

  test('an unmoved scene allocates nothing after its first frame', () {
    // Mutation: drop the early return on an unchanged key in `_record`. The
    // buffers are reused, so nothing allocates, but every node is copied
    // again every frame.
    final (:renderer, :scene, moving: _, still: _) = staged();
    final batch = InstancedMeshNode(mesh, Material(), capacity: 4)
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
    expect(renderer.frameHistory.of(batch)!.instanceCount, 1);
  });

  test('each view keeps last frame\'s view-projection', () {
    final (:renderer, :scene, moving: _, still: _) = staged();
    expect(renderer.frameHistory.viewProjection(0), isNull);
    draw(renderer, scene);
    final before = renderer.frameHistory.viewProjection(0)!.clone();
    scene.cameras.single.setPosition(0.0, 1.0, 0.0);
    draw(renderer, scene);
    expect(renderer.frameHistory.viewProjection(0), isNot(before));
    expect(renderer.frameHistory.viewProjection(1), isNull);
  });

  test('a renderer that is not tracking records nothing', () {
    final (:renderer, :scene, :moving, still: _) = staged();
    renderer.frameHistory.tracking = false;
    draw(renderer, scene);
    expect(renderer.frameHistory.of(moving), isNull);
    expect(renderer.frameHistory.allocations, 0);
  });
}
