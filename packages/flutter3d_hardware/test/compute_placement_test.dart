// The placement rule: what a step is told on devices without compute, and
// the order among devices that compute as [FrameCompute] applies it to the
// device a frame is drawn on and the registry that opened it.
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

void main() {
  test('a frame with no compute anywhere refuses a step, naming each', () {
    // Mutation: answer the drawing device whether or not it computes, and
    // a step is encoded on a device that refuses its first call.
    final executors = ComputeExecutors(device: FakeBackend());
    expect(executors.available, isEmpty);
    expect(
      () => executors.place(step: 'particles'),
      throwsA(
        isA<ComputePlacementException>()
            .having((e) => e.reason, 'reason', ComputeRefusalReason.noExecutor)
            .having((e) => e.tried, 'tried', hasLength(3))
            .having((e) => e.message, 'message', contains('"particles"')),
      ),
    );
  });

  test('the placements are an open set in their placement order', () {
    expect(ComputePlacement.values.map((p) => p.name), <String>[
      'device',
      'sidecar',
      'cpu',
      'nativeSimd',
    ]);
    expect(ComputePlacement.byName('cpu'), same(ComputePlacement.cpu));
    expect(ComputePlacement.byName('a placement from a newer version'), isNull);
    expect(
      ComputeRefusalReason.byName('kernelRefused'),
      same(ComputeRefusalReason.kernelRefused),
    );
  });

  test('a registry opens the newest device added for each placement', () async {
    // Mutation: open the first added, and a test's replacement CPU device is
    // never used.
    final registry = DeviceRegistry<Object>();
    final first = FakeBackend();
    final second = FakeBackend();
    final refused = <String>[];
    registry
      ..addComputeDevice(ComputePlacement.cpu, 'old', (_) async => first)
      ..addComputeDevice(ComputePlacement.cpu, 'new', (_) async => second)
      ..addComputeDevice(
        ComputePlacement.sidecar,
        'wgpu',
        (_) async => throw StateError('no adapter'),
      );
    final drawing = FakeBackend();
    final executors = await registry.computeExecutors(
      drawing,
      onRefused: refused.add,
    );
    expect(executors.device, same(drawing));
    expect(executors.cpu, same(second));
    expect(executors.sidecar, isNull);
    expect(refused.single, contains('wgpu (sidecar compute) would not start'));
  });

  test('a workload with host code falls back to it, not to a refusal', () {
    // Mutation: answer the CPU rule for a workload with host code, and a
    // frame with no compute anywhere refuses a step its own core would run.
    final executors = ComputeExecutors(device: FakeBackend());
    expect(executors.placeWorkload(step: 'water', hasHost: true), isNull);
    expect(
      () => executors.placeWorkload(step: 'water', hasHost: false),
      throwsA(
        isA<ComputePlacementException>().having(
          (e) => e.reason,
          'reason',
          ComputeRefusalReason.noExecutor,
        ),
      ),
    );
  });

  test('the GPUs are tried ahead of a workload\'s host code', () {
    expect(ComputeExecutors.aheadOfHost, <ComputePlacement>[
      ComputePlacement.device,
      ComputePlacement.sidecar,
    ]);
  });

  test('the native lanes are a placement no step is placed on', () {
    // Mutation: try nativeSimd in `place`, and every refusal gains a line
    // for an executor that is no device.
    expect(ComputePlacement.values.last, ComputePlacement.nativeSimd);
    expect(
      ComputePlacement.byName('nativeSimd'),
      same(ComputePlacement.nativeSimd),
    );
    final executors = ComputeExecutors(device: FakeBackend());
    expect(executors.executorFor(ComputePlacement.nativeSimd), isNull);
    expect(
      () => executors.place(step: 'blur'),
      throwsA(
        isA<ComputePlacementException>().having(
          (e) => e.tried.any((line) => line.contains('nativeSimd')),
          'names nativeSimd',
          isFalse,
        ),
      ),
    );
  });

  test('a workload binding says where it landed and what it draws', () {
    final host = WorkloadBinding.host();
    expect(host.isOnHost, isTrue);
    expect(host.vertices('surface'), isNull);
    final site = FrameCompute.of(FakeBackend()).frame;
    final placed = WorkloadBinding.at(site);
    expect(placed.isOnHost, isFalse);
    expect(computePlacementOf(placed.site!), ComputePlacement.device);
    expect(
      const WorkloadBuffer('depth', 16, readable: true),
      const WorkloadBuffer('depth', 16, readable: true),
    );
  });
}
