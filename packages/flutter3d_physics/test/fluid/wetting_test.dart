import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  /// Where a drop of [microlitres] left against a vertical pane of glass is
  /// after a second, and where it started.
  (double, double) onPane(int microlitres) {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001);
    final pane = [PlaneObstacle(normal: Vector3(1, 0, 0), offset: 0.0)];
    fluid.inject(microlitres * 1e-9, Vector3(0.002, 0.1, 0), Vector3.zero());
    double low() =>
        fluid.positions.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    // Let it come to the glass first.
    for (var i = 0; i < 24; i++) {
      fluid.step(1 / 240, gravity: Vector3(-9.81, 0, 0), obstacles: pane);
    }
    final start = low();
    for (var i = 0; i < 240; i++) {
      fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), obstacles: pane);
    }
    return (start, low());
  }

  test('a small drop hangs on a pane and a big one runs down it', () {
    // Furmidge: a microlitre weighs three quarters of what clean glass's
    // edge holds it with; twenty weigh five times what holds them.
    // Mutation: hold every drop under the capillary length, as before,
    // and the big one, under it at its four-millimetre base, stays.
    final (smallStart, smallEnd) = onPane(1);
    expect(smallEnd, closeTo(smallStart, 1e-3));
    final (bigStart, bigEnd) = onPane(20);
    expect(bigStart - bigEnd, greaterThan(0.01));
  });

  test('water beads on a lacquered bench and spreads on glass', () {
    Puddle lying(SolidSurface solid) {
      final bench =
          PuddleSurface(
            PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0, solid: solid),
          )..receive(
            5e-7,
            Vector3.zero(),
            Vector3.zero(),
            FluidMedium.water,
            const {},
          );
      return bench.puddles.single;
    }

    final glass = lying(SolidSurface.glass);
    final laminate = lying(SolidSurface.laminate);
    expect(laminate.restRadius(9.81), lessThan(glass.restRadius(9.81)));
    final r = laminate.restRadius(9.81);
    expect(
      laminate.capHeight(r),
      greaterThan(glass.capHeight(glass.restRadius(9.81))),
    );
  });
}
