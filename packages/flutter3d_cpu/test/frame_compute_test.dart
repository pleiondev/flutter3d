/// [FrameCompute] over devices that compute: where the hardware layer puts
/// a step for frames drawn on a device, given the registry that opened or
/// adopted it, and where it leaves work with host code of its own.
///
///     dart test test/frame_compute_test.dart
library;

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart'
    show FakeBackend, computePlacementOf;
import 'package:test/test.dart';

void main() {
  test('a device opened without a registry computes on itself alone', () async {
    // Mutation: offer nothing for a device no registry opened, and a test's
    // own device refuses every step.
    final drawing = cpuComputeDevice();
    final PlacedWork(:site, :loaded) = await FrameCompute.of(
      drawing,
    ).place('blur', (GraphicsDevice d) async => d.backendName);
    expect(site.device, same(drawing));
    expect(site.isOnFrameDevice, isTrue);
    expect(loaded, drawing.backendName);
  });

  test(
    'a registry gives the devices it opens and adopts its compute',
    () async {
      // Mutation: leave the registry's sidecar out of what an adopted device's
      // frames are offered, and nothing above the hardware layer can reach it.
      final registry = DeviceRegistry<Object>();
      final sidecar = cpuComputeDevice();
      registry.addComputeDevice(
        ComputePlacement.sidecar,
        'beside',
        () async => sidecar,
      );
      final drawing = FakeBackend();
      registry.adopt(drawing);
      final PlacedWork(:site, :loaded) = await FrameCompute.of(
        drawing,
      ).place('blur', (GraphicsDevice d) async => true);
      expect(site.device, same(sidecar));
      expect(site.isOnFrameDevice, isFalse);
      expect(computePlacementOf(site), ComputePlacement.sidecar);

      registry.addBackend('fake', ({required width, required height}) async {
        return FakeBackend();
      });
      final opened = await registry.open(width: 4, height: 4);
      final PlacedWork(site: onOpened) = await FrameCompute.of(
        opened,
      ).place('blur', (GraphicsDevice d) async => true);
      expect(onOpened.device, same(sidecar));
    },
  );

  test('work the frame draws the same frame is kept off the sidecar', () async {
    // Mutation: offer the sidecar to skinning, and the frame draws vertices
    // that crossed the host a frame late.
    final registry = DeviceRegistry<Object>();
    final cpu = cpuComputeDevice();
    registry
      ..addComputeDevice(
        ComputePlacement.sidecar,
        'beside',
        () async => cpuComputeDevice(),
      )
      ..addComputeDevice(ComputePlacement.cpu, 'cpu', () async => cpu);
    final drawing = FakeBackend();
    registry.adopt(drawing);
    final PlacedWork(:site, :loaded) = await FrameCompute.of(
      drawing,
    ).place('skinning', (GraphicsDevice d) async => true, besideFrame: false);
    expect(site.device, same(cpu));
  });

  test(
    'a device that refuses the work passes it on, and keeps the cause',
    () async {
      // Mutation: stop at the first device whatever it said, and a kernel the
      // drawing device cannot compile is never tried on the CPU.
      final registry = DeviceRegistry<Object>();
      final cpu = cpuComputeDevice();
      registry.addComputeDevice(ComputePlacement.cpu, 'cpu', () async => cpu);
      final drawing = cpuComputeDevice();
      registry.adopt(drawing);
      final PlacedWork(:site, :loaded) = await FrameCompute.of(drawing).place(
        'blur',
        (GraphicsDevice d) async =>
            identical(d, drawing) ? throw StateError('no such stage') : true,
      );
      expect(site.device, same(cpu));
      final alone = cpuComputeDevice();
      await expectLater(
        FrameCompute.of(alone).place(
          'blur',
          (GraphicsDevice d) async => throw StateError('no such stage'),
        ),
        throwsA(
          isA<ComputePlacementException>()
              .having(
                (e) => e.reason,
                'reason',
                ComputeRefusalReason.kernelRefused,
              )
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
    },
  );

  test('work with host code is left to it rather than to software', () async {
    // Mutation: put it on the first device that loads it, and a core's own
    // step is replaced by its kernels interpreted on the CPU.
    final registry = DeviceRegistry<Object>();
    registry.addComputeDevice(
      ComputePlacement.cpu,
      'cpu',
      () async => cpuComputeDevice(),
    );
    final drawing = FakeBackend();
    registry.adopt(drawing);
    final compute = FrameCompute.of(drawing);
    expect(
      await compute.placeHosted(
        'water',
        (GraphicsDevice d) async => true,
        hasHost: true,
      ),
      isNull,
    );
    final placed = await compute.placeHosted(
      'water',
      (GraphicsDevice d) async => true,
      hasHost: false,
    );
    expect(computePlacementOf(placed!.site), ComputePlacement.cpu);
  });
}
