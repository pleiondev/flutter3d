/// Liquid on the run's backend: the core's `f3d_liquid_*` held to the
/// reference on the scenes its users step — a block of spilt liquid in a
/// box, drops falling into a test tube with a round bottom, a stream
/// running down the inside of a glass and one clinging to the outside of
/// the glass it is poured from, a knocked surface ringing down, a U-tube
/// swinging and a thick liquid creeping level through a pipe, a block, a
/// ball and a capsule floating and settling, and a whole pour from one tube
/// into another.
///
/// The two are not promised to agree to the bit, only each with itself:
/// the core works in single precision and sums neighbours in another
/// order, and it is held to where the reference puts the liquid within a
/// tolerance that leaves room for that.
///
///     flutter test test/native_liquid_test.dart
///     flutter test --dart-define=FLUTTER3D_PHYSICS=dart \
///         test/native_liquid_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const FluidSolver _core = NativeLiquid();
const FluidSolver _reference = DartFluid();

/// A closed box of planes from (0, 0, 0) to [size].
List<JetObstacle> _box(double size) => [
  PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0),
  PlaneObstacle(normal: Vector3(1, 0, 0), offset: 0),
  PlaneObstacle(normal: Vector3(-1, 0, 0), offset: -size),
  PlaneObstacle(normal: Vector3(0, 0, 1), offset: 0),
  PlaneObstacle(normal: Vector3(0, 0, -1), offset: -size),
];

RevolvedVessel _tube(double r, double h) =>
    RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, h)]);

/// A block of six by six by six particles [s] apart, let go a centimetre
/// above the floor of a box six spacings wide, stepped [steps] times; its
/// columns started [nudge] of their place apart, a part in ten million
/// being single precision's own.
ParticleFluid _block(FluidSolver solver, int steps, {double nudge = 0.0}) {
  const s = 0.005;
  final fluid = ParticleFluid(
    medium: FluidMedium.water,
    spacing: s,
    solver: solver,
  );
  for (var i = 0; i < 6; i++) {
    for (var j = 0; j < 6; j++) {
      for (var k = 0; k < 6; k++) {
        fluid.inject(
          fluid.particleVolume,
          Vector3(
            (i + 0.5) * s * (1 + nudge * ((7 * i + 3 * j + k) % 5 - 2)),
            (j + 0.5) * s + 0.01,
            (k + 0.5) * s,
          ),
          Vector3.zero(),
        );
      }
    }
  }
  final walls = _box(6 * s);
  for (var t = 0; t < steps; t++) {
    fluid.step(1 / 600, gravity: Vector3(0, -9.81, 0), obstacles: walls);
  }
  return fluid;
}

/// The farthest any point of [a] is from the same point of [b].
double _apart(List<Vector3> a, List<Vector3> b) {
  expect(a.length, b.length);
  var worst = 0.0;
  for (var i = 0; i < a.length; i++) {
    worst = math.max(worst, (a[i] - b[i]).length);
  }
  return worst;
}

/// A narrow tube tipped over a wide one, pouring for [steps] steps of a
/// world on [solver].
({FluidWorld world, LiquidBody source, LiquidBody target, double total}) _pour(
  FluidSolver solver, {
  int steps = 480,
}) {
  final world = FluidWorld(
    gravity: Vector3(0, -9.81, 0),
    floor: [PlaneObstacle(normal: Vector3(0, 1, 0), offset: -0.01)],
    solver: solver,
  );
  final source = LiquidBody(
    shape: _tube(0.008, 0.1),
    medium: FluidMedium.water,
    volume: math.pi * 0.008 * 0.008 * 0.07,
    modes: 6,
    wallThickness: 0.0008,
  );
  final target = LiquidBody(
    shape: _tube(0.012, 0.1),
    medium: FluidMedium.water,
    volume: 0.0,
    modes: 6,
    wallThickness: 0.0008,
  );
  world.bodies.addAll([source, target]);
  final total = source.volume;
  for (var i = 0; i < steps; i++) {
    source.place(Matrix3.rotationX(1.3), Vector3(0, 0.1, -0.1045));
    target.place(Matrix3.identity(), Vector3.zero());
    world.advance(world.step);
  }
  return (world: world, source: source, target: target, total: total);
}

