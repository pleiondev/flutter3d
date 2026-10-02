import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'optics.dart' show radiusAt;

/// The free surface of a liquid in a round vessel, and how it moves.
///
/// **A liquid's surface stays level while its glass tilts, and it lags.**
/// Turn a tube and the liquid does not turn with it: its surface keeps
/// facing up, so in the glass's own frame it is a plane sloping the other
/// way. Turn it quickly and the liquid is left where it was for a moment,
/// then rocks across the glass and back, with finer waves running over it,
/// before it settles. Tap the glass and rings run across the surface and
/// fade. Those are most of what makes a coloured column read as liquid
/// rather than as a painted solid, and none of them needs a fluid solver: a
/// liquid in a round vessel has known modes of oscillation.
///
/// **The modes are Bessel functions.** Linear waves on a liquid of depth h
/// in a round vessel of radius R have the shapes J_m(ξ r / R) cos(m θ),
/// where ξ is a zero of the derivative J_m', so that the surface meets the
/// wall square, and each rings at ω² = g k tanh(k h) with k = ξ / R.
///
/// - **Tilting moves the m = 1 family** ([tiltZeros]: 1.8412, 5.3314,
///   8.5363). The surface settles to the plane level in the world, which
///   is kept exactly; what is followed is how far the liquid is from that
///   plane, mode by mode. When the glass turns faster than the liquid can
///   follow, the plane moves and the liquid does not, so each mode is left
///   off its rest by its share of the change in slope. A plane x is
///   Σ c_n J_1(ξ_n r / R) with c_n = 2R / ((ξ_n² − 1) J_1(ξ_n)), which is
///   what that share is: the first mode, the sloshing, takes most of it,
///   the other two the ripples that run across it.
/// - **A tap moves the m = 0 family** ([ringZeros]: 3.8317, 7.0156,
///   10.1735, the zeros of J_1): rings. None of them moves liquid in or out
///   of the middle, since ∫ J_0(ξ r / R) r dr is nought at those ξ, so the
///   level stays where it was poured.
final class Slosh {
  Slosh({required this.radius, required this.depth});

  /// The vessel's radius at the surface, and how deep the liquid is.
  double radius;
  double depth;

  static const List<double> tiltZeros = <double>[1.8412, 5.3314, 8.5363];
  static const List<double> ringZeros = <double>[3.8317, 7.0156, 10.1735];

  /// The slope the surface settles to, rise per metre along x and z in the
  /// glass's frame: level in the world. Set it as the glass turns, and the
  /// liquid is left behind by the change.
  double get targetX => _targetX;
  double get targetZ => _targetZ;
  double _targetX = 0.0;
  double _targetZ = 0.0;

  set targetX(double value) {
    _leave(offX, value - _targetX);
    _targetX = value;
  }

  set targetZ(double value) {
    _leave(offZ, value - _targetZ);
    _targetZ = value;
  }

  /// How far each tilting mode stands from its rest, along x and along z,
  /// in metres at its peak; and how fast each is moving.
  final List<double> offX = <double>[0.0, 0.0, 0.0];
  final List<double> offZ = <double>[0.0, 0.0, 0.0];
  final List<double> _rateX = <double>[0.0, 0.0, 0.0];
  final List<double> _rateZ = <double>[0.0, 0.0, 0.0];

  /// How far each ring mode lifts the middle of the surface, and how fast.
  final List<double> rings = <double>[0.0, 0.0, 0.0];
  final List<double> _ringRates = <double>[0.0, 0.0, 0.0];

  static const double _gravity = 9.81;

  /// Fractions of critical damping: water in glass this size rocks four or
  /// five times before it is still. A finer wave loses its energy to the
  /// boundary layer at the wall sooner, roughly as the root of its
  /// frequency.
  static double _damping(double xi) => 0.035 * math.sqrt(xi / tiltZeros[0]);

