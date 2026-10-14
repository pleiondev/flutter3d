/// A shallow water handed to the engine as a compute workload: the same
/// physics code wherever the engine's rule puts it, and the same water as
/// the core's own step within the tolerance `doc/gpu_water.md` gives.
///
///     dart test test/shallow_workload_test.dart
///
/// Four machines, set up the way an engine's device registry would: a
/// drawing device that computes (the software device, standing in for
/// WebGPU), one that does not with a compute sidecar beside it (the
/// software device again, standing in for wgpu), one that does not with
/// only the CPU executor, and one with nothing. The workload is the same
/// object each time; where it runs is the engine's answer, read back from
/// what it was told.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart'
    show ShallowWaterWorkload;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _nx = 10, _nz = 18;
const double _cell = 0.6;

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
    views: <RenderView>[RenderView(camera: camera)],
  );
}

/// [steps] frames of the reach on [executors], drawn by [renderer]: what
/// the core mirrors of it at the end, where it ran, and how much fell.
Future<({Float32List depth, WorkloadBinding binding, int spray, int moved})>
_run({
  required Renderer renderer,
  required ComputeExecutors executors,
  required int steps,
}) async {
  final (:world, :water) = _reach();
  addTearDown(world.dispose);
  final workload = ShallowWaterWorkload(world, water);
  final added = await renderer.renderSteps.addWorkload(workload, executors);
  addTearDown(added.cancel);
  // Where the engine put it, as the renderer reports it.
  expect(renderer.renderSteps.workloadStep(workload)!.refusal, isNull);
  final draw = _frames(renderer);
  var spray = 0, moved = 0;
  for (var s = 0; s < steps; s++) {
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
    binding: workload.binding!,
    spray: spray,
    moved: moved,
  );
}

/// The reach stepped by the core alone, as the host does it.
Float32List _onCore(int steps) {
  final (:world, :water) = _reach();
  addTearDown(world.dispose);
  for (var s = 0; s < steps; s++) {
    if (s == 20) _stone(world);
    world.step(1.0 / 60.0);
  }
  return world.readShallowSurface(water).depth;
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

/// The water held over the grid, m³.
double _held(Float32List depth) =>
    depth.fold(0.0, (sum, d) => sum + d) * _cell * _cell;

void main() {
  const steps = 60;

  test('a computing drawing device steps it, within the tolerance', () async {
    // Mutation: a kernel's flux scattered the wrong way round a column, or
    // a slope with its sign turned, and the pool drains or overfills.
    final device = cpuComputeDevice();
    final ran = await _run(
      renderer: Renderer.create(device: device),
      executors: ComputeExecutors(device: device),
      steps: steps,
    );
    expect(ran.binding.placement, ComputePlacement.device);
    expect(ran.moved, greaterThanOrEqualTo(steps));
    final core = _onCore(steps);
    var worst = 0.0;
    for (var c = 0; c < core.length; c++) {
      worst = math.max(worst, (core[c] - ran.depth[c]).abs());
    }
    // `doc/gpu_water.md`: a column within two centimetres, the water held
    // within one per cent, of the core's own step over a second of a
    // falls with a stone dropped into its pool.
    expect(worst, lessThan(0.02));
    expect(_held(ran.depth), closeTo(_held(core), 0.01 * _held(core)));
    // The falls off the sill is thrown as spray from the lips read back.
    expect(ran.spray, greaterThan(0));
  });

  test('a sidecar steps it where the drawing device cannot', () async {
    // Mutation: place on the CPU executor ahead of the sidecar, and the
    // binding names the wrong placement.
    final ran = await _run(
      renderer: Renderer.create(device: FakeBackend(maxColorAttachments: 4)),
      executors: ComputeExecutors(
        device: FakeBackend(maxColorAttachments: 4),
        sidecar: cpuComputeDevice(),
        cpu: cpuComputeDevice(),
      ),
      steps: steps,
    );
    expect(ran.binding.placement, ComputePlacement.sidecar);
    final core = _onCore(steps);
    expect(_held(ran.depth), closeTo(_held(core), 0.01 * _held(core)));
  });

  test('with only the CPU executor, the core steps it itself', () async {
    // Mutation: prefer the CPU executor to the workload's host code, and
    // the water is stepped by kernels interpreted in Dart while its own C
    // step sits idle.
    final ran = await _run(
      renderer: Renderer.create(device: FakeBackend(maxColorAttachments: 4)),
      executors: ComputeExecutors(
        device: FakeBackend(maxColorAttachments: 4),
        cpu: cpuComputeDevice(),
      ),
      steps: steps,
    );
    expect(ran.binding.isOnHost, isTrue);
    expect(ran.moved, 0);
    // On the host it is the core's step, bit for bit.
    expect(ran.depth, _onCore(steps));
  });

  test('with no compute anywhere, the core steps it itself', () async {
    final ran = await _run(
      renderer: Renderer.create(device: FakeBackend(maxColorAttachments: 4)),
      executors: ComputeExecutors(device: FakeBackend(maxColorAttachments: 4)),
      steps: steps,
    );
    expect(ran.binding.isOnHost, isTrue);
    expect(ran.depth, _onCore(steps));
  });
}
