/// A frame with one pipeline the driver will not link draws everything else
/// and says so once.
///
/// The field case: an OpenGL ES fallback links a pipeline lazily at its first
/// draw and refuses there. The draw threw, `Renderer.render` rethrew, and one
/// material on one phone failed every frame. `FakeBackend` plays that driver
/// through `refusingPipelines`; the device's half is
/// `pipeline_refused_test.dart` in `flutter3d_hardware`.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

const _refused = 'MeshVertex+UnlitOpaque';
const _drawn = 'MeshVertex+PbrOpaque';

/// The draws each pipeline was recorded making, over [passes].
Map<String, int> _drawsByPipeline(Iterable<FakePass> passes) {
  final draws = <String, int>{};
  for (final pass in passes) {
    String? bound;
    for (final command in pass.commands) {
      switch (command) {
        case RecordedPipeline(:final pipeline):
          bound = pipeline.name;
        case RecordedDraw() when bound != null:
          draws.update(bound, (int n) => n + 1, ifAbsent: () => 1);
        default:
      }
    }
  }
  return draws;
}

void main() {
  test('one refused pipeline skips its draws and the frame goes on', () {
    // Mutation: rethrow from FakePass.draw instead of skipping, and the first
    // render throws; take the refusals in the renderer every frame without
    // the device's once-per-pipeline record, and `told` has one per frame.
    final device = FakeBackend(refusingPipelines: <String>{_refused});
    final mesh = DeviceMesh.upload(device, CuboidShape().build());
    final scene = Scene()
      ..add(MeshNode(mesh, RenderMaterial())..setPosition(-1.0, 0.0, -5.0))
      ..add(
        MeshNode(mesh, RenderMaterial(lighting: LightingModel.unlit))
          ..setPosition(1.0, 0.0, -5.0),
      )
      ..add(CameraNode());
    final told = <PipelineRefused>[];
    final renderer = Renderer.create(device: device)
      ..listener = RenderListener(refused: told.add);

    final perFrame = <List<PipelineRefused>>[];
    for (var frame = 0; frame < 12; frame++) {
      final before = device.passes.length;
      final result = renderer.render(
        width: 64,
        height: 48,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
      );
      perFrame.add(result.pipelineRefusals);
      final draws = _drawsByPipeline(device.passes.skip(before));
      expect(draws[_refused], isNull, reason: 'frame $frame drew it');
      expect(draws[_drawn], greaterThan(0), reason: 'frame $frame');
    }

    expect(perFrame.first.map((r) => r.pipeline), <String>[_refused]);
    expect(perFrame.skip(1), everyElement(isEmpty));
    expect(told.map((r) => r.pipeline), <String>[_refused]);
    // Rebuilt at most `maxBuilds` times over twelve frames, then left alone.
    expect(device.pipelineBuilds[_refused], PipelineRefusals.maxBuilds);
  });

  test('a refusal reaches the bus once, as its own event', () {
    // Mutation: drop `refused:` from `RenderListener.toBus`, and nothing is
    // published.
    final published = <Object>[];
    final listener = RenderListener(refused: published.add);
    const refusal = PipelineRefused(
      pipeline: _refused,
      backend: 'FakeBackend',
      reason: PipelineRefusalReason.link,
    );
    final device = FakeBackend();
    final frame = device.createTexture(
      const RenderTargetDescriptor(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    final result = FrameResult(
      frame: frame,
      cpuMicros: 1,
      submitMicros: 1,
      drawCalls: 1,
      triangles: 1,
      instances: 1,
      culled: 0,
      pipelineSwitches: 1,
      debugLines: 0,
      lights: 0,
      lightsDropped: 0,
      pipelines: 1,
      shadowCasters: 0,
      skinnedDraws: 0,
      pipelineRefusals: const <PipelineRefused>[refusal],
    );
    listener.notify(result);
    expect(published, <Object>[refusal]);
    expect(const FramePipelineRefused(refusal).name, 'render.pipelineRefused');
    // A held frame repeats the result it stands for, and tells nothing.
    listener.notify(result.toHeld());
    expect(published, hasLength(1));
    expect(result.toHeld().pipelineRefusals, <PipelineRefused>[refusal]);
  });
}