  /// The plane's share of mode [n]: c_n over the radius.
  static double share(int n) {
    final xi = tiltZeros[n];
    return 2.0 / ((xi * xi - 1.0) * besselJ1(xi));
  }

  /// The liquid stays where it was while the plane it settles to tilts by
  /// [change]: every mode is left that much further from its rest.
  void _leave(List<double> off, double change) {
    for (var n = 0; n < off.length; n++) {
      off[n] -= share(n) * radius * change;
    }
  }

  /// The glass was jerked: the surface is left [dz] of slope along z off
  /// the plane it settles to, as a tilt that sudden would leave it.
  void jolt(double dz) => _leave(offZ, -dz);

  /// The angular frequency of the mode whose zero is [xi].
  double frequency(double xi) {
    final k = xi / radius;
    return math.sqrt(_gravity * k * _tanh(k * math.max(depth, 1e-3)));
  }

  /// Taps the glass: rings of [strength] metres at the middle, the finer
  /// ones weaker and of the other sign, as a knock on the side starts them.
  void tap(double strength) {
    rings[0] += strength;
    rings[1] -= 0.55 * strength;
    rings[2] += 0.3 * strength;
  }

  /// Moves on by [seconds], in steps short enough for the finest wave.
  void step(double seconds) {
    final steps = math.max(1, (seconds * 600).ceil());
    final dt = seconds / steps;
    // Semi-implicit Euler for each mode: the rate first, then the position
    // from it, which neither gains nor loses energy of its own.
    void ring(List<double> x, List<double> v, List<double> zeros) {
      for (var n = 0; n < x.length; n++) {
        final w = frequency(zeros[n]);
        final zeta = _damping(zeros[n]);
        for (var i = 0; i < steps; i++) {
          v[n] += (-w * w * x[n] - 2.0 * zeta * w * v[n]) * dt;
          x[n] += v[n] * dt;
        }
      }
    }

    ring(offX, _rateX, tiltZeros);
    ring(offZ, _rateZ, tiltZeros);
    ring(rings, _ringRates, ringZeros);
  }

  /// Whether nothing moves that the eye would see: every mode within a
  /// tenth of a millimetre of rest, and slower than that a radian.
  bool get settled {
    const still = 1e-4;
    bool quiet(List<double> x, List<double> v, List<double> zeros) {
      for (var n = 0; n < x.length; n++) {
        if (x[n].abs() > still) return false;
        if (v[n].abs() > still * frequency(zeros[n])) return false;
      }
      return true;
    }

    return quiet(offX, _rateX, tiltZeros) &&
        quiet(offZ, _rateZ, tiltZeros) &&
        quiet(rings, _ringRates, ringZeros);
  }

  /// Sets where the surface settles without leaving the liquid behind, and
  /// puts it there: for a glass turned past where the waves are followed.
  void rest(double x, double z) {
    _targetX = x;
    _targetZ = z;
    settle();
  }

  /// Puts the surface where it settles, at once.
  void settle() {
    for (final list in [offX, offZ, _rateX, _rateZ, rings, _ringRates]) {
      list.fillRange(0, list.length, 0.0);
    }
  }

