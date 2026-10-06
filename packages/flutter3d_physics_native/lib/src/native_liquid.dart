/// `flutter3d_physics`'s liquids stepped by the core: the [FluidSolver] a
/// run on [NativePhysics] gets from `PhysicsBackend.current.fluid`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;
import 'native_physics.dart';

/// The core's fluid solver: the spilt particles by `f3d_liquid_particles`,
/// a stream's parcels by `f3d_liquid_parcels` and a surface's modes by
/// `f3d_liquid_modes`, each what the reference does.
///
/// **Nothing is held.** Every call writes one step's state into the core's
/// memory, steps it and reads it back, as the reference moves the same
/// records in place, so a world can be stepped on either solver and read
/// the same way.
///
/// **Walls the core cannot describe are stepped on the reference.** The
/// core knows the walls a `FluidWorld` makes — a `PlaneObstacle`, and the
/// inside and outside of a `RevolvedVessel` — and the inside of any other
/// vessel, which has none. A caller's own `JetObstacle` is Dart code the
/// core cannot ask, so a step that meets one is the reference's.
final class NativeLiquid implements FluidSolver {
  const NativeLiquid();

  @override
  void moveParticles(ParticleMotion motion) {
    final n = motion.count;
    if (n == 0 || motion.substeps <= 0) return;
    final state = motion.state;
    const stride = ParticleMotion.particleFloats;
    // About the particles' middle: a particle's velocity is read off how
    // far it moved in a substep, and single precision keeps more of that
    // the nearer the numbers are to nought.
    // The middle in single precision, so the walls and the particles are
    // moved by exactly the same amount.
    double mean(int axis) =>
        Iterable<int>.generate(
          n,
        ).fold(0.0, (sum, i) => sum + state[i * stride + axis]) /
        n;
    final origin = Vector3(mean(0), mean(1), mean(2));
    final (ox, oy, oz) = (origin.x, origin.y, origin.z);
    final walls = liquidWalls(motion.walls, origin);
    if (walls == null) {
      const DartFluid().moveParticles(motion);
      return;
    }
    final local = Float64List.fromList(state);
    for (var i = 0; i < n; i++) {
      local[i * stride] -= ox;
      local[i * stride + 1] -= oy;
      local[i * stride + 2] -= oz;
    }
    final block = c.F32s.alloc(n * c.liquidParticleFloats);
    final records = _block(walls);
    final s = c.coreAlloc(c.F3dLiquidParticleSettingsLayout.size);
    try {
      block.setAll(local);
      for (var k = 0; k < 3; k++) {
        c.writeF32(
          s + c.F3dLiquidParticleSettingsLayout.gravity + k * 4,
          motion.gravity[k],
        );
      }
      for (final (offset, value) in <(int, double)>[
        (c.F3dLiquidParticleSettingsLayout.spacing, motion.spacing),
        (c.F3dLiquidParticleSettingsLayout.density, motion.medium.density),
        (
          c.F3dLiquidParticleSettingsLayout.kinematicViscosity,
          motion.medium.kinematicViscosity,
        ),
        (c.F3dLiquidParticleSettingsLayout.cohesion, motion.cohesion),
        (c.F3dLiquidParticleSettingsLayout.latticeSum, motion.latticeSum),
        (c.F3dLiquidParticleSettingsLayout.restStiffness, motion.restStiffness),
        (c.F3dLiquidParticleSettingsLayout.dt, motion.dt),
      ]) {
        c.writeF32(s + offset, value);
      }
      c.writeU32(
        s + c.F3dLiquidParticleSettingsLayout.substeps,
        motion.substeps,
      );
      c.writeU32(
        s + c.F3dLiquidParticleSettingsLayout.iterations,
        math.max(0, motion.iterations),
      );
      if (c.f3d_liquid_particles(block, n, records, walls.length, s) == 0) {
        throw StateError('the core refused the particles, or had no memory');
      }
      final out = block.copy(n * c.liquidParticleFloats);
      for (var i = 0; i < n; i++) {
        final at = i * stride;
        state
          ..[at] = out[at] + ox
          ..[at + 1] = out[at + 1] + oy
          ..[at + 2] = out[at + 2] + oz
          ..[at + 3] = out[at + 3]
          ..[at + 4] = out[at + 4]
          ..[at + 5] = out[at + 5];
      }
    } finally {
      block.free();
      records.free();
      c.coreFree(s);
    }
  }

