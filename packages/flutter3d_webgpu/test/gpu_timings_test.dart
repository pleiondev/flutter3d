/// A labelled pass reports what the GPU spent in it — `H2`.
///
///     flutter test --platform chrome test/gpu_timings_test.dart
///
/// The timings arrive a frame late by design: a pass's timestamps can only be
/// read once the GPU has written them, so the device resolves a frame's
/// queries when the next frame begins and hands them over when the copy is
/// done. The test draws one labelled pass, begins the next frame, and waits.
/// Where the adapter did not grant `timestamp-query` the device answers
/// false and the test says so rather than passing on nothing.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'quad_stages.dart';

void main() {
  test('a labelled pass comes back with a time, a frame later', () async {
    final device = await WebGpuDevice.create(
      width: 16,
      height: 16,
      stages: quadStages,
    );
    if (device == null) {
      markTestSkipped('this browser has no WebGPU');
      return;
    }
    if (!device.supportsGpuTimestamps) {
      markTestSkipped('the adapter did not grant timestamp-query');
      return;
    }

    final arrived = Completer<GpuFrameTimings>();
    device.onGpuTimings((timings) {
      if (!arrived.isCompleted) arrived.complete(timings);
    });

    final target = device.createTexture(
      const RenderTargetSpec(
        width: 16,
        height: 16,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    // A pass that draws, as every pass the engine labels does: on Metal a
    // pass with no work in it writes no end time, and the timer leaves such
    // a pass out rather than reporting the machine's uptime.
    final vertex = device.shaders['QuadVertex']!;
    final fragment = device.shaders['QuadFragment']!;
    final palette = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(<int>[0, 255, 0, 255])),
    )!;
    device.beginFrame();
    device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(texture: target, clearValue: Vector4(1, 0, 0, 1)),
          ],
          label: 'the one pass',
        ),
      )
      ..bindPipeline(device.createPipeline(vertex, fragment))
      ..bindVertexBuffer(
        device.uploadGeometry(quadVertices(), GeometryUsage.vertices),
        4,
      )
      ..bindIndexBuffer(
        device.uploadGeometry(quadIndices(), GeometryUsage.indices),
        IndexType.int16,
        6,
      )
      ..bindUniformBlock(vertex, 'Placement', <String, Float32List>{
        'value': Float32List.fromList(<double>[0, 0, 1, 1]),
      })
      ..bindUniformBlock(fragment, 'Tint', <String, Float32List>{
        'value': Float32List.fromList(<double>[1, 1, 1, 1]),
      })
      ..bindTexture(fragment, 'palette', palette)
      ..draw()
      ..submit();
    // The next frame is what resolves this one.
    device.beginFrame();

    final timings = await arrived.future.timeout(const Duration(seconds: 10));
    expect(timings.passes.map((p) => p.label), <String>['the one pass']);
    expect(timings.passes.single.micros, greaterThanOrEqualTo(0));
    device.dispose();
  });
}
