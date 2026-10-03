import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

RevolvedVessel _vat(double r, double h) =>
    RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, h)]);

void main() {
  final up = Vector3(0, 1, 0);

  test('what is under the surface, shape by shape', () {
    const r = 0.1;
    final ball = CollisionSphere(r);
    final full = 4 / 3 * math.pi * r * r * r;
    expect(
      submergedVolume(ball, Vector3.zero(), up, 0),
      closeTo(full / 2, 1e-12),
    );
    expect(submergedVolume(ball, Vector3.zero(), up, 1), closeTo(full, 1e-12));
    expect(submergedVolume(ball, Vector3.zero(), up, -1), 0.0);
    final box = CollisionBox(Vector3(0.1, 0.2, 0.3));
    final tilted = Vector3(0.3, 1, 0.1)..normalize();
    expect(
      submergedVolume(
        box,
        Vector3(1, 2, 3),
        tilted,
        tilted.dot(Vector3(1, 2, 3)),
      ),
      closeTo(0.024, 1e-6),
    );
    final capsule = CollisionCapsule(radius: 0.05, halfHeight: 0.1);
    final whole = math.pi * 0.05 * 0.05 * (0.2 + 4 / 3 * 0.05);
    expect(
      submergedVolume(capsule, Vector3.zero(), up, 1),
      closeTo(whole, whole * 0.01),
    );
    expect(
      submergedVolume(capsule, Vector3.zero(), up, 0),
      closeTo(whole / 2, whole * 0.01),
    );
  });

  test('a wooden block floats six tenths under', () {
    final gravity = Vector3(0, -9.81, 0);
    final collisions = CollisionWorld();
    final dynamics = Dynamics(world: collisions, gravity: gravity);
    const half = 0.02;
    final block = RigidBody(
      world: collisions,
      shape: CollisionBox(Vector3.all(half)),
      position: Vector3(0, 0.13, 0),
      mass: 600 * 8 * half * half * half,
    );
    dynamics.add(block);
    final world = FluidWorld(gravity: gravity);
    final vat = LiquidBody(
      shape: _vat(0.2, 0.3),
      medium: FluidMedium.water,
      volume: math.pi * 0.04 * 0.1,
      modes: 2,
    );
    world.bodies.add(vat);
    world.float(block);
    var under = 0.0;
    var samples = 0;
    for (var i = 0; i < 240 * 6; i++) {
      vat.place(Matrix3.identity(), Vector3.zero());
      world.advance(world.step);
      dynamics.step(world.step);
      // Over the last second, as it bobs about its level.
      if (i >= 240 * 5) {
        under += FloatingBody(block).submergedIn(vat);
        samples++;
      }
    }
    // Archimedes: it sinks until the water it displaces weighs what it
    // does, 600 / 998 of it. Mutation: buoy it by its whole volume, and it
    // floats on top.
    final whole = 8 * half * half * half;
    expect(under / samples / whole, closeTo(600 / 998.2, 0.02));
  });

  test('a small steel ball settles through glycerol at Stokes\'s speed', () {
    final gravity = Vector3(0, -9.81, 0);
    final collisions = CollisionWorld();
    final dynamics = Dynamics(world: collisions, gravity: gravity);
    const r = 0.001;
    final ball = RigidBody(
      world: collisions,
      shape: CollisionSphere(r),
      position: Vector3(0, 0.25, 0),
      mass: 7800 * 4 / 3 * math.pi * r * r * r,
    );
    dynamics.add(ball);
    final world = FluidWorld(gravity: gravity, step: 1 / 2000);
    final vat = LiquidBody(
      shape: _vat(0.05, 0.4),
      medium: FluidMedium.glycerol,
      volume: math.pi * 0.0025 * 0.3,
      modes: 2,
    );
    world.bodies.add(vat);
    world.float(ball);
    for (var i = 0; i < 2000; i++) {
      vat.place(Matrix3.identity(), Vector3.zero());
      world.advance(world.step);
      dynamics.step(world.step);
    }
    final stokes = stokesSpeed(FluidMedium.glycerol, r, 7800, 9.81);
    expect(-ball.velocity.y, closeTo(stokes, stokes * 0.03));
  });

  test('a ball spun in glycerol slows as Stokes\'s torque says', () {
    // 8πμR³ω against a ball's 2/5·mR²: its spin falls by e in ρR²/15μ, six
    // milliseconds for a centimetre ball as heavy as the glycerol. Slow
    // enough, a tenth of a Reynolds number, for Stokes to hold. Mutation:
    // leave the torque out, and it spins on as it was.
    final gravity = Vector3(0, -9.81, 0);
    final collisions = CollisionWorld();
    final dynamics = Dynamics(world: collisions, gravity: gravity);
    const r = 0.01;
    final rho = FluidMedium.glycerol.density;
    final ball = RigidBody(
      world: collisions,
      shape: CollisionSphere(r),
      position: Vector3(0, 0.1, 0),
      mass: rho * 4 / 3 * math.pi * r * r * r,
      canRotate: true,
    );
    ball.angularVelocity.setValues(0, 1, 0);
    dynamics.add(ball);
    const dt = 1 / 20000;
    final world = FluidWorld(gravity: gravity, step: dt);
    final vat = LiquidBody(
      shape: _vat(0.05, 0.4),
      medium: FluidMedium.glycerol,
      volume: math.pi * 0.0025 * 0.3,
      modes: 2,
    );
    world.bodies.add(vat);
    world.float(ball);
    final tau = rho * r * r / (15 * FluidMedium.glycerol.viscosity);
    final steps = (tau / dt).round();
    for (var i = 0; i < steps; i++) {
      vat.place(Matrix3.identity(), Vector3.zero());
      world.advance(dt);
      dynamics.step(dt);
    }
    expect(ball.angularVelocity.y, closeTo(math.exp(-1), math.exp(-1) * 0.02));
  });

  test('a body under the surface raises the level by its volume', () {
    final collisions = CollisionWorld();
    final world = FluidWorld(gravity: Vector3(0, -9.81, 0));
    final vat = LiquidBody(
      shape: _vat(0.1, 0.3),
      medium: FluidMedium.water,
      volume: math.pi * 0.01 * 0.1,
      modes: 2,
    );
    world.bodies.add(vat);
    final before = vat.height;
    // Held still: no mass to move.
    world.float(
      RigidBody(
        world: collisions,
        shape: CollisionSphere(0.03),
        position: Vector3(0, 0.05, 0),
        mass: 0,
      ),
    );
    vat.place(Matrix3.identity(), Vector3.zero());
    world.advance(world.step);
    final rise = 4 / 3 * math.pi * 0.027e-3 / (math.pi * 0.01);
    expect(vat.height - before, closeTo(rise, rise * 0.01));
  });

  test('a still glass weighs what its liquid weighs; a pour pushes back', () {
    final gravity = Vector3(0, -9.81, 0);
    final glass = LiquidBody(
      shape: _vat(0.02, 0.1),
      medium: FluidMedium.water,
      volume: math.pi * 4e-4 * 0.095,
      modes: 2,
    );
    glass
      ..place(Matrix3.identity(), Vector3.zero())
      ..step(1e-3, gravity: gravity);
    final weight = 998.2 * glass.volume * 9.81;
    expect(glass.load(gravity).y, closeTo(-weight, weight * 1e-6));
    // Tipped, it pours, and the stream leaving pushes the glass the other
    // way: −ρQv.
    Spill? spill;
    for (var i = 0; i < 400 && (spill == null || spill.flow == 0); i++) {
      glass.place(Matrix3.rotationX(0.6), Vector3.zero());
      spill = glass.step(1e-3, gravity: gravity);
    }
    expect(spill!.flow, greaterThan(0));
    final sideways = glass.load(gravity)..y = 0;
    final thrust = spill.velocity..y = 0;
    expect(sideways.dot(thrust), lessThan(0));
  });
}
