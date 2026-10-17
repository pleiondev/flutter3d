import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final g = Vector3(0, -9.81, 0);

  test('a drop under the capillary length is one body, falling as one', () {
    // Mutation: lay it out as particles, and there are four of them.
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
      ..inject(4e-9, Vector3(0, 1, 0), Vector3.zero());
    expect(fluid.count, 0);
    expect(fluid.drops, hasLength(1));
    for (var i = 0; i < 240; i++) {
      fluid.step(1 / 240, gravity: g);
    }
    // A second's fall, as a body falls: ½gt², to the step's first order.
    expect(1 - fluid.drops.single.position.y, closeTo(4.905, 0.03));
    expect(fluid.volume, 4e-9);
  });

  test('two drops that meet run together, liquid and momentum and all', () {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
      ..inject(
        1e-9,
        Vector3(0, 0, 0),
        Vector3(0.1, 0, 0),
        concentrations: const {'dye': 1.0},
      )
      ..inject(2e-9, Vector3(0.002, 0, 0), Vector3(-0.1, 0, 0));
    fluid
      ..step(1 / 240, gravity: Vector3.zero())
      ..step(1 / 240, gravity: Vector3.zero());
    final drop = fluid.drops.single;
    expect(drop.volume, closeTo(3e-9, 1e-21));
    // A third of it was dye at one, and the momenta cancel but for a third.
    expect(drop.concentrations['dye'], closeTo(1 / 3, 1e-12));
    expect(drop.velocity.x, closeTo((0.1 - 0.2) / 3, 1e-7));
  });

  test('a free block of particles gathers into one drop', () {
    // Eight particles laid out as a block, free in the air: under the
    // capillary length, a drop in flight is held whole by surface tension
    // against the air. Mutation: leave free blocks as particles, and they
    // ring until they fly apart.
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
      ..inject(8e-9, Vector3(0, 1, 0), Vector3.zero(), asParticles: true);
    expect(fluid.count, 8);
    fluid.step(1 / 240, gravity: Vector3.zero());
    expect(fluid.count, 0);
    expect(fluid.drops.single.volume, closeTo(8e-9, 1e-21));
    expect(fluid.drops.single.position.y, closeTo(1.0, 1e-3));
  });

  test('a drop wider than the capillary length spreads where it lands', () {
    // Twenty microlitres, 3.4 mm across against water's 2.7: its weight
    // flattens it on the glass, and it is particles there.
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
      ..inject(20e-9, Vector3(0, 0.0018, 0), Vector3.zero(), asParticles: true);
    final pane = [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0)];
    fluid.step(1 / 240, gravity: g, obstacles: pane);
    expect(fluid.drops, isEmpty);
    expect(fluid.count, 20);
  });

  test('a drop flies by the gravity where it is', () {
    // An attractor beside it, and no gravity of the world's: it falls
    // towards the attractor. Mutation: fly it by the world's one vector,
    // and it hangs where it was let go.
    final field = AttractorGravity(
      attractors: [Attractor(position: Vector3(1, 0, 0), mu: 9.81)],
    );
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
      ..inject(1e-9, Vector3.zero(), Vector3.zero());
    for (var i = 0; i < 24; i++) {
      fluid.step(1 / 240, gravity: Vector3.zero(), gravityAt: field.at);
    }
    // A tenth of a second at about 9.81 m/s², a little more as it nears.
    expect(fluid.drops.single.velocity.x, inInclusiveRange(0.981, 1.1));
  });
}
