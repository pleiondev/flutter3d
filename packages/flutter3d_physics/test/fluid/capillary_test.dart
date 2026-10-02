import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';

void main() {
  const g = 9.81;
  final water = FluidMedium.water;

  test('in a narrow tube the meniscus lifts liquid by Jurin\'s height', () {
    final m = TubeMeniscus(medium: water, radius: 2e-4, g: g);
    expect(
      m.rise,
      closeTo(jurinHeight(water, 2e-4, g), jurinHeight(water, 2e-4, g) * 0.01),
    );
    // And it is the spherical cap of radius R / cos θ.
    final theta = water.contactAngle;
    final cap = 2e-4 / math.cos(theta) * (1 - math.sin(theta));
    expect(m.wallRise, closeTo(cap, cap * 0.02));
  });

  test('in a wide tube it is flat in the middle and climbs the wall', () {
    // Twenty capillary lengths across: the wall's curve round the tube is
    // too gentle to matter, which at seven it still does, by six per cent.
    final m = TubeMeniscus(medium: water, radius: 0.05, g: g);
    // Far less than Jurin's narrow-tube height, whose middle is not flat.
    expect(m.rise, lessThan(0.2 * jurinHeight(water, 0.05, g)));
    // At the wall, as high as a flat wall's: l·√(2(1 − sin θ)).
    final l = water.capillaryLength(g);
    final h0 = l * math.sqrt(2 * (1 - math.sin(water.contactAngle)));
    expect(m.wallRise, closeTo(h0, h0 * 0.06));
    expect(m.heightAt(0.0), 0.0);
    expect(m.heightAt(0.035), lessThan(0.05 * m.wallRise));
  });

  test('mercury does not wet glass: it sinks, its meniscus bulges', () {
    final mercury = FluidMedium.mercury;
    final m = TubeMeniscus(medium: mercury, radius: 5e-4, g: g);
    expect(m.rise, lessThan(0));
    expect(m.wallRise, lessThan(0));
    expect(
      m.rise,
      closeTo(
        jurinHeight(mercury, 5e-4, g),
        jurinHeight(mercury, 5e-4, g).abs() * 0.15,
      ),
    );
  });

  test(
    "a flat wall's meniscus climbs it and dies off within capillary lengths",
    () {
      final l = water.capillaryLength(g);
      final h0 = l * math.sqrt(2 * (1 - math.sin(water.contactAngle)));
      expect(wallMeniscus(water, 0, g), closeTo(h0, h0 * 1e-6));
      expect(wallMeniscus(water, 5 * l, g), lessThan(0.01 * h0));
      // On the Moon the same water climbs six times as far out: l ∝ 1/√g.
      expect(
        water.capillaryLength(1.62) / l,
        closeTo(math.sqrt(g / 1.62), 1e-9),
      );
    },
  );
}
