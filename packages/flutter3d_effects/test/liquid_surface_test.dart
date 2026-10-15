/// A water's surface built by kernels where the water is stepped, against
/// the one `LiquidView` builds on the CPU from the same water.
///
///     dart test test/liquid_surface_test.dart
///
/// The kernels run on the software device's compute, made to stand in for
/// a GPU (`CpuDevice.standInForGpu`), as a GPU would run them; the water is stepped there, read back into the core, and
/// a view that never handed its water over writes its vertices from what
/// the core then holds. Every vertex's sixteen floats agree.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_effects/src/liquid_surface_kernels.dart';
import 'package:flutter3d_effects/src/vertices.dart' show vertexFloats;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart' show computePlacementOf;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _nx = 14, _nz = 12;
const double _cell = 0.5;

/// The water's step and its surface, the vertices read back after each
/// frame.
final class _Surface extends ShallowWaterWorkload {
  _Surface(super.world, super.water);

  Float32List? vertices;

  @override
  String get kernelSource =>
      '${ShallowWaterWorkload.kernels}\n$liquidSurfaceKernels';

  @override
  List<WorkloadBuffer> get buffers => <WorkloadBuffer>[
    ...super.buffers,
    WorkloadBuffer('look', 3 * water.cells * 4),
    WorkloadBuffer('air', water.cells * 4),
    const WorkloadBuffer('view', 16),
    WorkloadBuffer(
      'vertices',
      water.cells * vertexFloats * 4,
      drawn: true,
      readable: true,
    ),
  ];

  @override
  void recordAfterStep(WorkloadRecorder recorder) {
    final o = water.origin;
    recorder.write(
      'view',
      ByteData.sublistView(
        Float32List.fromList(<double>[o.x, o.y, o.z, _cell]),
      ),
    );
    final groups = (water.cells + 63) ~/ 64;
    recorder
      ..dispatch('SurfaceHeights', groups)
      ..dispatch('SurfaceVertices', groups)
      ..readBack(
        'vertices',
        (bytes) => vertices = Float32List.fromList(
          bytes.buffer.asFloat32List(bytes.offsetInBytes, water.cells * 16),
        ),
      );
  }
}

void main() {
  test('the surface built by kernels is the one the CPU builds', () async {
    // Mutation: a dry cell beside water drawn at its own ground, or the
    // flow's colour read off one face, and the vertices part.
    final world = NativeWorld();
    addTearDown(world.dispose);
    // A basin with sloping banks and an island, so the shore, the banks and
    // the sunk cells are all drawn.
    final ground = <double>[
      for (var j = 0; j < _nz; j++)
        for (var i = 0; i < _nx; i++)
          i < 2 || i >= _nx - 2
              ? 0.4 + 0.1 * (i < 2 ? 2 - i : i - _nx + 3)
              : (i == 7 && j == 6 ? 0.3 : -0.3 + 0.02 * j),
    ];
    final water = world.createShallowLiquid(
      nx: _nx,
      nz: _nz,
      cell: _cell,
      origin: Vector3(1.0, 0.5, -2.0),
      ground: ground,
    );
    world
      ..setShallowEdge(
        water,
        GridSide.south,
        const NativeEdgeFlow.inflow(discharge: 0.2),
      )
      ..setShallowEdge(water, GridSide.north, const NativeEdgeFlow.level(0.6))
      ..fillShallowLiquid(water, x0: -9, z0: -9, x1: 99, z1: 99, level: 0.6)
      ..pourShallowLiquid(water, 4.0, 0.5, radius: 0.6, volume: 0.4);
    // A box floating in it, which stands in the columns it fills: the
    // surface over it is the water's and what the box fills of it.
    final box = world.addBody(position: Vector3(5.0, 0.6, 1.0), mass: 20.0);
    world.setShape(box, NativeShape.box(Vector3(0.6, 0.15, 0.6)));
    final device = cpuComputeDevice(standInForGpu: true);
    final renderer = Renderer.create(device: device);
    final workload = _Surface(world, water);
    final added = await renderer.renderSteps.addWorkload(workload);
    addTearDown(added.cancel);
    expect(
      computePlacementOf(workload.binding!.site!),
      ComputePlacement.device,
    );
    final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
    final scene = Scene()..add(camera);
    for (var s = 0; s < 20; s++) {
      world.step(1.0 / 60.0);
      renderer.render(
        width: 8,
        height: 8,
        scene: scene,
        views: <CameraView>[CameraView(camera: camera)],
      );
      await Future<void>.delayed(Duration.zero);
    }
    final gpu = workload.vertices!;
    // A view the water was never handed to, drawing from what the core
    // now holds: the state the kernels built their surface from.
    final view = LiquidView(
      world: world,
      liquid: water,
      ground: ground,
      device: device,
      scene: Scene(),
      look: RenderMaterial(name: 'water'),
    )..update();
    final cpu = view.surfaceVertices;
    expect(gpu.length, cpu.length);
    var worst = 0.0;
    var at = -1;
    for (var k = 0; k < cpu.length; k++) {
      final d = (gpu[k] - cpu[k]).abs();
      if (d > worst) (worst, at) = (d, k);
    }
    expect(worst, lessThan(1e-4), reason: 'float $at of ${cpu.length}');
  });
}