  @override
  void flyParcels(ParcelFlight flight) {
    final n = flight.count;
    if (n == 0) return;
    final walls = liquidWalls(flight.walls, Vector3.zero());
    if (walls == null) {
      const DartFluid().flyParcels(flight);
      return;
    }
    final block = c.F32s.alloc(n * c.liquidParcelFloats);
    final records = _block(walls);
    final s = c.coreAlloc(c.F3dLiquidStreamSettingsLayout.size);
    try {
      block.setAll(flight.parcels);
      final medium = flight.medium;
      for (var k = 0; k < 3; k++) {
        c.writeF32(
          s + c.F3dLiquidStreamSettingsLayout.gravity + k * 4,
          flight.gravity[k],
        );
      }
      c.writeF32(s + c.F3dLiquidStreamSettingsLayout.dt, flight.dt);
      c.writeF32(
        s + c.F3dLiquidStreamSettingsLayout.cling,
        medium.surfaceTension *
            (1.0 + Portable.cos(medium.contactAngle)) /
            medium.density,
      );
      if (c.f3d_liquid_parcels(block, n, records, walls.length, s) == 0) {
        throw StateError('the core refused the parcels, or had no memory');
      }
      flight.parcels.setAll(0, block.copy(n * c.liquidParcelFloats));
    } finally {
      block.free();
      records.free();
      c.coreFree(s);
    }
  }

  @override
  void ringModes(ModeRinging ringing) {
    final n = ringing.count;
    if (n == 0) return;
    const stride = c.liquidModeFloats;
    final block = c.F32s.alloc(n * stride);
    final s = c.coreAlloc(c.F3dLiquidWaveSettingsLayout.size);
    try {
      block.setAll(<double>[
        for (var i = 0; i < n; i++) ...<double>[
          ringing.k2[i],
          ringing.norms[i],
          ringing.amplitude[i],
          ringing.rate[i],
          0.0,
          0.0,
        ],
      ]);
      final medium = ringing.medium;
      for (final (offset, value) in <(int, double)>[
        (c.F3dLiquidWaveSettingsLayout.dt, ringing.dt),
        (c.F3dLiquidWaveSettingsLayout.g, ringing.g),
        (c.F3dLiquidWaveSettingsLayout.depth, ringing.depth),
        (
          c.F3dLiquidWaveSettingsLayout.kinematicViscosity,
          medium.kinematicViscosity,
        ),
        (
          c.F3dLiquidWaveSettingsLayout.tension,
          medium.surfaceTension / medium.density,
        ),
        (c.F3dLiquidWaveSettingsLayout.area, ringing.area),
      ]) {
        c.writeF32(s + offset, value);
      }
      c.f3d_liquid_modes(block, n, s);
      final out = block.copy(n * stride);
      for (var i = 0; i < n; i++) {
        ringing.amplitude[i] = out[i * stride + 2];
        ringing.rate[i] = out[i * stride + 3];
        ringing.omega2[i] = out[i * stride + 4];
        ringing.decay[i] = out[i * stride + 5];
      }
    } finally {
      block.free();
      c.coreFree(s);
    }
  }
}

/// [records] in a block of the core's memory the caller frees.
c.F32s _block(List<double> records) {
  final block = c.F32s.alloc(math.max(1, records.length));
  if (records.isNotEmpty) block.setAll(records);
  return block;
}

/// [walls] as the records `f3d_liquid_particles` and `f3d_liquid_parcels`
/// read, about [origin]: each where it stands now, less [origin]. Null when
/// one is a wall the core cannot describe.
List<double>? liquidWalls(List<JetObstacle> walls, Vector3 origin) {
  final out = <double>[];
  for (final wall in walls) {
    switch (wall) {
      case PlaneObstacle(:final normal, :final offset):
        out.addAll(<double>[
          c.LiquidWallKind.plane.toDouble(),
          normal.x,
          normal.y,
          normal.z,
          offset - normal.dot(origin),
        ]);
      case InsideWalls(:final body):
        // Another shape's inside has no walls yet: nothing to describe.
        if (body.shape case final RevolvedVessel shape) {
          out.addAll(
            _vessel(
              c.LiquidWallKind.inside,
              body,
              shape,
              body.wallThickness,
              origin,
            ),
          );
        }
      case OutsideWalls(:final body, :final thickness):
        if (body.shape case final RevolvedVessel shape) {
          out.addAll(
            _vessel(c.LiquidWallKind.outside, body, shape, thickness, origin),
          );
        }
      default:
        return null;
    }
  }
  return out;
}

/// [body]'s vessel as a record of [kind], its glass [thickness] thick,
/// about [origin].
List<double> _vessel(
  int kind,
  LiquidBody body,
  RevolvedVessel shape,
  double thickness,
  Vector3 origin,
) => <double>[
  kind.toDouble(),
  body.position.x - origin.x,
  body.position.y - origin.y,
  body.position.z - origin.z,
  ...body.rotation.storage,
  thickness,
  shape.floor,
  shape.top,
  shape.widest,
  shape.radiusAt(shape.floor),
  shape.wall.length.toDouble(),
  for (final p in shape.wall) ...<double>[p.x, p.y],
];
