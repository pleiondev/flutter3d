import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the Earth pulls 9.82 at its surface and half that halfway down', () {
    // μ = 3.986×10¹⁴ m³/s², R = 6371 km.
    const r = 6.371e6;
    final earth = AttractorGravity(
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
    final pair = AttractorGravity(
      attractors: [
        Attractor(position: Vector3(-1, 0, 0), mu: 10),
        Attractor(position: Vector3(1, 0, 0), mu: 10),
      ],
    );
    expect(pair.at(Vector3.zero()).length, closeTo(0.0, 1e-12));
  });

  test('attractors written as a field read back off it', () {
    // The field contract's grid of f3d.gravity, three values a cell: what
    // a renderer or another solver reads too. At a cell's middle it is the
    // law's to f32; between cells, the blend of the eight about it.
    // Mutation: swap two components on the way, and y comes back as x.
    final law = AttractorGravity(
      uniform: Vector3(0, -9.81, 0),
      attractors: [Attractor(position: Vector3(10, 0, 0), mu: 100)],
    );
    const declaration = FieldDeclaration(
      id: 'test.gravity',
      quantity: GravityField.quantity,
      unit: Unit.meterPerSecondSquared,
      grid: FieldGrid(4, 4, 4, components: 3),
      transform: FieldTransform(cellSize: 0.5),
      writer: FieldAccess.simulation('test.attractors'),
      readers: [FieldAccess.simulation('f3d.fluid')],
    );
    expect(declaration.problem, isNull);
    final sampled = SampledGravity(law.writeField(declaration));
    final at = Vector3(0.5, 1.0, 1.5);
    final read = sampled.at(at);
    final truth = law.at(at);
    for (var k = 0; k < 3; k++) {
      expect(read[k], closeTo(truth[k], 1e-5));
    }
    // A field of another quantity is not a gravity.
    expect(
      () => SampledGravity(
        HostField(
          const FieldDeclaration(
            id: 'test.heat',
            quantity: 'f3d.temperature',
            unit: Unit.kelvin,
            grid: FieldGrid(1, 1, 1),
            writer: FieldAccess.simulation('test.heat'),
          ),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('a glass beside an attractor levels across its own gravity', () {
    // A pull of 9.81 at a metre, sideways to the glass, and no other: the
    // liquid lies along the glass's side, its surface facing the
    // attractor's way out. Mutation: hand every vessel the world's one
    // gravity, which here is nought, and the surface never turns.
    final field = AttractorGravity(
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
        timeSeconds: world.timeSeconds + world.step,
      );
      world.advance(world.step);
    }
    expect(glass.up.x, closeTo(1.0, 1e-6));
  });
}
