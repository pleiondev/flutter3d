import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';

void main() {
  test("an opening passes Torricelli's speed, in the world's gravity", () {
    final earth = orificeFlow(area: 1e-4, head: 0.2, g: 9.81);
    expect(earth.speed, closeTo(math.sqrt(2 * 9.81 * 0.2), 1e-12));
    expect(earth.flow, closeTo(0.62 * 1e-4 * earth.speed, 1e-15));
    // On the Moon the same head passes 0.40 as much: √(1.62 / 9.81).
    final moon = orificeFlow(area: 1e-4, head: 0.2, g: 1.62);
    expect(moon.flow / earth.flow, closeTo(math.sqrt(1.62 / 9.81), 1e-12));
    expect(orificeFlow(area: 1e-4, head: -1, g: 9.81).flow, 0.0);
  });

  test('a weir passes the flow its head gives, and back', () {
    final over = overCircularLip(flow: 2e-6, radius: 0.008, tilt: 1.6, g: 9.81);
    final again = circularWeir(
      head: over.head,
      radius: 0.008,
      tilt: 1.6,
      g: 9.81,
    );
    expect(again.flow, closeTo(2e-6, 2e-6 * 1e-6));
    // Critical flow at the crest: a speed of about √(g · 2h/3).
    expect(over.speed, closeTo(math.sqrt(9.81 * over.head * 2 / 3), 0.05));
    expect(circularWeir(head: 0, radius: 0.008, tilt: 1.6, g: 9.81).flow, 0);
  });

  test('a long thin pipe is held back by viscosity, as Poiseuille says', () {
    const r = 0.5e-3, length = 1.0, head = 0.1;
    final q = pipeFlow(
      length: length,
      radius: r,
      head: head,
      medium: FluidMedium.water,
      g: 9.81,
    );
    final poiseuille =
        math.pi *
        math.pow(r, 4) *
        FluidMedium.water.density *
        9.81 *
        head /
        (8 * FluidMedium.water.viscosity * length);
    expect(q, closeTo(poiseuille, poiseuille * 1e-12));
    // Glycerol, fourteen hundred times as viscous, is that much slower.
    final thick = pipeFlow(
      length: length,
      radius: r,
      head: head,
      medium: FluidMedium.glycerol,
      g: 9.81,
    );
    expect(q / thick, greaterThan(1000));
    expect(
      pipeFlow(
        length: length,
        radius: r,
        head: -head,
        medium: FluidMedium.water,
        g: 9.81,
      ),
      closeTo(-q, 1e-18),
    );
  });

  test("water's capillary length is about 2.7 millimetres", () {
    expect(FluidMedium.water.capillaryLength(9.81), closeTo(2.73e-3, 0.02e-3));
  });
}