  /// How far the surface stands above the level at (x, z), and its slope
  /// there, rise per metre along x and along z.
  ({double height, double dx, double dz}) at(double x, double z) {
    final r = math.sqrt(x * x + z * z);
    final cx = r > 1e-9 ? x / r : 1.0;
    final cz = r > 1e-9 ? z / r : 0.0;
    var height = _targetX * x + _targetZ * z;
    var dx = _targetX;
    var dz = _targetZ;
    // The tilting modes: J1(k r) times the cosine of the angle from x, and
    // from z. In Cartesian terms J1(k r) x / r, whose gradient is
    // (J1' k − J1 / r) (x / r) r̂ + (J1 / r) x̂, and likewise for z.
    for (var n = 0; n < offX.length; n++) {
      final ax = offX[n];
      final az = offZ[n];
      if (ax == 0.0 && az == 0.0) continue;
      final k = tiltZeros[n] / radius;
      final kr = k * r;
      final j1 = besselJ1(kr);
      // J1(u) / u, with its limit of a half at the axis.
      final j1OverR = r > 1e-9 ? j1 / r : 0.5 * k;
      final dj1 = k * (besselJ0(kr) - (kr > 1e-9 ? j1 / kr : 0.5));
      final along = ax * cx + az * cz;
      height += along * j1;
      final radial = along * (dj1 - j1OverR);
      dx += radial * cx + ax * j1OverR;
      dz += radial * cz + az * j1OverR;
    }
    for (var n = 0; n < rings.length; n++) {
      final a = rings[n];
      if (a == 0.0) continue;
      final k = ringZeros[n] / radius;
      height += a * besselJ0(k * r);
      // d/dr J0(k r) = −k J1(k r).
      final radial = -a * k * besselJ1(k * r);
      dx += radial * cx;
      dz += radial * cz;
    }
    return (height: height, dx: dx, dz: dz);
  }

  static double _tanh(double x) {
    final e = math.exp(-2.0 * x);
    return (1.0 - e) / (1.0 + e);
  }
}

/// J_0, from its series: exact enough over the range the modes use, up to
/// about eleven, where the terms' cancellation costs four of double's
/// sixteen digits.
double besselJ0(double x) {
  final q = -x * x / 4.0;
  var term = 1.0;
  var sum = 1.0;
  for (var m = 1; m < 40; m++) {
    term *= q / (m * m);
    sum += term;
    if (term.abs() < 1e-16) break;
  }
  return sum;
}

/// J_1, from its series, likewise.
double besselJ1(double x) {
  final q = -x * x / 4.0;
  var term = x / 2.0;
  var sum = term;
  for (var m = 1; m < 40; m++) {
    term *= q / (m * (m + 1));
    sum += term;
    if (term.abs() < 1e-16) break;
  }
  return sum;
}

/// How high water climbs the glass where it meets it, and how quickly that
/// fades towards the middle: the meniscus, scaled with the rest of the
/// bench.
const double meniscusRise = 0.008;
const double _meniscusReach = 0.01;

