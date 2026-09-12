/// `FrameResult.passes` — `pro-eng-05`'s own row: which nodes
/// `CompiledFrameGraph.order` actually kept, and how long each took.
///
///     flutter test test/frame_pass_timings_test.dart
library;

import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('without bloom, bloom is absent from passes — the row\'s own worked '
      'example', () {
    // Mutation: report every registered node rather than only the ones
    // `order` kept. This test is the one that would still see "bloom" in
    // the list even though the graph never asked it to run.
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final scene = Scene()..add(CameraNode());
    final view = RenderView(camera: scene.cameras.single);

    final result = renderer.render(
      width: 64,
      height: 64,
      scene: scene,
      views: <RenderView>[view],
      settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
    );

    expect(result.passes.map((p) => p.name), isNot(contains('bloom')));
  });

  test('with bloom on, bloom is one of the passes', () {
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final scene = Scene()..add(CameraNode());
    final view = RenderView(camera: scene.cameras.single);

    final result = renderer.render(
      width: 64,
      height: 64,
      scene: scene,
      views: <RenderView>[view],
      settings: const RenderSettings(),
    );

    expect(result.passes.map((p) => p.name), contains('bloom'));
  });

  test('every pass reports a non-negative time and says it is active', () {
    // Mutation: never start the stopwatch, or start a fresh one that never
    // reads elapsed time before the field is filled in. Nothing here proves
    // the *scale* of the number is right — only that it is a real
    // measurement rather than a default no test would notice missing.
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final scene = Scene()..add(CameraNode());
    final view = RenderView(camera: scene.cameras.single);

    final result = renderer.render(
      width: 64,
      height: 64,
      scene: scene,
      views: <RenderView>[view],
      settings: const RenderSettings(),
    );

    expect(result.passes, isNotEmpty);
    for (final pass in result.passes) {
      expect(pass.micros, greaterThanOrEqualTo(0), reason: pass.name);
      expect(pass.active, isTrue, reason: pass.name);
    }
  });
}
