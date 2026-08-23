/// A pooled target is not handed out again while the GPU may still be reading.
///
///     flutter test test/frame_ring_test.dart
///
/// **The comment was right and the code did the other thing.** `render` retires
/// one slot of a three-slot ring at the top of every frame, and the counter
/// that chooses the slot was advanced *there* — before any pass ran. So a
/// texture released during frame N went into the slot the top of frame N + 1
/// retires: one frame of deferral where three were intended.
///
/// One frame is not enough. `CommandBuffer.submit` is asynchronous, and at a
/// hundred and twenty frames a second one frame is eight milliseconds; a debug
/// build's GPU work runs several frames behind. The pool hands a live target to
/// the next pass, and what that looks like is a draw missing from a frame — a
/// bar of a wireframe cage, a model inside it — which is invisible in a moving
/// scene and unmissable in a still one. It was reported as an editor that
/// flickers.
library;

import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d_graphics/testing.dart';
import 'package:flutter_test/flutter_test.dart';


void main() {
  test('a target released this frame is not reused for a full ring', () {
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final scene = Scene()..add(CameraNode());
    final view = RenderView(camera: scene.cameras.single);

    void frame() => renderer.render(
          width: 64,
          height: 64,
          scene: scene,
          views: <RenderView>[view],
          // Bloom acquires and releases pooled targets, which is what makes
          // this frame have anything to defer at all.
          settings: const RenderSettings(),
        );

    // How the pool fills is the whole of it. Each frame acquires the same
    // handful of targets; with a three-deep ring the first three frames each
    // allocate their own set and the fourth finds the first frame's waiting,
    // so the total stops climbing at three frames' worth.
    final created = <int>[];
    for (var i = 0; i < 8; i++) {
      frame();
      created.add(renderer.targetPool.createdCount);
    }

    final perFrame = created.first;
    expect(perFrame, greaterThan(0), reason: 'nothing was pooled at all');
    expect(created[2], perFrame * 3,
        reason: 'three frames should each have allocated their own set: '
            '$created');
    for (final total in created.skip(3)) {
      expect(total, perFrame * 3,
          reason: 'the pool kept allocating after the ring filled: $created');
    }

    // **This is what a one-frame deferral looks like**, and what this test
    // exists to refuse: the total would stop at one frame's worth, because
    // every target released by a frame is handed straight to the next one
    // while the GPU may still be reading it.
    expect(created.last, isNot(perFrame),
        reason: 'targets are being reused by the very next frame');
  });
}
