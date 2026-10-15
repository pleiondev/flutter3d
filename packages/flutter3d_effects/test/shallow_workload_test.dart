/// A shallow water handed to the engine as a compute workload: the same
/// physics code wherever the engine's rule puts it, and the same water as
/// the core's own step within the tolerance
/// `flutter3d_physics_native/doc/gpu_water.md` gives.
///
///     dart test test/shallow_workload_test.dart
///
/// The machines are set up the way an engine's device registry would set
/// them up, and the workload is the same object each time: where it runs is
/// the hardware layer's answer, read back from what it was told through the
/// hardware layer's test seam (`computePlacementOf`). Where nothing but the
/// software device computes, the rule leaves the water on the core — the
/// core's own step is written for the CPU, the software device would
/// interpret kernels written for a GPU — so to run the kernels here the
/// software device is made to stand in for a GPU
/// (`CpuDevice.standInForGpu`): for WebGPU drawing the frame, and for wgpu
/// beside one that does not compute. The workload asks for nothing.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart'
    show ShallowWaterWorkload;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart'
    show FakeBackend, computePlacementOf;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_wgpu/flutter3d_wgpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _nx = 10, _nz = 18;
const double _cell = 0.6;
const int _steps = 60;

/// A reach of river as the river game lays one under a bridge: a sill at
/// its upper end the river is let in over, a pool under it, a level edge
/// at its lower end, banks either side.
({NativeWorld world, NativeShallowLiquid water}) _reach() {
  final world = NativeWorld();
  final ground = <double>[
    for (var j = 0; j < _nz; j++)
      for (var i = 0; i < _nx; i++)
        if (i == 0 || i == _nx - 1)
          0.6
        else if (j < 4)
          0.52
        else if (j < 7)
          -0.7
        else
          -0.4 - 0.02 * (i - _nx / 2).abs(),
  ];
  final water = world.createShallowLiquid(
    nx: _nx,
    nz: _nz,
    cell: _cell,
    origin: Vector3.zero(),
    ground: ground,
  );
  world
    ..setShallowEdge(
      water,
      GridSide.south,
      const NativeEdgeFlow.inflow(discharge: 0.6),
    )
    ..setShallowEdge(water, GridSide.north, const NativeEdgeFlow.level(0.0))
    ..fillShallowLiquid(water, x0: -1, z0: -1, x1: 99, z1: 99, level: 0.0);
  return (world: world, water: water);
}

/// A stone dropped into the pool: what the core does round the columns,
/// crossing to wherever they are stepped as a change.
void _stone(NativeWorld world) {
  const r = 0.25;
  final stone = world.addBody(
    position: Vector3(_nx * _cell / 2, 0.3, 10 * _cell),
    mass: 1400.0 * 4.0 / 3.0 * math.pi * r * r * r,
  );
  world
    ..setShape(stone, NativeShape.sphere(r))
    ..setVelocity(stone, Vector3(0.0, -3.0, 0.0));
}

/// What a frame drawing nothing but a camera is: enough for the scene to
/// read what the workload writes, which keeps the workload in the frame.
void Function() _frames(Renderer renderer) {
  final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
  camera.lookAt(Vector3.zero());
  final scene = Scene()..add(camera);
  return () => renderer.render(
    width: 8,
    height: 8,
    scene: scene,
    views: <CameraView>[CameraView(camera: camera)],
  );
}

/// [_steps] frames of the reach drawn on [drawing], which [registry]
/// adopts when given one: what the core mirrors of it at the end, what it
/// was told, how much spray was in the air at most, and how many substeps
/// were run off the core.
Future<
  ({
    Float32List depth,
    WorkloadStep step,
    WorkloadBinding? binding,
    int spray,
    int moved,
  })
>
_run({
  required GraphicsDevice drawing,
  DeviceRegistry<Object>? registry,
  void Function(String message)? onRefused,
}) async {
  registry?.adopt(drawing, onRefused: onRefused);
  final (:world, :water) = _reach();
  addTearDown(world.dispose);
  final renderer = Renderer.create(device: drawing);
  final workload = ShallowWaterWorkload(world, water);
  final added = renderer.renderSteps.addWorkload(workload);
  await renderer.renderSteps.whenPlaced();
  addTearDown(added.cancel);
  final step = renderer.renderSteps.workloadStep(workload)!;
  final draw = _frames(renderer);
  var spray = 0, moved = 0;
  for (var s = 0; s < _steps; s++) {
    if (s == 20) _stone(world);
    world.step(1.0 / 60.0);
    draw();
    // The reads back land on the host's own turn.
    await Future<void>.delayed(Duration.zero);
    spray = math.max(spray, world.readSpray().length);
    moved += workload.lastSubsteps;
  }
  return (
    depth: world.readShallowSurface(water).depth,
    step: step,
    binding: workload.binding,
    spray: spray,
    moved: moved,
  );
}

