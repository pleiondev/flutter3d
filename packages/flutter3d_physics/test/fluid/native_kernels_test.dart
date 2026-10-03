import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics/src/fluid/native/pbf_backend.dart'
    show nativePbfLanes, setNativePbfLanes;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A loose cloud of [n] particles about a millimetre apart, the same every
/// run, and its neighbours within [h] as compressed rows.
(Float64List, Int32List, Int32List) _cloud(int n, double h) {
  final random = math.Random(7);
  final x = Float64List(3 * n);
  for (var i = 0; i < 3 * n; i++) {
    x[i] = random.nextDouble() * 0.006;
  }
  final rows = <List<int>>[
    for (var i = 0; i < n; i++)
      [
        for (var j = 0; j < n; j++)
          if (j != i &&
              math.pow(x[3 * i] - x[3 * j], 2) +
                      math.pow(x[3 * i + 1] - x[3 * j + 1], 2) +
                      math.pow(x[3 * i + 2] - x[3 * j + 2], 2) <
                  h * h)
            j,
      ],
  ];
  final start = Int32List(n + 1);
  for (var i = 0; i < n; i++) {
    start[i + 1] = start[i] + rows[i].length;
  }
  final list = Int32List(start[n]);
  for (var i = 0; i < n; i++) {
    list.setAll(start[i], rows[i]);
  }
  return (x, start, list);
}

void _close(Float64List a, Float64List b) {
  var scale = 0.0;
  for (final v in a) {
    scale = math.max(scale, v.abs());
  }
  for (var i = 0; i < a.length; i++) {
    expect(b[i], closeTo(a[i], 1e-12 * scale + 1e-300), reason: 'entry $i');
  }
}

void main() {
  test('the native kernels are built here', () {
    // On a machine with a C compiler the hook builds them; this one has.
    expect(nativePbfAvailable, isTrue);
  });

  for (final lanes in const [1, 2, 4, 8]) {
    test('each native kernel matches the Dart one to a part in 10¹², '
        '\$lanes at a time', () {
      // Each width this processor has: the wider are only the running
      // processor's (AVX2, AVX-512F) on x86-64, and all of them on arm64.
      if (setNativePbfLanes(lanes) != lanes) {
        markTestSkipped('not on this processor');
        return;
      }
      addTearDown(() => setNativePbfLanes(0));
      _matches();
    });
  }

  test('the processor chooses how many at a time', () {
    expect(const [2, 4], contains(nativePbfLanes));
  });

  test('both find the same neighbours, in the same order', () {
    final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001);
    final native = ParticleFluid(
      medium: FluidMedium.water,
      spacing: 0.001,
      native: true,
    );
    const n = 300;
    final (x, start, list) = _cloud(n, fluid.h);
    final (s1, l1) = fluid.kernels.neighbours(x, n, fluid.h);
    final (s2, l2) = native.kernels.neighbours(x, n, fluid.h);
    expect(s2, s1);
    expect(l2, l1);
    // And the same as every pair within reach, counted the slow way.
    expect(l1.length, list.length);
    expect(s1, start);
    // Candidates half as far again, cut back to the reach, are the same
    // pairs: each row the same set, in the candidates' own order.
    for (final kernels in [fluid.kernels, native.kernels]) {
      final (cs, cl) = kernels.neighbours(x, n, 1.5 * fluid.h);
      expect(cl.length, greaterThan(list.length));
      final (ws, wl) = kernels.within(x, n, cs, cl, fluid.h);
      expect(ws, start);
      for (var i = 0; i < n; i++) {
        expect(
          wl.sublist(ws[i], ws[i + 1]).toSet(),
          list.sublist(start[i], start[i + 1]).toSet(),
        );
      }
    }
  });

  test(
    'a drop run natively lands where the Dart one does, every drop of it',
    () {
      Vector3 run({required bool native}) {
        final fluid = ParticleFluid(
          medium: FluidMedium.water,
          spacing: 0.001,
          native: native,
        )..inject(27e-9, Vector3(0, 0.01, 0), Vector3(0.05, 0, 0));
        final bench = [PlaneObstacle(normal: Vector3(0, 1, 0), offset: 0)];
        for (var i = 0; i < 120; i++) {
          fluid.step(1 / 240, gravity: Vector3(0, -9.81, 0), obstacles: bench);
        }
        expect(fluid.volume, closeTo(27e-9, 1e-21));
        final centre = Vector3.zero();
        for (final p in fluid.positions) {
          centre.add(p);
        }
        return centre..scale(1.0 / fluid.count);
      }

      final reference = run(native: false);
      final fast = run(native: true);
      // **Not the same path: the same drop.** A step decides things — whether
      // a particle touches the bench, whether its edge holds the drop — and a
      // part in 10¹² either side of a threshold decides differently: the Dart
      // run started a millionth of a micrometre over lands seventy-five
      // micrometres off its own. So the two land as the same drop, on the
      // bench, within a particle's spacing of each other, every drop of it
      // there; to the bit is the Dart kernels' promise, not this.
      expect(fast.y, lessThan(0.003));
      expect((fast - reference).length, lessThan(0.001));
    },
  );

  test('the native modes of a round cross-section are the Dart ones', () {
    // A disc of cells twelve across its radius, as a test tube's surface.
    const r = 12;
    final index = <int, int>{};
    for (var y = -r; y <= r; y++) {
      for (var x = -r; x <= r; x++) {
        if (x * x + y * y <= r * r) {
          index[(y + r) * 100 + (x + r)] = index.length;
        }
      }
    }
    final neighbours = List<List<int>>.generate(index.length, (_) => []);
    index.forEach((key, i) {
      for (final d in const [1, -1, 100, -100]) {
        final j = index[key + d];
        if (j != null) neighbours[i].add(j);
      }
    });
    final n = index.length;
    const cell2 = 0.0006 * 0.0006;
    final dart = FreeSurface.solveModes(n, neighbours, cell2, 4);
    final native = FreeSurface.solveModes(
      n,
      neighbours,
      cell2,
      4,
      native: true,
    );
    for (var m = 0; m < 4; m++) {
      expect(native.$2[m], closeTo(dart.$2[m], dart.$2[m] * 1e-9));
    }
    // Each native mode lies in the span of the Dart modes of its own k²:
    // a round section's come in pairs, and either turn of a pair is right.
    double dot(Float64List a, Float64List b) {
      var s = 0.0;
      for (var i = 0; i < n; i++) {
        s += a[i] * b[i];
      }
      return s;
    }

    for (var m = 0; m < 4; m++) {
      final mode = native.$1[m];
      var projected = 0.0;
      for (var d = 0; d < 4; d++) {
        if ((dart.$2[d] - native.$2[m]).abs() > dart.$2[d] * 1e-6) continue;
        final c = dot(mode, dart.$1[d]) / dot(dart.$1[d], dart.$1[d]);
        projected += c * c * dot(dart.$1[d], dart.$1[d]);
      }
      expect(projected / dot(mode, mode), closeTo(1.0, 1e-9));
    }
  });

  test('the native meniscus is the Dart one, to within a tolerance', () {
    for (final medium in [
      FluidMedium.water,
      FluidMedium.ethanol,
      FluidMedium.mercury,
    ]) {
      for (final radius in [0.0005, 0.0075, 0.02]) {
        final dart = TubeMeniscus(medium: medium, radius: radius, g: 9.81);
        final native = TubeMeniscus(
          medium: medium,
          radius: radius,
          g: 9.81,
          native: true,
        );
        final scale = dart.apexCurvature.abs() + 1.0 / radius * 1e-6;
        expect(
          native.apexCurvature,
          closeTo(dart.apexCurvature, scale * 1e-9),
          reason: '\${medium.name} in \$radius m',
        );
        expect(native.wallRise, closeTo(dart.wallRise, radius * 1e-9));
        expect(native.meanHeight, closeTo(dart.meanHeight, radius * 1e-9));
      }
    }
  });
}

