/// The sidecar against the contract's compute and sharing checks: the four
/// kernels give the bytes the CPU gives, a texture carries by copy, and zero
/// copy is refused by name.
///
/// **Not the whole suite**: the sidecar computes and draws nothing, so the
/// checks that open a render pass are not its to pass. A machine with no
/// wgpu sidecar — no adapter, or a build without wgpu-native — skips each
/// check with the reason, never passes it.
library;

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_wgpu/flutter3d_wgpu.dart';
import 'package:test/test.dart';

/// The sidecar, or null with the reason recorded as a skip.
Future<GraphicsDevice?> _open() async {
  try {
    return await WgpuSidecar.open();
  } on DeviceUnavailableException catch (refused) {
    markTestSkipped('no wgpu sidecar here: ${refused.message}');
    return null;
  }
}

void main() {
  for (final check in <ConformanceCheck>[...computeChecks, ...sharingChecks]) {
    test('sidecar: ${check.name}', () async {
      final device = await _open();
      if (device == null) return;
      try {
        await check.run(device);
      } on ConformanceDeclinedException catch (declined) {
        markTestSkipped('sidecar: ${declined.reason}');
      } finally {
        device.dispose();
      }
    });
  }

  test('the sidecar computes, draws nothing, and says so by name', () async {
    // Mutation: report the drawing features, and a frame places a render
    // node on a device that cannot open a pass.
    final device = await _open();
    if (device == null) return;
    try {
      expect(device.features.has(DeviceFeature.compute), isTrue);
      expect(device.features.has(DeviceFeature.sharedTextures), isFalse);
      expect(WgpuSidecar.adapterName(device), isNotEmpty);
      // Mutation: answer `DeviceLimits.webgpuDefaults`, and a caller sizing
      // a pass from the limits plans eight colour attachments and four
      // samples on a device that opens no pass at all.
      final limits = device.limits;
      expect(
        (
          limits.maxColorAttachments,
          limits.maxColorAttachmentBytesPerSample,
          limits.maxSampleCount,
          limits.maxVertexBuffers,
          limits.maxVertexAttributes,
          limits.maxInterStageShaderVariables,
        ),
        (0, 0, 1, 0, 0, 0),
      );
      expect(
        limits.maxComputeInvocationsPerWorkgroup,
        DeviceLimits.webgpuDefaults.maxComputeInvocationsPerWorkgroup,
      );
      expect(
        () => device.beginRenderPass(const RenderPassDescriptor(colors: [])),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('draws nothing'),
          ),
        ),
      );
    } finally {
      device.dispose();
    }
  });

  test('a registry places compute on the sidecar before the CPU', () async {
    final registry = DeviceRegistry<Object>();
    final registration = registerWgpuSidecar(registry);
    final refused = <String>[];
    // A drawing device without compute: the hardware package's fake.
    final executors = await registry.computeExecutors(
      FakeBackend(),
      onRefused: refused.add,
    );
    registration.cancel();
    if (executors.sidecar == null) {
      markTestSkipped('no wgpu sidecar here: ${refused.join('; ')}');
      return;
    }
    expect(executors.place(step: 'blur').placement, ComputePlacement.sidecar);
    executors.sidecar!.dispose();
  });
}
