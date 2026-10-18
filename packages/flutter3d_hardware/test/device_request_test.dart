/// What an application asks of the device it opens, and the registry holding
/// every backend to it.
///
/// An opener is a function type every backend assigns to, so it takes one
/// value whose fields can grow; and a backend that never reads a field is
/// still held to it, because the registry checks the device it answers.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

void main() {
  test('a device without a required feature is not handed over', () async {
    // Mutation: return the device from `_openHeld` without checking it. The
    // application asked for multiview and would be drawing on a device
    // without it, with the first refusal deep inside a frame.
    final registry = DeviceRegistry<Object>();
    final lacking = FakeBackend();
    final having = FakeBackend(
      extraFeatures: <DeviceFeature>[DeviceFeature.renderBundles],
    );
    final asked = <DeviceRequest>[];
    final told = <String>[];
    registry
      ..addBackend('having', (DeviceRequest request) async {
        asked.add(request);
        return having;
      }, asFallback: true)
      ..addBackend('lacking', (DeviceRequest request) async {
        asked.add(request);
        return lacking;
      });

    final opened = await registry.openFor(
      const DeviceRequest(
        width: 8,
        height: 4,
        requiredFeatures: <DeviceFeature>{DeviceFeature.renderBundles},
      ),
      onFallback: told.add,
    );

    expect(identical(opened, having), isTrue);
    expect(asked.map((DeviceRequest r) => '${r.width}x${r.height}'), <String>[
      '8x4',
      '8x4',
    ]);
    expect(told.single, contains('render-bundles'));
    expect(
      lacking.isDisposed,
      isTrue,
      reason: 'a device the request refused is the registry to dispose',
    );
  });

  test('limits are held both ways, and an unknown one is refused', () {
    final device = FakeBackend(maxColorAttachments: 2);
    expect(
      const DeviceRequest(
        width: 1,
        height: 1,
        requiredLimits: <String, int>{'maxColorAttachments': 2},
      ).shortfallsOf(device),
      isEmpty,
    );
    expect(
      const DeviceRequest(
        width: 1,
        height: 1,
        requiredLimits: <String, int>{'maxColorAttachments': 4},
      ).shortfallsOf(device).single,
      contains('below the 4'),
    );
    expect(
      const DeviceRequest(
        width: 1,
        height: 1,
        requiredLimits: <String, int>{'minUniformBufferOffsetAlignment': 64},
      ).shortfallsOf(device).single,
      contains('above the 64'),
      reason: 'an alignment is met by a smaller number, not a larger one',
    );
    expect(
      () => const DeviceRequest(
        width: 1,
        height: 1,
        requiredLimits: <String, int>{'maxWarpDrive': 1},
      ).checkSatisfiedBy(device),
      throwsA(isA<DeviceUnavailableException>()),
    );
  });

  test('open with a size is a request for nothing else', () async {
    final registry = DeviceRegistry<Object>();
    final asked = <DeviceRequest>[];
    final device = FakeBackend();
    registry.addBackend('fake', (DeviceRequest request) async {
      asked.add(request);
      return device;
    });
    await registry.open(width: 3, height: 2);
    expect(asked.single, const DeviceRequest(width: 3, height: 2));
    expect(
      const DeviceRequest.compute().width,
      0,
      reason: 'a compute device presents nothing, so it has no size',
    );
    expect(PowerPreference.byName('high-performance'), isNotNull);
  });
}
