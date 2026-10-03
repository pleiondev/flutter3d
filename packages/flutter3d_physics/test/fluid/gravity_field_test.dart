import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the Earth pulls 9.82 at its surface and half that halfway down', () {
    // μ = 3.986×10¹⁴ m³/s², R = 6371 km.
    const r = 6.371e6;
    final earth = GravityField(
      attractors: [
        Attractor(position: Vector3.zero(), mu: 3.986e14, radius: r),
      ],
    );
    final surface = earth.at(Vector3(0, r, 0));
    expect(surface.length, closeTo(9.82, 0.01));
    expect(surface.y, lessThan(0.0));
    // Inside a uniform ball the pull falls straight to nought at the middle.
    expect(earth.at(Vector3(0, r / 2, 0)).length, closeTo(9.82 / 2, 0.01));
    // Between two equal masses, none at all.
    final pair = GravityField(
      attractors: [
        Attractor(position: Vector3(-1, 0, 0), mu: 10),
        Attractor(position: Vector3(1, 0, 0), mu: 10),
      ],
    );
    expect(pair.at(Vector3.zero()).length, closeTo(0.0, 1e-12));
  });

  test('a glass beside an attractor levels across its own gravity', () {
    // A pull of 9.81 at a metre, sideways to the glass, and no other:
    // the liquid lies along the glass's side, its surface facing the
    // attractor's way out. Mutation: hand every vessel the world's one
    // gravity, which here is nought, and the surface never turns.
    final field = GravityField(
      attractors: [Attractor(position: Vector3.zero(), mu: 9.81)],
    );
    final world = FluidWorld(gravity: Vector3.zero(), field: field);
    final glass = LiquidBody(
      shape: RevolvedVessel([
        Vector2(0, 0),
        Vector2(0.02, 0),
        Vector2(0.02, 0.1),
      ]),
      medium: FluidMedium.water,
      volume: 2e-5,
      modes: 2,
    );
    world.bodies.add(glass);
    for (var i = 0; i < 240; i++) {
      glass.place(
        Matrix3.identity(),
        Vector3(1, 0, 0),
        time: world.time + world.step,
      );
      world.advance(world.step);
    }
    expect(glass.up.x, closeTo(1.0, 1e-6));
  });

  test('a drop between two attractors falls to the nearer', () {
    final field = GravityField(
      attractors: [
        Attractor(position: Vector3(-0.1, 0, 0), mu: 1e-3),
        Attractor(position: Vector3(0.1, 0, 0), mu: 1e-3),
      ],
    );
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
      ..inject(1e-9, Vector3(0.01, 0, 0), Vector3.zero());
    for (var i = 0; i < 24; i++) {
      fluid.step(1 / 240, gravity: Vector3.zero(), gravityAt: field.at);
    }
    expect(fluid.positions.single.x, greaterThan(0.01));
  });
}
