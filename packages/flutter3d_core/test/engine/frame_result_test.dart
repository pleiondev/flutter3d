// A held frame is the last drawn one handed back again: every field of it,
// with `held` set.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

void main() {
  test('a held frame keeps the stalls of the frame it repeats', () {
    final device = FakeBackend();
    const stall = PipelineStall(
      material: 'pbr',
      geometry: PipelineGeometry.skinned,
      micros: 12000,
      frame: 7,
    );
    final drawn = FrameResult(
      frame: device.createTexture(
        const RenderTargetDescriptor(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      ),
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
      pipelineStalls: const <PipelineStall>[stall],
    );

    // Mutation: build the held result without `pipelineStalls`, and a held
    // frame reports none while the frame it stands for had one.
    final held = drawn.toHeld();
    expect(held.held, isTrue);
    expect(held.pipelineStalls, <PipelineStall>[stall]);
  });
}
