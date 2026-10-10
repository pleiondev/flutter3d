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
final class _Counting extends FluidSolver {
  int particles = 0;
  int parcels = 0;
  int modes = 0;
  int pipes = 0;
  int pushes = 0;

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

  @override
  void flowPipes(PipeFlow flow) {
    pipes++;
    const DartFluid().flowPipes(flow);
  }

  @override
  void pushBodies(FloatPush push) {
    pushes++;
    const DartFluid().pushBodies(push);
  }
}

/// A backend with a fluid of its own.
final class _Backend extends PhysicsBackend {
  @override
  final _Counting fluid = _Counting();

  @override
  String get name => 'counting';
}

RevolvedVessel _tube(double r, double h) =>
    RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, h)]);

/// A narrow tube tipped over a wide one, pouring: streams, splashes and
/// waves, on [world]; and beside them a vat with a ball floating in it and
/// a pipe from its floor into the wide tube's.
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
  final vat = LiquidBody(
    shape: _tube(0.05, 0.1),
    medium: FluidMedium.water,
    volume: math.pi * 0.05 * 0.05 * 0.05,
    modes: 4,
  );
  world.bodies.addAll([source, target, vat]);
  world.pipes.add(
    Pipe(
      from: vat,
      at: Vector3(0, 0.002, 0),
      to: target,
      toAt: Vector3(0, 0.002, 0),
      radius: 0.001,
      length: 0.3,
    ),
  );
  world.float(
    RigidBody(
      world: CollisionWorld(),
      shape: CollisionSphere(0.01),
      position: Vector3(0.3, 0.04, 0),
      mass: 0.002,
    ),
  );
  for (var i = 0; i < 240; i++) {
    source.place(Matrix3.rotationX(1.3), Vector3(0, 0.1, -0.1045));
    target.place(Matrix3.identity(), Vector3.zero());
    vat.place(Matrix3.identity(), Vector3(0.3, 0, 0));
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
    // Through the base type, as code that holds only a PhysicsBackend
    // asks. Mutation: the base always answering the reference.
    final PhysicsBackend current = backend;
    expect(current.fluid, same(backend.fluid));
  });

  test('a world is made on its backend, and steps everything on it', () {
    final backend = _Backend();
    {
      final world = FluidWorld(gravity: Vector3(0, -9.81, 0), backend: backend);
      expect(world.solver, same(backend.fluid));
      _pour(world);
      // Mutations: a stream made with no solver, particles made with
      // none, a body, a pipe or a float stepped with none, and that count
      // stays at nought.
      expect(backend.fluid.parcels, greaterThan(0));
      expect(backend.fluid.particles, greaterThan(0));
      expect(backend.fluid.modes, greaterThan(0));
      expect(backend.fluid.pipes, greaterThan(0));
      expect(backend.fluid.pushes, greaterThan(0));
    }
  });
}
