/// A compute step put in the frame through `RendererSteps.addComputeStep`:
/// placed on the executors the device registry answers, then run by the
/// frame where it was placed. A drawing device without compute places it on
/// the CPU that `registerCpuBackend` added.
///
///     dart test test/compute_wiring_test.dart
///
/// What the step writes is read by a pass-through node after the scene, as
/// a particle draw would read it: a step whose output nothing in the frame
/// reads is culled, as any other node is (`compute_step_test.dart`).
///
/// Mutation: add the node without `prepare` in `addComputeStep` and the step
/// is never placed, so the frame skips it and nothing is recorded.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_shaders/kernel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

const _particles = ResourceId('test.particles');

/// Records where the frame ran it.
final class _Step extends ComputeStep {
  final List<ComputePlacement> ran = <ComputePlacement>[];

  @override
  String get name => 'test.particles';

  @override
  List<ResourceId> get writes => const <ResourceId>[_particles];

  @override
  List<ComputeKernel> get kernels => ComputeKernel.parseAll('''
compute Step {
  buffer p: f32[] read_write;
  kernel { }
}
''');

  @override
  void record(ComputeContext context) => ran.add(context.placement);
}

/// Reads the step's output, as a particle draw would, and hands the scene's
/// colour on unchanged.
final class _Reader extends RenderNode {
  @override
  String get name => 'test.reader';

  @override
  List<ResourceId> get reads => const <ResourceId>[
    _particles,
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

void main() {
  test(
    'a step is placed on the registered CPU and runs in the frame',
    () async {
      final device = FakeBackend(maxColorAttachments: 4);
      final registry = DeviceRegistry<Object>();
      final cpu = registerCpuBackend(registry);
      addTearDown(cpu.cancel);
      final renderer = Renderer.create(device: device);
      final step = _Step();

      final registration = await renderer.renderSteps.addComputeStep(
        step,
        await registry.computeExecutors(device),
      );
      expect(step.refusal, isNull);
      expect(step.executor!.placement, ComputePlacement.cpu);
      final reader = renderer.renderSteps.addNode(_Reader());

      final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
      camera.lookAt(Vector3.zero());
      void draw() => renderer.render(
        width: 16,
        height: 16,
        scene: Scene()..add(camera),
        views: <RenderView>[RenderView(camera: camera)],
      );
      draw();
      expect(step.ran, <ComputePlacement>[ComputePlacement.cpu]);

      // Taken out with what reads it, and the frame no longer runs it.
      registration.cancel();
      reader.cancel();
      draw();
      expect(step.ran, hasLength(1));
    },
  );

  test('a step nothing can run is added, and says why', () async {
    final device = FakeBackend(maxColorAttachments: 4);
    final renderer = Renderer.create(device: device);
    final step = _Step();
    await renderer.renderSteps.addComputeStep(
      step,
      await DeviceRegistry<Object>().computeExecutors(device),
    );
    expect(step.refusal!.reason, ComputeRefusalReason.noExecutor);
  });

  test('a workload with host code is kept off the software device', () {
    // Mutation: drop the isSoftware test from the workload rule, and a
    // physics core's water drawn by the software rasteriser is stepped by
    // its kernels interpreted in Dart rather than by the core.
    final device = cpuComputeDevice();
    expect(device.isSoftware, isTrue);
    final executors = ComputeExecutors(
      device: device,
      sidecar: cpuComputeDevice(),
      cpu: cpuComputeDevice(),
    );
    expect(executors.placeWorkload(step: 'water', hasHost: true), isNull);
    expect(executors.workloadCandidates(hasHost: true), isEmpty);
    // Without host code, the rule is the compute step's: the drawing
    // device first, software or not.
    expect(
      executors.placeWorkload(step: 'blur', hasHost: false)!.placement,
      ComputePlacement.device,
    );
    expect(
      executors.workloadCandidates(hasHost: false).map((e) => e.placement),
      <ComputePlacement>[
        ComputePlacement.device,
        ComputePlacement.sidecar,
        ComputePlacement.cpu,
      ],
    );
  });
}
