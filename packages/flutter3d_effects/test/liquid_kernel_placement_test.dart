// The spilt liquid's pair loops as kernels, placed by the hardware layer,
// and the native lanes beside them.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Keeps the motion a fluid hands its solver, and moves nothing.
final class _Keep extends FluidSolver {
  ParticleMotion? motion;

  @override
  void moveParticles(ParticleMotion motion) => this.motion = motion;
}

/// A block of 27 particles two millimetres apart, squeezed a little, a
/// metre from the origin over a floor: the motion a fluid hands over, with
/// [substeps] substeps.
ParticleMotion _block({int substeps = 2}) {
  final keep = _Keep();
  final fluid =
      ParticleFluid(medium: FluidMedium.water, spacing: 0.002, solver: keep)
        ..inject(
          27 * 8e-9,
          Vector3(1.0, 0.0035, -0.5),
          Vector3(0.05, -0.1, 0.0),
          asParticles: true,
        );
  fluid.step(
    1 / 240,
    gravity: Vector3(0, -9.81, 0),
    obstacles: [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0.0)],
  );
  final m = keep.motion!;
  // Squeezed by a tenth, so the density has something to hold.
  final state = Float64List.fromList(m.state);
  for (var i = 0; i < m.count; i++) {
    for (var k = 0; k < 3; k++) {
      final at = i * ParticleMotion.particleFloats + k;
      final middle = <double>[1.0, 0.0035, -0.5][k];
      state[at] = middle + (state[at] - middle) * 0.9;
    }
  }
  return ParticleMotion(
    state: state,
    medium: m.medium,
    spacing: m.spacing,
    iterations: m.iterations,
    substeps: substeps,
    dt: m.dt,
    gravity: m.gravity,
    cohesion: m.cohesion,
    latticeSum: m.latticeSum,
    restStiffness: m.restStiffness,
    walls: m.walls,
  );
}

/// [motion] again, its state its own.
ParticleMotion _copy(ParticleMotion motion) => ParticleMotion(
  state: Float64List.fromList(motion.state),
  medium: motion.medium,
  spacing: motion.spacing,
  iterations: motion.iterations,
  substeps: motion.substeps,
  dt: motion.dt,
  gravity: motion.gravity,
  cohesion: motion.cohesion,
  latticeSum: motion.latticeSum,
  restStiffness: motion.restStiffness,
  walls: motion.walls,
);

Float64List _moved(FluidSolver solver, ParticleMotion motion) {
  final copy = _copy(motion);
  solver.moveParticles(copy);
  return copy.state;
}

/// The largest difference of a position and of a velocity between [a] and
/// [b].
({double position, double velocity}) _apart(Float64List a, Float64List b) {
  var position = 0.0;
  var velocity = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (i % ParticleMotion.particleFloats < 3) {
      position = math.max(position, d);
    } else {
      velocity = math.max(velocity, d);
    }
  }
  return (position: position, velocity: velocity);
}

