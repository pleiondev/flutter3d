/// What a fall back, a requirement and the queue's order hold to, on the
/// devices that compute in Dart: the contract tests that lock the compute
/// policy's behaviour.
///
///     dart test test/compute_fallback_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart'
    show cpuComputeDeviceStandingInForGpu;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart'
    show FakeBackend, computePlacementOf;
import 'package:flutter3d_shaders/kernel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

const String _twice = '''
compute Twice {
  workgroup 4;
  buffer values: u32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(values) { return; }
    values[i] = values[i] * 2u;
  }
}
''';

Future<ShaderHandle> _stage(GraphicsDevice device, String source) async {
  final kernels = ComputeKernel.parseAll(source);
  final library = await device.loadShaders(
    kernelBundle('test', kernels).encode(),
  );
  return library[kernels.single.name]!;
}

ByteData _uints(List<int> values) {
  final out = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    out.setUint32(i * 4, values[i], Endian.little);
  }
  return out;
}

List<int> _read(ByteData bytes) => <int>[
  for (var i = 0; i < bytes.lengthInBytes ~/ 4; i++)
    bytes.getUint32(i * 4, Endian.little),
];

/// Reads what a workload draws and the scene's colour, so the frame keeps
/// the workload's step.
final class _Reader extends RenderNode {
  @override
  String get name => 'test.reader';

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.computedVertices,
    FrameResourceIds.hdrColor,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) => frame.resources.provide(
    FrameResourceIds.hdrColor,
    frame.resources.texture(FrameResourceIds.hdrColor),
  );
}

/// A workload that dispatches, then writes what the dispatch reads: on a
/// GPU queue the write lands first.
final class _WriteAfterDispatch extends ComputeWorkload {
  _WriteAfterDispatch();

  ByteData? result;

  @override
  String get name => 'write after dispatch';

  @override
  String get kernelSource => _twice;

  @override
  List<WorkloadBuffer> get buffers => const <WorkloadBuffer>[
    WorkloadBuffer('values', 16, readable: true),
  ];

  @override
  void record(WorkloadRecorder recorder) {
    recorder
      ..dispatch('Twice', 1)
      ..write('values', _uints(<int>[1, 2, 3, 4]))
      ..readBack('values', (ByteData bytes) => result = bytes);
  }
}

const String _count = '''
compute Count {
  workgroup 4;
  buffer values: u32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(values) { return; }
    values[i] = values[i] + 1u;
  }
}
''';

/// A workload that counts its frames on the device and reads the count
/// back every frame: which frame asked, and what it read.
final class _Counter extends ComputeWorkload {
  _Counter();

  int _recorded = 0;
  final List<(int, int)> seen = <(int, int)>[];

  @override
  String get name => 'counter';

  @override
  String get kernelSource => _count;

  @override
  List<WorkloadBuffer> get buffers => const <WorkloadBuffer>[
    WorkloadBuffer('values', 16, readable: true),
  ];

  @override
  void record(WorkloadRecorder recorder) {
    final frame = ++_recorded;
    recorder
      ..dispatch('Count', 1)
      ..readBack(
        'values',
        (ByteData bytes) =>
            seen.add((frame, bytes.getUint32(0, Endian.little))),
      );
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a kernel failing on a GPU throws in a test, and falls back with an '
      'event in a release build', () async {
    // Mutation: catch the error and move on silently, as placement did, and
    // a GPU-intended kernel runs in Dart one invocation at a time with
    // nothing saying so.
    final registry = DeviceRegistry<Object>();
    final cpu = cpuComputeDevice();
    registry.addComputeDevice(ComputePlacement.cpu, 'cpu', (_) async => cpu);
    final drawing = cpuComputeDeviceStandingInForGpu();
    registry.adopt(drawing);
    final compute = FrameCompute.of(drawing);
    expect(compute.strict, isTrue, reason: 'a test runs with assertions on');
    Future<Object> load(GraphicsDevice d) async => identical(d, drawing)
        ? throw StateError('the WGSL did not compile')
        : 'loaded';
    await expectLater(
      compute.place('blur', load),
      throwsA(
        isA<ComputeFallbackError>().having(
          (e) => e.fallback.passedOver.single.error,
          'error',
          isA<StateError>(),
        ),
      ),
    );

    compute.strict = false;
    final events = <ComputeFallback>[];
    compute.fallbacks.listen(events.add);
    final placed = await compute.place('blur', load);
    expect(placed.site.device, same(cpu));
    expect(placed.passedOver.single.backend, drawing.backendName);
    await _settle();
    expect(events.single.landedOn, cpu.backendName);
    expect(events.single.message, contains('the WGSL did not compile'));
  });