/// Each native kernel against the Dart one, at the width set.
void _matches() {
  final fluid = ParticleFluid(medium: FluidMedium.water, spacing: 0.001);
  final native = ParticleFluid(
    medium: FluidMedium.water,
    spacing: 0.001,
    native: true,
  );
  final dart = fluid.kernels;
  final c = native.kernels;
  expect(c, isNot(isA<DartPbfKernels>()));
  const n = 200;
  final (x, start, list) = _cloud(n, fluid.h);
  expect(list.length, greaterThan(n));

  final d1 = Float64List(n);
  final d2 = Float64List(n);
  dart.densities(x, start, list, n, d1);
  c.densities(x, start, list, n, d2);
  _close(d1, d2);

  final n1 = Float64List(3 * n);
  final n2 = Float64List(3 * n);
  dart.normals(x, start, list, n, d1, n1);
  c.normals(x, start, list, n, d1, n2);
  _close(n1, n2);

  final before = Float64List(3 * n)..fillRange(0, 3 * n, -9.81);
  final after = Float64List(3 * n)..fillRange(0, 3 * n, 0.1);
  final v1 = Float64List(3 * n);
  final v2 = Float64List(3 * n);
  dart.forces(x, start, list, n, d1, n1, before, after, v1, 1e-4);
  c.forces(x, start, list, n, d1, n1, before, after, v2, 1e-4);
  _close(v1, v2);

  final l1 = Float64List(n);
  final l2 = Float64List(n);
  dart.lambdas(x, start, list, n, l1);
  c.lambdas(x, start, list, n, l2);
  _close(l1, l2);

  final p1 = Float64List(3 * n);
  final p2 = Float64List(3 * n);
  dart.deltas(x, start, list, n, l1, p1);
  c.deltas(x, start, list, n, l1, p2);
  _close(p1, p2);

  final s1 = Float64List(3 * n);
  final s2 = Float64List(3 * n);
  dart.viscosity(x, v1, start, list, n, 0.05, s1);
  c.viscosity(x, v1, start, list, n, 0.05, s2);
  _close(s1, s2);
}
