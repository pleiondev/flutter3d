/// A compute step put in the frame through `RendererSteps.addComputeStep`:
/// placed by the hardware layer on the compute the device's registry has,
/// then run by the frame where it was placed. A drawing device without
/// compute places it on the CPU that `registerCpuBackend` added.
///
///     dart test test/compute_wiring_test.dart
///
/// What the step writes is read by a pass-through node after the scene, as
/// a particle draw would read it: a step whose output nothing in the frame
/// reads is culled, as any other node is (`compute_step_test.dart`).
///
/// Mutation: add the node without `prepare` in `addComputeStep` and the step
/// is never placed, so the frame skips it and nothing is recorded.
///
/// The registration is synchronous and the placement loads behind it: the
/// frames before it lands are drawn without the step (`PassSkip.pending`).
/// A node that is not a compute step asks for compute of its own with
/// `FrameGraphBuilder.place`, and the renderer's placer takes the request
/// to the hardware layer. Mutation: compile the frame without `placer:` and
/// that node is unsupported for ever.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart'
    show FakeBackend, computePlacementOf;
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
  void record(ComputeContext context) =>
      ran.add(computePlacementOf(context.site));
}

/// A node that is not a compute step and asks for compute of its own: what
/// it is handed is where the frame's placer put its kernels.
final class _Placed extends RenderNode {
  final List<ComputeNodePlacement> placements = <ComputeNodePlacement>[];

  static final List<ComputeKernel> _kernels = ComputeKernel.parseAll('''
compute Step {
  buffer p: f32[] read_write;
  kernel { }
}
''');

  @override
  String get name => 'test.placed';

  @override
  List<ResourceId> get writes => const <ResourceId>[_particles];

  @override
  void setup(FrameGraphBuilder builder) {
    super.setup(builder);
    builder.place(ComputePlacementRequest(_kernels));
  }

  @override
  void execute(RenderFrame frame) =>
      placements.add(frame.placement! as ComputeNodePlacement);
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

      registry.adopt(device);
      final registration = renderer.renderSteps.addComputeStep(step);
      await renderer.renderSteps.whenPlaced();
      expect(step.refusal, isNull);
      expect(computePlacementOf(step.site!), ComputePlacement.cpu);
      final reader = renderer.renderSteps.addNode(_Reader());

      final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
      camera.lookAt(Vector3.zero());
      void draw() => renderer.render(
        width: 16,
        height: 16,
        scene: Scene()..add(camera),
        views: <CameraView>[CameraView(camera: camera)],
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

  test('a step is in the frame at once, pending until it is placed', () async {
    // Mutation: report a step that is still loading as unsupported, and a
    // caller looks through its hardware for a limit that is a load.
    final device = FakeBackend(maxColorAttachments: 4);
    final registry = DeviceRegistry<Object>();
    final cpu = registerCpuBackend(registry);
    addTearDown(cpu.cancel);
    final renderer = Renderer.create(device: device);
    final step = _Step();
    registry.adopt(device);
    final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
    camera.lookAt(Vector3.zero());
    FrameResult draw() => renderer.render(
      width: 16,
      height: 16,
      scene: Scene()..add(camera),
      views: <CameraView>[CameraView(camera: camera)],
    );

    renderer.renderSteps
      ..addComputeStep(step)
      ..addNode(_Reader());
    final before = draw();
    expect(
      before.skipped,
      contains(
        const SkippedPass(name: 'test.particles', reason: PassSkip.pending),
      ),
    );
    expect(
      before.skipped,
      contains(
        const SkippedPass(name: 'test.reader', reason: PassSkip.starved),
      ),
    );
    expect(step.ran, isEmpty);

    await renderer.renderSteps.whenPlaced();
    draw();
    expect(step.ran, <ComputePlacement>[ComputePlacement.cpu]);
  });

  test(
    'a node asks for compute with place, and the renderer places it',
    () async {
      final device = FakeBackend(maxColorAttachments: 4);
      final registry = DeviceRegistry<Object>();
      final cpu = registerCpuBackend(registry);
      addTearDown(cpu.cancel);
      final renderer = Renderer.create(device: device);
      registry.adopt(device);
      final node = _Placed();
      renderer.renderSteps
        ..addNode(node)
        ..addNode(_Reader());
      final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
      camera.lookAt(Vector3.zero());
      FrameResult draw() => renderer.render(
        width: 16,
        height: 16,
        scene: Scene()..add(camera),
        views: <CameraView>[CameraView(camera: camera)],
      );

      expect(
        draw().skipped,
        contains(
          const SkippedPass(name: 'test.placed', reason: PassSkip.pending),
        ),
      );
      expect(node.placements, isEmpty);
      await renderer.renderSteps.whenPlaced();
      draw();
      draw();
      expect(node.placements, hasLength(2));
      final placed = node.placements.first;
      expect(computePlacementOf(placed.site), ComputePlacement.cpu);
      expect(() => placed.stage('Step'), returnsNormally);
    },
  );

  test('a step nothing can run is added, and says why', () async {
    final device = FakeBackend(maxColorAttachments: 4);
    final renderer = Renderer.create(device: device);
    final step = _Step();
    DeviceRegistry<Object>().adopt(device);
    renderer.renderSteps.addComputeStep(step);
    await renderer.renderSteps.whenPlaced();
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