  test('a refusal the machine decides falls back even in a test', () async {
    final registry = DeviceRegistry<Object>();
    final cpu = cpuComputeDevice();
    registry.addComputeDevice(ComputePlacement.cpu, 'cpu', (_) async => cpu);
    final drawing = cpuComputeDeviceStandingInForGpu();
    registry.adopt(drawing);
    final placed = await FrameCompute.of(drawing).place(
      'blur',
      (GraphicsDevice d) async => identical(d, drawing)
          ? throw UnsupportedCapabilityException(
              DeviceFeature.storageTextures,
              backend: d.backendName,
            )
          : 'loaded',
    );
    expect(placed.site.device, same(cpu));
  });

  test('a bit-exact workload that uses sin is kept off a GPU, and one that '
      'keeps to exact operations is not', () async {
    // Mutation: ignore the requirement, and a replay steps on a GPU whose
    // sin is its own to a few ulp.
    final registry = DeviceRegistry<Object>();
    final drawing = cpuComputeDeviceStandingInForGpu();
    registry.adopt(drawing);
    final compute = FrameCompute.of(drawing);
    final inexact = ComputeNeeds(
      requirements: const <ComputeRequirement>{ComputeRequirement.bitExact},
      invocationsPerWorkgroup: 4,
      storageBuffersPerStage: 1,
      inexactOperations: const <String>{'sin'},
    );
    final loads = <GraphicsDevice>[];
    expect(
      await compute.placeHosted(
        'replay',
        (GraphicsDevice d) async => loads.add(d),
        hasHost: true,
        needs: inexact,
      ),
      isNull,
    );
    expect(loads, isEmpty, reason: 'a device that cannot meet it is not asked');

    const exact = ComputeNeeds(
      requirements: <ComputeRequirement>{ComputeRequirement.bitExact},
      invocationsPerWorkgroup: 4,
      storageBuffersPerStage: 1,
    );
    final placed = await compute.placeHosted(
      'replay',
      (GraphicsDevice d) async => true,
      hasHost: true,
      needs: exact,
    );
    expect(computePlacementOf(placed!.site), ComputePlacement.device);
  });

  test('work past the portable profile is refused unless it says so', () async {
    final drawing = cpuComputeDevice();
    const big = ComputeNeeds(invocationsPerWorkgroup: 256);
    await expectLater(
      FrameCompute.of(
        drawing,
      ).place('big', (GraphicsDevice d) async => true, needs: big),
      throwsA(
        isA<ComputePlacementException>().having(
          (e) => e.tried.join(),
          'tried',
          contains('portable 128'),
        ),
      ),
    );
    const declared = ComputeNeeds(
      requirements: <ComputeRequirement>{
        ComputeRequirement.beyondPortableProfile,
      },
      invocationsPerWorkgroup: 256,
    );
    final placed = await FrameCompute.of(
      drawing,
    ).place('big', (GraphicsDevice d) async => true, needs: declared);
    expect(placed.site.device, same(drawing));
  });

  test(
    'a write made while a CPU pass is open lands before its dispatches',
    () async {
      // Mutation: run a dispatch as it is recorded, and the CPU doubles the
      // values a GPU queue would already have overwritten.
      final device = cpuComputeDevice();
      final stage = await _stage(device, _twice);
      final buffer = device.createBuffer(
        BufferDescriptor(
          lengthInBytes: 16,
          usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
        ),
        contents: _uints(<int>[9, 9, 9, 9]),
      );
      final pass = device.beginComputePass()
        ..bindPipeline(device.createComputePipeline(stage))
        ..bindStorageBuffer(stage, 'values', buffer)
        ..dispatch(1);
      device.writeBuffer(buffer, 0, _uints(<int>[1, 2, 3, 4]));
      pass.submit();
      expect(_read(await device.readBuffer(buffer)), <int>[2, 4, 6, 8]);
    },
  );

