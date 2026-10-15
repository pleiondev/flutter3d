/// What a piece of compute may require, the portable profile, the declared
/// tolerances, the checks every encoder makes, and the fake's compute.
///
///     dart test test/compute_requirement_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

double _f32(double x) => (ByteData(4)..setFloat32(0, x)).getFloat32(0);

double _next(double x) {
  final bits = (ByteData(4)..setFloat32(0, x)).getUint32(0);
  return (ByteData(4)..setUint32(0, bits + 1)).getFloat32(0);
}

void main() {
  test('a requirement is an open set with its names', () {
    expect(ComputeRequirement.values, <ComputeRequirement>[
      ComputeRequirement.bitExact,
      ComputeRequirement.beyondPortableProfile,
    ]);
    expect(
      ComputeRequirement.byName('bitExact'),
      same(ComputeRequirement.bitExact),
    );
    expect(ComputeRequirement.byName('fast'), isNull);
  });

  test('the portable profile refuses past 128 unless asked to look at the '
      'device', () {
    // Mutation: hold kernels to WebGPU's 256, and a kernel that loads on
    // the browser fails on the Vulkan and GLES devices Impeller runs on.
    const limits = DeviceLimits.webgpuDefaults;
    expect(
      PortableComputeProfile.refusalFor(
        invocations: 128,
        storageBuffers: 8,
        limits: limits,
      ),
      isNull,
    );
    expect(
      PortableComputeProfile.refusalFor(
        invocations: 256,
        storageBuffers: 1,
        limits: limits,
      ),
      contains('portable 128'),
    );
    expect(
      PortableComputeProfile.refusalFor(
        invocations: 1,
        storageBuffers: 9,
        limits: limits,
      ),
      contains('portable 8'),
    );
    const beyond = <ComputeRequirement>{
      ComputeRequirement.beyondPortableProfile,
    };
    expect(
      PortableComputeProfile.refusalFor(
        invocations: 256,
        storageBuffers: 1,
        limits: limits,
        requirements: beyond,
      ),
      isNull,
    );
    expect(
      PortableComputeProfile.refusalFor(
        invocations: 256,
        storageBuffers: 1,
        limits: const DeviceLimits(maxComputeInvocationsPerWorkgroup: 64),
        requirements: beyond,
      ),
      contains("device's 64"),
    );
  });

  test('a tolerance admits what it declares and no more', () {
    final one = _f32(1);
    expect(ulpsBetween(one, _next(one)), 1);
    expect(ulpsBetween(-0.0, 0.0), 0);
    final divide = kernelTolerances['/']!;
    var x = one;
    for (var i = 0; i < divide.ulp; i++) {
      x = _next(x);
    }
    expect(divide.admits(one, x), isTrue);
    expect(divide.admits(one, _next(x)), isFalse);
    final sin = kernelTolerances['sin']!;
    expect(sin.admits(0.5, 0.5 + 1 / 4096), isTrue);
    expect(sin.admits(0.5, 0.5 + 1 / 1024), isFalse);
    expect(sin.admits(double.nan, double.nan), isTrue);
    expect(sin.admits(0.5, double.nan), isFalse);
    expect(kernelTolerances.keys, <String>['/', 'sqrt', 'sin', 'cos', 'pow']);
  });

  test('a bit-exact need passes over a GPU only for inexact operations', () {
    final gpu = FakeBackend(compute: true);
    const exact = ComputeNeeds(
      requirements: <ComputeRequirement>{ComputeRequirement.bitExact},
    );
    expect(exact.unmetOn(gpu), isNull);
    const inexact = ComputeNeeds(
      requirements: <ComputeRequirement>{ComputeRequirement.bitExact},
      inexactOperations: <String>{'sin', '/'},
    );
    expect(inexact.unmetOn(gpu), contains('/, sin'));
    expect(
      const ComputeNeeds(inexactOperations: <String>{'sin'}).unmetOn(gpu),
      isNull,
      reason: 'without the requirement, a tolerance is enough',
    );
  });

  test('every encoder refuses a misaligned range and an oversized dispatch '
      'at the call', () {
    // Mutation: take the checks out of the fake's pass, and a test on the
    // VM never meets what WebGPU refuses in the browser.
    final device = FakeBackend(compute: true);
    final buffer = device.createBuffer(
      const BufferDescriptor(
        lengthInBytes: 1024,
        usage: BufferUsage.standardStorage,
      ),
    );
    final stage = device.shaders['Step']!;
    final pass = device.beginComputePass(label: 'probe')
      ..bindPipeline(device.createComputePipeline(stage));
    expect(
      pass.bindStorageBuffer(stage, 'p', buffer, offsetInBytes: 256),
      isTrue,
    );
    expect(
      () => pass.bindStorageBuffer(stage, 'p', buffer, offsetInBytes: 4),
      throwsRangeError,
    );
    expect(
      () => pass.bindStorageBuffer(stage, 'p', buffer, sizeInBytes: 2048),
      throwsRangeError,
    );
    expect(() => pass.dispatch(65536), throwsRangeError);
    pass
      ..dispatch(4, 2)
      ..submit();
    final recorded = device.computePasses.single;
    expect(recorded.label, 'probe');
    expect(recorded.dispatches, 1);
    expect(recorded.wasSubmitted, isTrue);
    expect(recorded.commands.map((RecordedCall c) => c.name), <String>[
      'bindPipeline',
      'bindStorageBuffer',
      'dispatch',
      'submit',
    ]);
    expect(
      () => checkDispatch(DeviceLimits.webgpuDefaults, 1, -1, 1),
      throwsRangeError,
    );
    expect(
      checkStorageBinding(
        buffer,
        DeviceLimits.webgpuDefaults,
        offsetInBytes: 512,
      ),
      512,
    );
  });

  test('a fake without compute still refuses it', () {
    expect(
      () => FakeBackend().beginComputePass(),
      throwsA(isA<UnsupportedCapabilityException>()),
    );
  });

  test('the frame device is the site of work only it can run', () {
    // Mutation: answer a site for a device without compute, and the splat
    // sort opens a pass on WebGL.
    expect(
      FrameCompute.of(FakeBackend()).placeOnFrame('sort', (_) => true),
      isNull,
    );
    final gpu = FakeBackend(compute: true);
    expect(FrameCompute.of(gpu).placeOnFrame('sort', (_) => false), isNull);
    final site = FrameCompute.of(gpu).placeOnFrame('sort', (_) => true)!;
    expect(site.isOnFrameDevice, isTrue);
    expect(computePlacementOf(site), ComputePlacement.device);
    site.beginPass(label: 'sort').submit();
    expect(gpu.computePasses.single.label, 'sort');
  });

  test(
    'an explicit dispose lets go of what is cached on the frame device',
    () async {
      final gpu = FakeBackend(compute: true);
      final compute = FrameCompute.of(gpu);
      final stage = gpu.shaders['Step']!;
      final pipeline = await compute.cached(
        gpu,
        'pipeline',
        () async => gpu.createComputePipeline(stage),
        release: (ComputePipelineHandle p) => p.dispose(),
      );
      expect(
        await compute.cached<ComputePipelineHandle>(
          gpu,
          'pipeline',
          () async => throw StateError('made twice'),
        ),
        same(pipeline),
        reason: 'asked again, the same value',
      );
      expect(gpu.liveHandles, contains(pipeline));
      compute.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(pipeline.isDisposed, isTrue);
      expect(gpu.liveHandles, isNot(contains(pipeline)));
      expect(() => compute.cached(gpu, 'x', () async => 1), throwsStateError);
    },
  );

  test('a cached key answers one type and refuses another', () async {
    // Mutation: hand back the kept value cast to whatever was asked, and
    // asking for a String under the pipeline's key is a TypeError at the
    // cast instead of a refusal that names both types.
    final gpu = FakeBackend(compute: true);
    final compute = FrameCompute.of(gpu);
    final pipeline = await compute.cached(
      gpu,
      'pipeline',
      () async => gpu.createComputePipeline(gpu.shaders['Step']!),
      release: (ComputePipelineHandle p) => p.dispose(),
    );
    expect(
      await compute.cached<Object>(gpu, 'pipeline', () async => 'another'),
      same(pipeline),
      reason: 'a supertype of what is kept is answered',
    );
    expect(
      () => compute.cached(gpu, 'pipeline', () async => 'another'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('ComputePipelineHandle'), contains('String')),
        ),
      ),
    );
    expect(compute.cachedCount, 1, reason: 'the refusal keeps nothing');
    compute.dispose();
  });
}