void main() {
  test('the pair loops are six kernels within the portable profile', () {
    // Past the profile, a kernel would run on some machines and be refused
    // on others. Mutation: bind an eighth buffer, or a workgroup of 256.
    final kernels = ComputeKernel.parseAll(liquidPairKernels);
    expect(kernels.map((k) => k.name), <String>[
      'LiquidDensity',
      'LiquidNormal',
      'LiquidForce',
      'LiquidLambda',
      'LiquidDelta',
      'LiquidSmooth',
    ]);
    for (final k in kernels) {
      expect(
        k.workgroupSize.invocations,
        lessThanOrEqualTo(PortableComputeProfile.maxInvocationsPerWorkgroup),
      );
      expect(
        k.bindings.length,
        lessThanOrEqualTo(PortableComputeProfile.maxStorageBuffersPerStage),
      );
      expect(k.binding('params')!.writable, isFalse);
    }
  });

  test('a deterministic run lands on the CPU kernel and gives the same '
      'bytes every time', () async {
    // Mutation: round anything on the host through another path, or take
    // the neighbours in an order a hash map chooses, and two runs from one
    // state part in the last bits.
    final liquid = await placeKernelLiquid(FrameCompute.of(cpuComputeDevice()));
    expect(liquid.isNativeLanes, isFalse);
    expect(liquid.backend, cpuComputeDevice().backendName);
    final motion = _block();
    final once = _moved(liquid, motion);
    final again = _moved(
      await placeKernelLiquid(FrameCompute.of(cpuComputeDevice())),
      motion,
    );
    expect(
      Uint8List.sublistView(again),
      orderedEquals(Uint8List.sublistView(once)),
    );
    // And it moved: gravity, the floor and the squeeze all had a say.
    expect(_apart(once, motion.state).position, greaterThan(1e-6));
  });

  test('the kernels step as the reference does, to single precision', () async {
    // The reference sums in doubles in another order and parts coincident
    // particles inside its sums; the kernels round to f32 after every
    // operation. Two substeps of a squeezed block land within a hundredth
    // of a micrometre and ten micrometres a second of each other, where it
    // moved more than a millimetre and fell at sixteen centimetres a
    // second. Mutation: drop
    // the artificial pressure from the kernels' solve, or read the wrong
    // neighbour's normal, and they part by far more.
    final liquid = await placeKernelLiquid(FrameCompute.of(cpuComputeDevice()));
    final motion = _block();
    final apart = _apart(
      _moved(liquid, motion),
      _moved(const DartFluid(), motion),
    );
    expect(apart.position, lessThan(1e-8));
    expect(apart.velocity, lessThan(1e-5));
  });

  test('where the run must replay, a GPU is passed over, by its reason', () {
    // A device that does its work on a GPU computes division and square
    // roots to within a tolerance, so bit-exact work never lands there.
    // Mutation: leave the requirement out, and the stand-in takes it.
    expect(
      placeKernelLiquid(FrameCompute.of(cpuComputeDeviceStandingInForGpu())),
      throwsA(
        isA<ComputePlacementException>().having(
          (e) => e.message,
          'message',
          contains('same bytes on every machine'),
        ),
      ),
    );
  });

  test('the native lanes run only where the run need not replay', () async {
    final compute = FrameCompute.of(cpuComputeDevice());
    // Mutation: hand the hardware layer no lanes, and an accurate run never
    // reaches them; or admit them under bitExact, and a replay diverges.
    final strict = await placeKernelLiquid(compute);
    expect(strict.isNativeLanes, isFalse);
    final loose = await placeKernelLiquid(
      compute,
      profile: SimulationProfile.accurate,
    );
    expect(loose.isNativeLanes, KernelLiquid.isNativeLanesBuilt);
    expect(
      loose.backend,
      KernelLiquid.isNativeLanesBuilt
          ? KernelLiquid.nativeBackend
          : cpuComputeDevice().backendName,
    );
  });

  test(
    'the native lanes are held to the CPU kernel within the stated '
    'tolerance',
    () async {
      // One substep of the squeezed block on either: positions within the
      // tolerance's share of a spacing, velocities within its share of the
      // fastest. Mutation: drop the crowd the lanes write, and the density
      // is held for no iterations; or sum a lane twice.
      final compute = FrameCompute.of(cpuComputeDevice());
      final kernel = await placeKernelLiquid(compute);
      final lanes = await placeKernelLiquid(
        compute,
        profile: SimulationProfile.accurate,
      );
      final motion = _block(substeps: 1);
      final a = _moved(kernel, motion);
      final b = _moved(lanes, motion);
      var fastest = 0.0;
      for (var i = 0; i < a.length; i++) {
        if (i % ParticleMotion.particleFloats >= 3) {
          fastest = math.max(fastest, a[i].abs());
        }
      }
      final apart = _apart(a, b);
      expect(
        apart.position,
        lessThan(KernelLiquid.nativeTolerance * motion.spacing),
      );
      expect(apart.velocity, lessThan(KernelLiquid.nativeTolerance * fastest));
    },
    skip: KernelLiquid.isNativeLanesBuilt
        ? false
        : 'the hook built no native lanes here',
  );
}
