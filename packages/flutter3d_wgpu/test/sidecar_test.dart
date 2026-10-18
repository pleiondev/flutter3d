/// The sidecar against the contract's compute and sharing checks: the four
/// kernels give the bytes the CPU gives, a texture carries by copy, and zero
/// copy is refused by name.
///
/// **Not the whole suite**: the sidecar computes and draws nothing, so the
/// checks that open a render pass are not its to pass. A machine with no
/// wgpu sidecar — no adapter, or a build without wgpu-native — skips each
/// check with the reason, never passes it.
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:flutter3d_wgpu/flutter3d_wgpu.dart';
import 'package:test/test.dart';

/// The backend a run asks for, by `F3D_WGPU_BACKEND` (`dx12`, `vulkan`,
/// `metal`, `gl`); the platform's own when it is unset. CI's Windows job
/// sets `dx12` and `F3D_WGPU_FALLBACK=1`, so every check below runs on
/// Direct3D 12 through WARP.
final WgpuBackend? _asked = switch (Platform.environment['F3D_WGPU_BACKEND']) {
  null || '' => null,
  final String name =>
    WgpuBackend.byName(name) ??
        (throw ArgumentError('F3D_WGPU_BACKEND=$name names no backend')),
};

/// Whether the run asks for the software adapter (`F3D_WGPU_FALLBACK=1`).
final bool _fallback = Platform.environment['F3D_WGPU_FALLBACK'] == '1';

/// The sidecar, or null with the reason recorded as a skip — except in a
/// run that asked for a backend by name, where no adapter is a failure: a
/// CI job set up for Direct3D 12 that skipped every check would be green
/// for nothing.
Future<GraphicsDevice?> _open() async {
  try {
    return await WgpuSidecar.open(backend: _asked, fallbackAdapter: _fallback);
  } on DeviceUnavailableException catch (refused) {
    if (_asked != null) rethrow;
    markTestSkipped('no wgpu sidecar here: ${refused.message}');
    return null;
  }
}

/// What the platform's own order opens first, where the machine has it.
WgpuBackend get _platformFirst => Platform.isWindows
    ? WgpuBackend.dx12
    : Platform.isMacOS || Platform.isIOS
    ? WgpuBackend.metal
    : WgpuBackend.vulkan;

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
          isA<DeviceResourceException>().having(
            (e) => e.reason,
            'reason',
            contains('draws nothing'),
          ),
        ),
      );
    } finally {
      // Mutation: dispose without a word on `lost`, as the sidecar did, and
      // an engine holding it as its compute executor never hears it is gone.
      final losses = <DeviceLoss>[];
      device.lost.listen(losses.add);
      device
        ..dispose()
        ..dispose();
      await Future<void>.delayed(Duration.zero);
      expect(losses.map((DeviceLoss l) => l.reason), <DeviceLossReason>[
        DeviceLossReason.destroyed,
      ]);
      expect(device.isLost, isTrue);
    }
  });

  test('a read back through the pool comes back whole, twice, and a bad '
      'range is refused at the call', () async {
    // Mutation: hand a staging buffer back to the pool still mapped, and the
    // second read of the same buffer fails to map.
    final device = await _open();
    if (device == null) return;
    try {
      final bytes = ByteData(64 * 1024);
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        bytes.setUint32(i, i, Endian.little);
      }
      final buffer = device.createBuffer(
        BufferDescriptor(
          lengthInBytes: bytes.lengthInBytes,
          usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
        ),
        contents: bytes,
      );
      await device.readBuffer(buffer);
      final read = device.readBuffer(buffer);
      final back = await read;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        expect(back.getUint32(i, Endian.little), i);
      }
      // A misaligned range is refused at the call, as WebGPU refuses it.
      final stage = (await device.loadShaders(
        kernelBundle(
          'probe',
          ComputeKernel.parseAll(conformanceKernels),
        ).encode(),
      ))['PrefixSum']!;
      final pass = device.beginComputePass()
        ..bindPipeline(device.createComputePipeline(stage));
      expect(
        () => pass.bindStorageBuffer(stage, 'sums', buffer, offsetInBytes: 4),
        throwsRangeError,
      );
      expect(() => pass.dispatch(1 << 20), throwsRangeError);
    } finally {
      device.dispose();
    }
  });

  test('the sidecar says which backend it opened, and it is the one '
      'decided', () async {
    // Mutation: create the instance with every backend again, and on a
    // Windows machine the report says vulkan where dx12 was the decision;
    // or answer `other` for every adapter, and nobody knows what ran.
    final device = await _open();
    if (device == null) return;
    try {
      final info = WgpuSidecar.adapterInfo(device)!;
      expect(info.name, WgpuSidecar.adapterName(device));
      if (_asked case final asked?) {
        expect(info.backend, asked);
        expect(info.isFallback, _fallback);
      } else if (Platform.isMacOS) {
        // Metal is the only backend the sidecar opens on Apple platforms.
        expect(info.backend, WgpuBackend.metal);
        expect(info.isFallback, isFalse);
      } else {
        expect(info.backend, isNot(WgpuBackend.other));
        expect(<WgpuBackend>[
          _platformFirst,
          if (Platform.isWindows) WgpuBackend.vulkan else WgpuBackend.gl,
        ], contains(info.backend));
      }
      expect(WgpuSidecar.adapterInfo(FakeBackend()), isNull);
    } finally {
      device.dispose();
    }
  });

  test(
    'a backend the machine does not have is refused, never replaced',
    () async {
      // Mutation: fall back to the platform's order when the backend asked
      // for has no adapter, and a run asked for Direct3D 12 computes on
      // something else while saying it passed.
      final device = await _open();
      if (device == null) return;
      device.dispose();
      final missing = Platform.isWindows ? WgpuBackend.metal : WgpuBackend.dx12;
      await expectLater(
        WgpuSidecar.open(backend: missing),
        throwsA(
          isA<DeviceUnavailableException>().having(
            (e) => e.message,
            'message',
            contains(missing.name),
          ),
        ),
      );
      expect(
        () => WgpuSidecar.open(backend: WgpuBackend.other),
        throwsArgumentError,
      );
    },
  );

  test('the backends are an open set with stable names', () {
    expect(WgpuBackend.values.map((b) => b.name), <String>[
      'dx12',
      'vulkan',
      'metal',
      'gl',
      'other',
    ]);
    expect(WgpuBackend.byName('dx12'), same(WgpuBackend.dx12));
    expect(WgpuBackend.byName('a backend from a newer version'), isNull);
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
