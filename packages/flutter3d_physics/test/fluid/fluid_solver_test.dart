/// Fluid from the run's backend: the reference is each piece's own solve,
/// a backend with a fluid of its own is asked for it, and a `FluidWorld`
/// hands its solver to everything it steps — the waves, the streams and
/// the spilt particles.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A solver that counts what it is asked to step and steps it on the
/// reference.
final class _Counting implements FluidSolver {
  int particles = 0;
  int parcels = 0;
  int modes = 0;

  @override
  void moveParticles(ParticleMotion motion) {
    particles++;
    const DartFluid().moveParticles(motion);
  }

  @override
  void flyParcels(ParcelFlight flight) {
    parcels++;
    const DartFluid().flyParcels(flight);
  }

  @override
  void ringModes(ModeRinging ringing) {
    modes++;
    const DartFluid().ringModes(ringing);
  }
}

/// A backend with a fluid of its own.
final class _Backend implements PhysicsBackend, FluidPhysics {
  @override
  final _Counting fluid = _Counting();

  @override
  String get name => 'counting';

  @override
  RigidDynamics dynamics(CollisionWorld world, {Vector3? gravity}) =>
      const DartPhysics().dynamics(world, gravity: gravity);

  @override
  void attach(CollisionWorld world) {}

  @override
  void release(CollisionWorld world) {}
}

RevolvedVessel _tube(double r, double h) =>
    RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, h)]);

/// A narrow tube tipped over a wide one, pouring: streams, splashes and
/// waves, on [world].
({LiquidBody source, LiquidBody target}) _pour(FluidWorld world) {
  final source = LiquidBody(
    shape: _tube(0.008, 0.1),
    medium: FluidMedium.water,
    volume: math.pi * 0.008 * 0.008 * 0.07,
    modes: 4,
    wallThickness: 0.0008,
  );
  final target = LiquidBody(
    shape: _tube(0.012, 0.1),
    medium: FluidMedium.water,
    volume: 0.0,
    modes: 4,
    wallThickness: 0.0008,
  );
  world.bodies.addAll([source, target]);
  for (var i = 0; i < 240; i++) {
    source.place(Matrix3.rotationX(1.3), Vector3(0, 0.1, -0.1045));
    target.place(Matrix3.identity(), Vector3.zero());
    world.advance(world.step);
  }
  return (source: source, target: target);
}

void main() {
  test('a backend with no fluid of its own is on the reference', () {
    expect(const DartPhysics().fluid, isA<DartFluid>());
  });

  test('a backend with a fluid of its own is asked for it', () {
    final backend = _Backend();
    // Through the extension, as code that holds only a PhysicsBackend
    // asks. Mutation: the extension always answering the reference.
    final PhysicsBackend current = backend;
    expect(current.fluid, same(backend.fluid));
  });

  test('a world is made on the run\'s backend, and steps everything on it', () {
    final before = PhysicsBackend.current;
    final backend = _Backend();
    PhysicsBackend.current = backend;
    try {
      final world = FluidWorld(gravity: Vector3(0, -9.81, 0));
      expect(world.solver, same(backend.fluid));
      _pour(world);
      // Mutations: a stream made with no solver, particles made with
      // none, or a body stepped with none, and that count stays at nought.
      expect(backend.fluid.parcels, greaterThan(0));
      expect(backend.fluid.particles, greaterThan(0));
      expect(backend.fluid.modes, greaterThan(0));
    } finally {
      PhysicsBackend.current = before;
    }
  });
}
