// The liquid's native lanes: refused where a run must replay, and every
// width the processor has within the stated tolerance of one lane.
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_physics_native/src/liquid_lanes.dart'
    show liquidLanesWidth;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Keeps the motion a fluid hands its solver, and moves nothing.
final class _Keep extends FluidSolver {
  ParticleMotion? motion;

  @override
  void moveParticles(ParticleMotion motion) => this.motion = motion;
}

/// A block of 27 particles two millimetres apart over a floor, one
/// substep, as a fluid hands it over.
ParticleMotion _block() {
  final keep = _Keep();
  ParticleFluid(medium: FluidMedium.water, spacing: 0.002, solver: keep)
    ..inject(
      27 * 8e-9,
      Vector3(0.0, 0.0035, 0.0),
      Vector3(0.05, -0.1, 0.0),
      asParticles: true,
    )
    ..step(
      1 / 240,
      gravity: Vector3(0, -9.81, 0),
      obstacles: [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0.0)],
    );
  final m = keep.motion!;
  return ParticleMotion(
    state: Float64List.fromList(m.state),
    medium: m.medium,
    spacing: m.spacing,
    iterations: m.iterations,
    substeps: 1,
    dt: m.dt,
    gravity: m.gravity,
    cohesion: m.cohesion,
    latticeSum: m.latticeSum,
    restStiffness: m.restStiffness,
    walls: m.walls,
  );
}

Float64List _moved(FluidSolver solver, ParticleMotion m) {
  final state = Float64List.fromList(m.state);
  solver.moveParticles(
    ParticleMotion(
      state: state,
      medium: m.medium,
      spacing: m.spacing,
      iterations: m.iterations,
      substeps: m.substeps,
      dt: m.dt,
      gravity: m.gravity,
      cohesion: m.cohesion,
      latticeSum: m.latticeSum,
      restStiffness: m.restStiffness,
      walls: m.walls,
    ),
  );
  return state;
}

void main() {
  test('the native lanes are refused where a run must replay', () {
    // Their bytes are not the CPU kernel's, and a replay checks bytes.
    // Mutation: hand them out whatever the profile, and a deterministic
    // match diverges between an AVX2 machine and a phone.
    expect(KernelLiquid.native(), isNull);
    final loose = KernelLiquid.native(profile: SimulationProfile.accurate);
    if (KernelLiquid.isNativeLanesBuilt) {
      expect(loose!.isNativeLanes, isTrue);
      expect(loose.backend, KernelLiquid.nativeBackend);
    } else {
      expect(loose, isNull);
    }
  });

  test(
    'every width the processor has steps within the tolerance of one lane',
    () {
      // Two, four and eight neighbours at a time add in other orders than
      // one at a time. Mutation: let a masked lane through (a neighbour
      // past the reach, or the particle itself), and a width parts from the
      // others by far more.
      final motion = _block();
      final liquid = KernelLiquid.native(profile: SimulationProfile.accurate)!;
      final widths = <int>[1, 2, 4, 8];
      final runs = <int, Float64List>{};
      for (final lanes in widths) {
        if (liquidLanesWidth(lanes: lanes) != lanes) continue;
        runs[lanes] = _moved(liquid, motion);
      }
      liquidLanesWidth(lanes: 0);
      expect(runs.keys, containsAll(<int>[1, 2]));
      final one = runs[1]!;
      var fastest = 0.0;
      for (var i = 3; i < one.length; i += 6) {
        for (var k = 0; k < 3; k++) {
          fastest = math.max(fastest, one[i + k].abs());
        }
      }
      for (final MapEntry(key: lanes, value: run) in runs.entries) {
        for (var i = 0; i < one.length; i++) {
          final scale = i % 6 < 3 ? motion.spacing : fastest;
          expect(
            (run[i] - one[i]).abs(),
            lessThan(KernelLiquid.nativeTolerance * scale),
            reason: '$lanes lanes, value $i',
          );
        }
      }
    },
    skip: KernelLiquid.isNativeLanesBuilt
        ? false
        : 'the hook built no native lanes here',
  );
}
