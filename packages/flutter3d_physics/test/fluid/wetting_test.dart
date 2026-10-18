import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  /// Where a drop of [microlitres] against a vertical pane of [solid] is
  /// after a second, and where it started.
  (double, double) onPane(double microlitres, {SolidSurface? solid}) {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001);
    final pane = [
      PlaneObstacle(normal: Vector3(1, 0, 0), offset: 0.0, surface: solid),
    ];
    fluid.inject(microlitres * 1e-9, Vector3(0.002, 0.1, 0), Vector3.zero());
    // Let it come to the glass first.
    for (var i = 0; i < 24; i++) {
      fluid.step(1 / 240, gravity: Vector3(-9.81, 0, 0), obstacles: pane);
    }
    final start = fluid.drops.single.position.y;
    for (var i = 0; i < 240; i++) {
      fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), obstacles: pane);
    }
    return (start, fluid.drops.single.position.y);
  }

  test('a small drop hangs on a pane and a bigger one runs down it', () {
    // Furmidge: a microlitre weighs less than what clean glass's edge
    // holds it with; nine weigh more. Mutation: hold no drop by its edge,
    // and the small one slides down too.
    final (smallStart, smallEnd) = onPane(1);
    expect(smallEnd, closeTo(smallStart, 1e-6));
    final (bigStart, bigEnd) = onPane(9);
    expect(bigStart - bigEnd, greaterThan(0.01));
  });

  test('a phenolic bench holds a drop harder than glass, by the '
      'catalogue', () {
    // Its edge holds over 25° about 75°, where glass holds over 10° about
    // 20°: σ·w·(cos θr − cos θa) is several times glass's for the same
    // drop. Read from the catalogue's pairs, not written here.
    final glass = SolidSurface.glass;
    final bench = SolidSurface.benchTop;
    final water = FluidMedium.water;
    expect(bench.angleFor(water), greaterThan(glass.angleFor(water)));
    expect(
      bench.retention(water, 0.002),
      greaterThan(2 * glass.retention(water, 0.002)),
    );
    // A liquid with no pair keeps its own angle and the default hysteresis.
    expect(
      bench.angleFor(FluidMedium.glycerol),
      FluidMedium.glycerol.contactAngle,
    );
    expect(
      bench.hysteresisFor(FluidMedium.glycerol),
      SolidSurface.defaultHysteresis,
    );
    // The angle a caller gives a medium is its angle on glass.
    final steep = water.copyWith(contactAngle: 1.0);
    expect(glass.angleFor(steep), 1.0);
  });

  test('water beads on a phenolic bench and spreads on glass', () {
    Puddle lying(SolidSurface solid) {
      final bench = PuddleSurface(
        PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0, surface: solid),
      )..receive(JetLanding(volume: 5e-7, point: Vector3.zero()));
      return bench.puddles.single;
    }

    final glass = lying(SolidSurface.glass);
    final bench = lying(SolidSurface.benchTop);
    expect(bench.restRadius(9.81), lessThan(glass.restRadius(9.81)));
    expect(
      bench.capHeight(bench.restRadius(9.81)),
      greaterThan(glass.capHeight(glass.restRadius(9.81))),
    );
  });
}