void main() {
  test(
    'the run\'s fluid is the core, unless the build asked for Dart',
    () async {
      final start = await startPhysics();
      // Mutation: NativePhysics without FluidPhysics, and the run's liquids
      // fall back to the reference.
      expect(
        PhysicsBackend.current.fluid,
        askedPhysics == 'dart' ? isA<DartFluid>() : isA<NativeLiquid>(),
      );
      expect(start.fallbackBecause, isNull);
      // A world made now is on it.
      expect(
        FluidWorld(gravity: Vector3(0, -9.81, 0)).solver,
        same(PhysicsBackend.current.fluid),
      );
    },
  );

  group('spilt particles', () {
    test('a block in a box falls and settles where the reference\'s does', () {
      // **No further from the reference than the reference is from
      // itself.** A block pulled into a ball by its own surface tension,
      // and struck on the floor, takes a difference in the seventh digit to
      // a tenth of a millimetre in ten steps: the reference started a part
      // in ten million apart goes as far from itself. So as it falls and
      // first strikes the floor, every particle on the core is within twice
      // that of the reference's. Mutation: the core's cohesion with the
      // wrong sign, or its density passes held to the stretched as well as
      // the squeezed, and the block is centimetres from it.
      final reference30 = _block(_reference, 30).positions;
      final spread = _apart(
        _block(_reference, 30, nudge: 1e-7).positions,
        reference30,
      );
      expect(spread, lessThan(1e-3));
      expect(
        _apart(_block(_core, 30).positions, reference30),
        lessThan(2 * spread),
      );
      // A second in, where the splash has gone its own way, it lies as
      // deep: at its rest density, its mean height within a twentieth of a
      // spacing of the reference's, all of it in the box.
      final core = _block(_core, 600).positions;
      final reference = _block(_reference, 600).positions;
      double mean(List<Vector3> ps) =>
          ps.fold(0.0, (s, p) => s + p.y) / ps.length;
      expect(mean(core), closeTo(mean(reference), 0.05 * 0.005));
      for (final p in core) {
        expect(p.x, inInclusiveRange(-1e-5, 0.03 + 1e-5));
        expect(p.z, inInclusiveRange(-1e-5, 0.03 + 1e-5));
        expect(p.y, greaterThanOrEqualTo(-1e-5));
      }
    });

    test('drops falling into a test tube land in it, as many and as soon', () {
      // Sixteen millimetres across, half a millimetre of glass, a round
      // bottom: the glass a particle is held off by both its inside and its
      // outside.
      List<Vector2> inside() => [
        Vector2(0, 0.0005),
        for (var i = 1; i <= 8; i++)
          Vector2(
            0.0075 * math.sin(i / 8 * math.pi / 2),
            0.0005 + 0.0075 * (1 - math.cos(i / 8 * math.pi / 2)),
          ),
        Vector2(0.0075, 0.09),
      ];
      List<int> run(FluidSolver solver) {
        final body = LiquidBody(
          shape: RevolvedVessel(inside()),
          medium: FluidMedium.water,
          volume: 0.0,
          modes: 2,
          wallThickness: 0.0005,
        )..place(Matrix3.identity(), Vector3.zero());
        final fluid = ParticleFluid(
          medium: FluidMedium.water,
          spacing: 0.001,
          solver: solver,
        );
        final walls = <JetObstacle>[
          InsideWalls(body),
          OutsideWalls(body, thickness: 0.0005),
        ];
        final left = <int>[];
        for (var s = 0; s < 240; s++) {
          if (s < 60 && s % 3 == 0) {
            fluid.inject(4e-9, Vector3(0.002, 0.04, 0.001), Vector3(0, -1, 0));
          }
          fluid.step(
            1 / 240,
            gravity: Vector3(0, -9.81, 0),
            obstacles: walls,
            receivers: [body],
          );
          left.add(fluid.count);
        }
        expect(body.volume, closeTo(80e-9, 1e-15));
        return left;
      }

      // How many are still falling, step by step, within a particle or
      // two of the reference: they fall the same way and are caught at
      // the same surface. Mutation: the core's inside wall pushing out
      // through the glass rather than back in, and they fall through it.
      final core = run(_core);
      final reference = run(_reference);
      for (var s = 0; s < core.length; s++) {
        expect(core[s], closeTo(reference[s], 2), reason: 'step $s');
      }
    });

    test('a drop a metre up falls as the reference\'s does', () {
      // The core's single precision a metre from the origin keeps a tenth
      // of a micrometre: a velocity read off a substep's move of a fraction
      // of a millimetre would lose most of its digits there, so the
      // particles go to the core about their own middle. Mutation: hand
      // them over where they are, and in half a second the drop is six
      // millimetres off.
      Vector3 fall(FluidSolver solver) {
        final fluid = ParticleFluid(
          medium: FluidMedium.water,
          spacing: 0.002,
          solver: solver,
        )..inject(8e-9, Vector3(0.7, 1, -0.4), Vector3.zero());
        for (var i = 0; i < 500; i++) {
          fluid.step(1 / 1000, gravity: Vector3(0, -1.62, 0));
        }
        return fluid.positions.single;
      }

      expect((fall(_core) - fall(_reference)).length, lessThan(1e-5));
    });

    test('a wall the core cannot describe is stepped on the reference', () {
      // A caller's own obstacle is Dart the core cannot ask: that step is
      // the reference's, to the bit.
      ParticleFluid fall(FluidSolver solver) {
        final fluid = ParticleFluid(
          medium: FluidMedium.water,
          spacing: 0.002,
          solver: solver,
        )..inject(27 * 8e-9, Vector3(0, 0.01, 0), Vector3.zero());
        for (var i = 0; i < 40; i++) {
          fluid.step(
            1 / 240,
            gravity: Vector3(0, -9.81, 0),
            obstacles: [_Floor()],
          );
        }
        return fluid;
      }

      expect(fall(_core).positions, fall(_reference).positions);
    });
  });

  group('streams', () {
    test('a stream that meets the inside of a glass runs down it as the '
        'reference\'s does', () {
      const r = 0.02;
      ({List<Vector3> path, double landed}) run(FluidSolver solver) {
        final body = LiquidBody(
          shape: _tube(r, 0.2),
          medium: FluidMedium.water,
          volume: 1e-6,
          modes: 4,
        );
        final jet = Jet(medium: FluidMedium.water, solver: solver);
        for (var i = 0; i < 300; i++) {
          jet.emit(
            flow: 1e-5,
            dt: 1 / 1000,
            point: Vector3(-0.015, 0.19, 0),
            velocity: Vector3(0.6, 0, 0),
            width: 1e-3,
            across: Vector3(0, 0, 1),
          );
          jet.step(
            1 / 1000,
            gravity: Vector3(0, -9.81, 0),
            obstacles: [InsideWalls(body)],
            receivers: [body],
          );
        }
        return (
          path: [
            for (final run in jet.runs)
              for (final s in run) s.position,
          ],
          landed: jet.landed,
        );
      }

      // Parcel by parcel, within a tenth of a millimetre: it strikes the
      // wall at the same place and runs down it at the same speed.
      // Mutation: the core keeping the speed that went into the wall, and
      // it bounces across the glass.
      final core = run(_core);
      final reference = run(_reference);
      expect(_apart(core.path, reference.path), lessThan(1e-4));
      expect(core.landed, closeTo(reference.landed, reference.landed * 0.02));
    });

    test('poured slowly it clings to the outside as the reference\'s does', () {
      const r = 0.02, wall = 0.002;
      final source = LiquidBody(
        shape: _tube(r, 0.1),
        medium: FluidMedium.water,
        volume: 1e-6,
        modes: 2,
      );
      List<Vector3> run(FluidSolver solver) {
        final jet = Jet(
          medium: FluidMedium.water,
          breakupGrowth: 1e9,
          solver: solver,
        );
        for (var i = 0; i < 200; i++) {
          jet.emit(
            flow: 2e-7,
            dt: 1 / 1000,
            point: Vector3(r + wall + 0.0004, 0.1, 0),
            velocity: Vector3(0.03, 0, 0),
            width: 1e-3,
            across: Vector3(0, 0, 1),
          );
          jet.step(
            1 / 1000,
            gravity: Vector3(0, -9.81, 0),
            obstacles: [OutsideWalls(source, thickness: wall)],
          );
        }
        return [
          for (final run in jet.runs)
            for (final s in run) s.position,
        ];
      }

      // Mutation: the core letting go of a slow parcel the step it leaves
      // the wall, and the trickle falls away from the glass.
      expect(_apart(run(_core), run(_reference)), lessThan(1e-4));
    });
  });

  test('a knocked surface rings down as the reference\'s does', () {
    List<double> ring(FluidSolver solver) {
      final glass = LiquidBody(
        shape: _tube(0.008, 0.1),
        medium: FluidMedium.water,
        volume: math.pi * 0.008 * 0.008 * 0.05,
        modes: 8,
      );
      final g = Vector3(0, -9.81, 0);
      final reach = <double>[];
      for (var i = 0; i < 480; i++) {
        glass.place(Matrix3.identity(), Vector3.zero());
        if (i == 10) {
          glass.surface.knock(Vector3(0.004, glass.height, 0), 0.001);
        }
        glass.step(1 / 240, gravity: g, solver: solver);
        reach.add(glass.surface.reach);
      }
      return reach;
    }

    // Each mode is stepped exactly, so the two differ by single precision
    // only: within a thousandth of the first ring all the way down.
    // Mutation: the core's decay without the boundary layer's share, and
    // it rings on long after the reference's has died.
    final core = ring(_core);
    final reference = ring(_reference);
    final first = reference[11];
    expect(first, greaterThan(1e-5));
    for (var i = 0; i < core.length; i++) {
      expect(core[i], closeTo(reference[i], 1e-3 * first), reason: 'step $i');
    }
  });

  group('pipes', () {
    /// Two tubes of [medium] at 12 and 8 cm joined at their floors by a
    /// pipe of [bore], stepped for [seconds]: how far apart their levels
    /// are, step by step.
    List<double> levels(
      FluidSolver solver,
      FluidMedium medium,
      double radius,
      double bore,
      double seconds,
    ) {
      LiquidBody tube(double level) => LiquidBody(
        shape: _tube(radius, 0.5),
        medium: medium,
        volume: math.pi * radius * radius * level,
        modes: 2,
      );
      final world = FluidWorld(
        gravity: Vector3(0, -9.81, 0),
        step: 1 / 2000,
        solver: solver,
      );
      final a = tube(0.12), b = tube(0.08);
      world.bodies.addAll([a, b]);
      world.pipes.add(
        Pipe(
          from: a,
          at: Vector3(0, 0.0005, 0),
          to: b,
          toAt: Vector3(0, 0.0005, 0),
          radius: bore,
          length: 0.1,
          minorLoss: 0,
        ),
      );
      final out = <double>[];
      for (var i = 0; i < seconds * 2000; i++) {
        a.place(Matrix3.identity(), Vector3.zero());
        b.place(Matrix3.identity(), Vector3(0.2, 0, 0));
        world.advance(world.step);
        out.add(a.height - b.height);
      }
      return out;
    }

    test('a U-tube swings as the reference\'s does', () {
      // Within a fiftieth of a millimetre all the way, its swing four
      // centimetres: the same period, the same damping. Mutation: the
      // core's inertance without the liquid standing over each end, and it
      // swings at nearly twice the rate.
      final core = levels(_core, FluidMedium.water, 0.03, 0.03, 2);
      final reference = levels(_reference, FluidMedium.water, 0.03, 0.03, 2);
      for (var i = 0; i < core.length; i++) {
        expect(core[i], closeTo(reference[i], 2e-5), reason: 'step $i');
      }
    });

    test('a thick liquid creeps level as the reference\'s does', () {
      // Poiseuille's friction holds it: within a fiftieth of a millimetre
      // of the reference. Mutation: the core's friction without the bore's
      // fourth power, and it creeps at another rate.
      final core = levels(_core, FluidMedium.glycerol, 0.02, 0.002, 2);
      final reference = levels(
        _reference,
        FluidMedium.glycerol,
        0.02,
        0.002,
        2,
      );
      for (var i = 0; i < core.length; i++) {
        expect(core[i], closeTo(reference[i], 2e-5), reason: 'step $i');
      }
    });
  });

  test('a block, a ball and a capsule float as the reference\'s do', () {
    // Each let go above a vat of water and over glycerol, falling in,
    // bobbing and settling: a flat wooden block and a capsule, both thrown
    // in sideways so their drag is met along more than one axis, and a
    // steel ball sinking at Stokes's speed. The rigid bodies are the reference's on
    // both; only the push is the solver's.
    List<List<Vector3>> run(FluidSolver solver) {
      final gravity = Vector3(0, -9.81, 0);
      final collisions = CollisionWorld();
      final dynamics = Dynamics(world: collisions, gravity: gravity);
      final world = FluidWorld(gravity: gravity, step: 1 / 960, solver: solver);
      final water = LiquidBody(
        shape: _tube(0.2, 0.3),
        medium: FluidMedium.water,
        volume: math.pi * 0.04 * 0.1,
        modes: 2,
      );
      final glycerol = LiquidBody(
        shape: _tube(0.05, 0.4),
        medium: FluidMedium.glycerol,
        volume: math.pi * 0.0025 * 0.3,
        modes: 2,
      );
      world.bodies.addAll([water, glycerol]);
      final bodies = [
        RigidBody(
          world: collisions,
          shape: CollisionBox(Vector3(0.03, 0.012, 0.02)),
          position: Vector3(-0.08, 0.13, 0),
          mass: 600 * 8 * 0.03 * 0.012 * 0.02,
        ),
        RigidBody(
          world: collisions,
          shape: CollisionSphere(0.002),
          position: Vector3(1.0, 0.25, 0),
          mass: 7800 * 4 / 3 * math.pi * 0.002 * 0.002 * 0.002,
        ),
        RigidBody(
          world: collisions,
          shape: CollisionCapsule(radius: 0.01, halfHeight: 0.02),
          position: Vector3(0.08, 0.14, 0),
          mass: 0.01,
        ),
      ];
      bodies[0].velocity.setValues(0.4, 0, -0.3);
      bodies[2].velocity.setValues(-0.5, 0, 0.3);
      for (final body in bodies) {
        dynamics.add(body);
        world.float(body);
      }
      final path = <List<Vector3>>[];
      for (var i = 0; i < 960 * 2; i++) {
        water.place(Matrix3.identity(), Vector3.zero());
        glycerol.place(Matrix3.identity(), Vector3(1.0, 0, 0));
        world.advance(world.step);
        dynamics.step(world.step);
        path.add([for (final b in bodies) b.position.clone()]);
      }
      return path;
    }

    // Within a tenth of a millimetre all the way. Mutations in the core:
    // the block lifted by its whole volume rather than what is under, and
    // it floats high; no drag, and they all bob on; a box's frontal area
    // the same whichever way it moves, or a capsule's not foreshortened by
    // how steeply it is met, and that one drifts its own way.
    final core = run(_core);
    final reference = run(_reference);
    for (var i = 0; i < core.length; i++) {
      expect(_apart(core[i], reference[i]), lessThan(1e-4), reason: 'step $i');
    }
  });

  test('a whole pour fills the other tube as the reference\'s does, and '
      'loses nothing', () {
    final core = _pour(_core);
    final reference = _pour(_reference);
    // What reached the wide tube within half a per cent of the
    // reference's, and every drop accounted for on the core as exactly as
    // on the reference: the books are the same Dart on both.
    expect(core.target.volume, greaterThan(0.1 * core.total));
    expect(
      core.target.volume,
      closeTo(reference.target.volume, 0.005 * reference.total),
    );
    expect(core.world.volume, closeTo(core.total, core.total * 1e-9));
  });
}

/// A floor the core has no record for.
final class _Floor implements JetObstacle {
  @override
  bool reaches(Vector3 centre, double distance) => true;

  @override
  ({Vector3 normal, double depth})? touch(Vector3 point, double radius) {
    final d = point.y - radius;
    return d < 0.0 ? (normal: Vector3(0, 1, 0), depth: -d) : null;
  }
}
