// The placement rule on devices without compute: what a step that demands
// nothing and one that demands a placement are told. The order among
// devices that do compute is held where a device computes,
// `flutter3d_cpu/test/compute_placement_test.dart`.
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
            .having((e) => e.demand, 'demand', isNull)
            .having((e) => e.tried, 'tried', hasLength(3))
            .having((e) => e.message, 'message', contains('"particles"')),
      ),
    );
  });

  test('a demanded placement that is missing is refused, not moved', () {
    // Mutation: fall through to the next placement, and a step that
    // demanded the sidecar runs somewhere it did not ask for.
    final executors = ComputeExecutors(device: FakeBackend());
    expect(
      () => executors.place(step: 'blur', demand: ComputePlacement.sidecar),
      throwsA(
        isA<ComputePlacementException>()
            .having(
              (e) => e.reason,
              'reason',
              ComputeRefusalReason.placementUnavailable,
            )
            .having((e) => e.demand, 'demand', ComputePlacement.sidecar)
            .having((e) => e.tried.single, 'tried', 'sidecar: none given'),
      ),
    );
  });

  test('the placements are an open set in their placement order', () {
    expect(ComputePlacement.values.map((p) => p.name), <String>[
      'device',
      'sidecar',
      'cpu',
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
      ..addComputeDevice(ComputePlacement.cpu, 'old', () async => first)
      ..addComputeDevice(ComputePlacement.cpu, 'new', () async => second)
      ..addComputeDevice(
        ComputePlacement.sidecar,
        'wgpu',
        () async => throw StateError('no adapter'),
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
}