/// The liquid in a vessel whose inside is [wall] — a profile in the (radius,
/// height) plane from the middle of its floor up the side, as
/// [Vessel.liquidAt] gives it without its cap — standing at [level] in the
/// vessel's own frame, its surface as [surface] shapes it, with a meniscus
/// round the edge.
///
/// Built as a lathe is, a column of rows for each of [segments] angles, but
/// the rows end where the surface meets the wall at that angle, which a
/// tilted or rippling surface puts at a different height at each one: up
/// the side to there, then in across the surface to the middle.
MeshData liquidVolume({
  required List<Vector2> wall,
  required double level,
  required Slosh surface,
  int segments = 64,
  int sideRows = 28,
  int surfaceRows = 14,
}) {
  final floor = wall.first.y;
  final top = wall.map((p) => p.y).reduce(math.max);
  double radiusAtHeight(double y) =>
      radiusAt(wall, y.clamp(floor, top)) ?? wall.last.x;

  // Where the surface meets the wall at angle (c, s): the height y at which
  // the surface over the wall's radius there is y itself.
  double meets(double c, double s) {
    double gap(double y) {
      final r = radiusAtHeight(y);
      return y - (level + meniscusRise + surface.at(r * c, r * s).height);
    }

    var lo = floor;
    var hi = top;
    if (gap(lo) >= 0.0) return lo;
    if (gap(hi) <= 0.0) return hi;
    for (var i = 0; i < 40; i++) {
      final mid = 0.5 * (lo + hi);
      if (gap(mid) < 0.0) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.5 * (lo + hi);
  }

  // The wall's polyline up to [height], with the length along it to each
  // point.
  ({List<Vector2> points, List<double> along}) wallTo(double height) {
    final points = <Vector2>[wall.first];
    for (var i = 1; i < wall.length; i++) {
      final a = wall[i - 1];
      final b = wall[i];
      if (b.y <= height) {
        points.add(b);
        continue;
      }
      if (a.y < height) {
        final t = (height - a.y) / (b.y - a.y);
        points.add(Vector2(a.x + (b.x - a.x) * t, height));
      }
      break;
    }
    final along = <double>[0.0];
    for (var i = 1; i < points.length; i++) {
      along.add(along.last + (points[i] - points[i - 1]).length);
    }
    return (points: points, along: along);
  }

  final rows = sideRows + 1 + surfaceRows;
  final builder = MeshBuilder(
    VertexLayout.standard,
    reserveVertices: (segments + 1) * rows,
    reserveIndices: segments * (rows - 1) * 6,
  );
  final onAxis = List<bool>.filled(rows, false);
  for (var i = 0; i <= segments; i++) {
    final angle = 2.0 * math.pi * i / segments;
    final c = math.cos(angle);
    final s = math.sin(angle);
    final tangent = Vector4(-s, 0.0, c, 1.0);
    final u = i / segments;
    final edge = meets(c, s);
    final (:points, :along) = wallTo(edge);
    final length = along.last;

    // Up the side, evenly along the wall, each row with the normal of the
    // stretch it lies on: down on a flat floor, out up the wall.
    var segment = 1;
    for (var k = 0; k <= sideRows; k++) {
      final d = length * k / sideRows;
      while (segment < points.length - 1 && along[segment] < d) {
        segment++;
      }
      final a = points[segment - 1];
      final b = points.length > 1 ? points[segment] : a;
      final span = along.length > 1 ? along[segment] - along[segment - 1] : 0.0;
      final t = span > 0.0 ? (d - along[segment - 1]) / span : 0.0;
      final p = a + (b - a) * t;
      final run = b - a;
      final plane = run.length2 > 0.0
          ? Vector2(run.y, -run.x).normalized()
          : Vector2(0.0, -1.0);
      if (k == 0 && p.x == 0.0) onAxis[0] = true;
      builder.addVertex(
        position: Vector3(p.x * c, p.y, p.x * s),
        normal: Vector3(plane.x * c, plane.y, plane.x * s),
        texcoord: Vector2(u, 0.5 * k / sideRows),
        tangent: tangent,
      );
    }

    // In across the surface from the wall to the middle, closer together
    // near the wall, where the meniscus curls up.
    final rim = radiusAtHeight(edge);
    for (var j = 1; j <= surfaceRows; j++) {
      final w = 1.0 - j / surfaceRows;
      final f = 1.0 - (1.0 - w) * (1.0 - w);
      final r = rim * f;
      final x = r * c;
      final z = r * s;
      final shape = surface.at(x, z);
      final climb = meniscusRise * math.exp(-(rim - r) / _meniscusReach);
      final dClimb = climb / _meniscusReach;
      final dx = shape.dx + dClimb * c;
      final dz = shape.dz + dClimb * s;
      builder.addVertex(
        position: Vector3(x, level + shape.height + climb, z),
        normal: Vector3(-dx, 1.0, -dz)..normalize(),
        texcoord: Vector2(u, 0.5 + 0.5 * j / surfaceRows),
        tangent: tangent,
      );
    }
  }
  onAxis[rows - 1] = true;

  // The lathe's winding, so the faces look out; triangles that collapse on
  // the axis are left out.
  int at(int column, int row) => column * rows + row;
  for (var i = 0; i < segments; i++) {
    for (var j = 0; j < rows - 1; j++) {
      final a = at(i, j);
      final b = at(i + 1, j);
      final cc = at(i + 1, j + 1);
      final d = at(i, j + 1);
      if (!onAxis[j]) builder.addTriangle(a, d, b);
      if (!onAxis[j + 1]) builder.addTriangle(b, d, cc);
    }
  }
  return builder.build();
}