/// The reach stepped by the core alone, as the host does it.
Float32List _onCore() {
  final (:world, :water) = _reach();
  addTearDown(world.dispose);
  for (var s = 0; s < _steps; s++) {
    if (s == 20) _stone(world);
    world.step(1.0 / 60.0);
  }
  return world.readShallowSurface(water).depth;
}

/// The water held over the grid, m³.
double _held(Float32List depth) =>
    depth.fold(0.0, (sum, d) => sum + d) * _cell * _cell;

FakeBackend _noCompute() => FakeBackend(maxColorAttachments: 4);

/// A software device standing in for a GPU.
CpuDevice _gpu() => cpuComputeDevice(standInForGpu: true);

void main() {
  test(
    'the drawing device\'s compute steps it, within the tolerance',
    () async {
      // Mutation: a kernel's flux scattered the wrong way round a column, or
      // a slope with its sign turned, and the pool drains or overfills.
      final ran = await _run(drawing: _gpu());
      expect(computePlacementOf(ran.binding!.site!), ComputePlacement.device);
      expect(ran.moved, greaterThanOrEqualTo(_steps));
      final core = _onCore();
      var worst = 0.0;
      for (var c = 0; c < core.length; c++) {
        worst = math.max(worst, (core[c] - ran.depth[c]).abs());
      }
      // The tolerance: a column within two centimetres, the water held within
      // one per cent, of the core's own step over a second of a falls with a
      // stone dropped into its pool.
      expect(worst, lessThan(0.02));
      expect(_held(ran.depth), closeTo(_held(core), 0.01 * _held(core)));
      // The falls off the sill is thrown as spray from the lips read back.
      expect(ran.spray, greaterThan(0));
    },
  );

  test('a sidecar steps it beside a drawing device without compute', () async {
    // Mutation: copy the drawn buffers only when the executor draws, and a
    // sidecar's water never reaches the frame — or place it on the CPU
    // device, and the binding names the wrong site.
    final registry = DeviceRegistry<Object>()
      ..addComputeDevice(
        ComputePlacement.sidecar,
        'beside',
        (_) async => _gpu(),
      )
      ..addComputeDevice(
        ComputePlacement.cpu,
        'cpu',
        (_) async => cpuComputeDevice(),
      );
    final ran = await _run(drawing: _noCompute(), registry: registry);
    expect(computePlacementOf(ran.binding!.site!), ComputePlacement.sidecar);
    final core = _onCore();
    expect(_held(ran.depth), closeTo(_held(core), 0.01 * _held(core)));
  });

  test('the wgpu sidecar steps it on a GPU, within the tolerance', () async {
    // The registry as a native application sets it up: a drawing device
    // without compute (Impeller's, standing in), the sidecar and the CPU
    // registered. Nothing is asked for: the rule puts the water on the
    // sidecar. Mutation: a kernel that reads a neighbour's velocity a row
    // off, and the GPU's water leaves the core's by more than the
    // tolerance.
    final registry = DeviceRegistry<Object>();
    final sidecar = registerWgpuSidecar(registry);
    final cpu = registerCpuBackend(registry);
    addTearDown(cpu.cancel);
    addTearDown(sidecar.cancel);
    final refused = <String>[];
    final ran = await _run(
      drawing: _noCompute(),
      registry: registry,
      onRefused: refused.add,
    );
    if (ran.binding!.isOnHost) {
      markTestSkipped('no wgpu sidecar here: ${refused.join('; ')}');
      return;
    }
    expect(computePlacementOf(ran.binding!.site!), ComputePlacement.sidecar);
    expect(ran.moved, greaterThanOrEqualTo(_steps));
    final core = _onCore();
    var worst = 0.0;
    for (var c = 0; c < core.length; c++) {
      worst = math.max(worst, (core[c] - ran.depth[c]).abs());
    }
    expect(worst, lessThan(0.02));
    expect(_held(ran.depth), closeTo(_held(core), 0.01 * _held(core)));
    expect(ran.spray, greaterThan(0));
  });

  test('a software device drawing the frame leaves it on the core', () async {
    // Mutation: place a workload with host code on a device that computes
    // on the CPU, and the water is stepped by kernels interpreted in Dart
    // while its own C step sits idle.
    final ran = await _run(drawing: cpuComputeDevice());
    expect(ran.binding!.isOnHost, isTrue);
    expect(ran.moved, 0);
    // On the host it is the core's step, bit for bit.
    expect(ran.depth, _onCore());
  });

  test('with only the CPU device, the core steps it itself', () async {
    // Mutation: prefer the CPU device to the workload's host code.
    final registry = DeviceRegistry<Object>()
      ..addComputeDevice(
        ComputePlacement.cpu,
        'cpu',
        (_) async => cpuComputeDevice(),
      );
    final ran = await _run(drawing: _noCompute(), registry: registry);
    expect(ran.binding!.isOnHost, isTrue);
    expect(ran.depth, _onCore());
  });

  test('with no compute anywhere, the core steps it itself', () async {
    final ran = await _run(drawing: _noCompute());
    expect(ran.binding!.isOnHost, isTrue);
    expect(ran.step.refusal, isNull);
    expect(ran.depth, _onCore());
  });
}