  test('a workload\'s write after a dispatch lands first, on the CPU '
      'executor and on a device standing in for a GPU alike', () async {
    // Mutation: write through to the device as recorded, and the CPU
    // executor doubles the zeros the buffer was made with.
    for (final executor in <CpuDevice Function()>[
      cpuComputeDevice,
      cpuComputeDeviceStandingInForGpu,
    ]) {
      final device = FakeBackend(maxColorAttachments: 4);
      final registry = DeviceRegistry<Object>()
        ..addComputeDevice(
          ComputePlacement.cpu,
          'cpu',
          (_) async => executor(),
        );
      registry.adopt(device);
      final renderer = Renderer.create(device: device);
      final workload = _WriteAfterDispatch();
      renderer.renderSteps
        ..addWorkload(workload)
        ..addNode(_Reader());
      await renderer.renderSteps.whenPlaced();
      final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
      camera.lookAt(Vector3.zero());
      renderer.render(
        width: 16,
        height: 16,
        scene: Scene()..add(camera),
        views: <CameraView>[CameraView(camera: camera)],
      );
      await _settle();
      expect(_read(workload.result!), <int>[2, 4, 6, 8]);
      renderer.dispose();
    }
  });

  test('a frame drawn straight after another hands the workload what that '
      'one read back, as it stood then', () async {
    // Mutation: hand a read over only when its future lands, and frames
    // drawn with no turn between them read nothing back at all; read it
    // again after the next frame's dispatch, and each count is one ahead.
    for (final executor in <CpuDevice Function()>[
      cpuComputeDevice,
      cpuComputeDeviceStandingInForGpu,
    ]) {
      final device = FakeBackend(maxColorAttachments: 4);
      final registry = DeviceRegistry<Object>()
        ..addComputeDevice(
          ComputePlacement.cpu,
          'cpu',
          (_) async => executor(),
        );
      registry.adopt(device);
      final renderer = Renderer.create(device: device);
      final workload = _Counter();
      renderer.renderSteps
        ..addWorkload(workload)
        ..addNode(_Reader());
      await renderer.renderSteps.whenPlaced();
      final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
      camera.lookAt(Vector3.zero());
      final scene = Scene()..add(camera);
      for (var i = 0; i < 5; i++) {
        renderer.render(
          width: 16,
          height: 16,
          scene: scene,
          views: <CameraView>[CameraView(camera: camera)],
        );
      }
      expect(workload.seen, <(int, int)>[(1, 1), (2, 2), (3, 3), (4, 4)]);
      await _settle();
      expect(workload.seen.last, (
        5,
        5,
      ), reason: 'the last frame\'s read lands on a later turn');
      renderer.dispose();
    }
  });

  test('the engine instance lets go of its compute with its device', () async {
    // Mutation: keep executors in a static, and a second engine finds the
    // first one's sidecar, opened and never disposed.
    final registry = DeviceRegistry<Object>();
    final opened = <FakeBackend>[];
    registry.addComputeDevice(ComputePlacement.cpu, 'fake', (_) async {
      final made = FakeBackend(compute: true);
      opened.add(made);
      return made;
    });
    final drawing = FakeBackend();
    registry.adopt(drawing);
    final compute = FrameCompute.of(drawing);
    final placed = await compute.place('blur', (GraphicsDevice d) async => d);
    final released = <String>[];
    await compute.cached(
      placed.site.device,
      'pipeline',
      () async => 'made',
      release: released.add,
    );
    expect(compute.cachedCount, 1);
    expect(opened.single.isLost, isFalse);

    drawing.dispose();
    await _settle();
    expect(compute.isDisposed, isTrue);
    expect(opened.single.isLost, isTrue, reason: 'the executor it opened');
    expect(released, <String>['made']);
    expect(compute.cachedCount, 0);
    expect(identical(FrameCompute.of(drawing), compute), isFalse);
  });
}
