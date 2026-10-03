import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final g = Vector3(0, -9.81, 0);

  test('a drop under the capillary length is one body, falling as one', () {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
      ..inject(4e-9, Vector3(0, 1, 0), Vector3.zero());
    expect(fluid.count, 1);
    expect(fluid.dropCount, 1);
    for (var i = 0; i < 240; i++) {
      fluid.step(1 / 240, gravity: g);
    }
    // A second's fall, as a body falls: ½gt², to the step's first order.
    expect(1 - fluid.positions.single.y, closeTo(4.905, 0.03));
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
    // Apart at first; they meet within the second step.
    fluid
      ..step(1 / 240, gravity: Vector3.zero())
      ..step(1 / 240, gravity: Vector3.zero());
    expect(fluid.dropCount, 1);
    expect(fluid.volume, closeTo(3e-9, 1e-21));
    // A third of it was dye at one.
    expect(fluid.concentrations['dye'], closeTo(1 / 3, 1e-12));
  });

  test('a block of liquid in the air is one drop, and holds together', () {
    // Twenty-seven particles laid out as a block, free in the air, rang
    // until they flew apart, ten centimetres in a tenth of a second. A
    // drop in flight is held whole by surface tension against the air
    // (its Weber number far under twelve): one body. Mutation: leave free
    // blocks as particles, and they fly apart.
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001)
      ..inject(27e-9, Vector3(0, 1, 0), Vector3.zero());
    for (var i = 0; i < 24; i++) {
      fluid.step(1 / 240, gravity: Vector3.zero());
    }
    expect(fluid.dropCount, 1);
    expect(fluid.count, 1);
    expect(fluid.positions.single.y, closeTo(1.0, 1e-6));
    expect(fluid.volume, closeTo(27e-9, 1e-21));
  });

  test('a drop that lands on glass is particles there', () {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001);
    final pane = [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0)];
    // A block resting on the glass from the start: particles, held there.
    fluid.inject(27e-9, Vector3(0, 0.0015, 0), Vector3.zero());
    fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), obstacles: pane);
    expect(fluid.dropCount, 0);
    expect(fluid.count, 27);
  });
}
