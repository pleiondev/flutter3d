import 'dart:math' as math;

import 'package:chemlab/chemlab.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the Bessel functions cross nought where the tables say', () {
    expect(besselJ0(2.4048), closeTo(0.0, 1e-4));
    expect(besselJ0(5.5201), closeTo(0.0, 1e-4));
    for (final xi in Slosh.ringZeros) {
      expect(besselJ1(xi), closeTo(0.0, 1e-4), reason: 'J1($xi)');
    }
  });

  test('rings from a tap move no liquid in or out', () {
    // Mutation: start the rings at a zero of J0 rather than of J1, and the
    // tapped surface holds more liquid than the still one.
    final slosh = Slosh(radius: 0.074, depth: 0.3)..tap(0.01);
    var volume = 0.0;
    var area = 0.0;
    const n = 400;
    for (var i = 0; i < n; i++) {
      final r = slosh.radius * (i + 0.5) / n;
      final ring = 2.0 * math.pi * r * slosh.radius / n;
      volume += slosh.at(r, 0.0).height * ring;
      area += ring;
    }
    // Under a hundredth of a millimetre over the surface, against a
    // centimetre at its middle.
    expect((volume / area).abs(), lessThan(1e-5));
    expect(slosh.at(0, 0).height.abs(), greaterThan(0.005));
  });

  test('a sudden tilt leaves the liquid behind, then it rocks', () {
    final slosh = Slosh(radius: 0.074, depth: 0.3)..targetX = 0.2;
    // The instant after, the surface is where it was: flat. The plane it
    // settles to is matched by the three modes' shares to within what three
    // terms of the series hold, a few millimetres at the wall.
    expect(slosh.at(0.03, 0).height.abs(), lessThan(0.002));
    final crossings = <double>[];
    var before = slosh.offX[0];
    const dt = 1 / 2000;
    for (var i = 1; i < 4000; i++) {
      slosh.step(dt);
      final now = slosh.offX[0];
      if (before.sign != now.sign) crossings.add(i * dt);
      before = now;
    }
    // Mutation: ring the sloshing at a ring mode's frequency.
    final period = crossings[4] - crossings[2];
    expect(period, closeTo(2.0 * math.pi / slosh.frequency(1.8412), 0.01));
    // The finer tilting modes ring faster and are gone sooner.
    expect(slosh.offX[2].abs(), lessThan(slosh.offX[0].abs()));
  });

  test('settled, a tilted surface is the plane, without ripples', () {
    // Mutation: keep the modes' sum for the rest shape instead of the
    // plane, and a three-term series puts bumps on a still surface.
    final slosh = Slosh(radius: 0.074, depth: 0.3)
      ..targetZ = 0.4
      ..settle();
    for (final z in <double>[-0.07, -0.03, 0.0, 0.02, 0.06]) {
      expect(slosh.at(0.01, z).height, closeTo(0.4 * z, 1e-9));
    }
  });

  test('a leaning tube keeps its liquid level and lets it settle', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final tube = bench.vessels[1];
    bench.lean(tube, 0.4);
    expect(bench.step(1 / 60), isTrue);
    var seconds = 0.0;
    while (bench.step(1 / 60)) {
      seconds += 1 / 60;
      expect(seconds, lessThan(20), reason: 'still moving');
    }
    // Two points of the surface either side of the axis, along the way it
    // leans, are at one height in the world. Mutation: take the slope with
    // the other sign, and they are two and a half centimetres apart.
    Vector3 world(double z) {
      final y = tube.level + tube.slosh.at(0, z).height;
      return tube.body.worldMatrix.transformed3(Vector3(0, y, z));
    }

    expect(world(0.05).y, closeTo(world(-0.05).y, 1e-4));
    // And the glass still stands on the bench.
    expect(tube.body.readPosition().y, greaterThan(0.0));
  });
}
