import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'fluid_medium.dart';
import 'vessel_shape.dart';

/// The waves on a liquid's free surface in a vessel of any shape: how far
/// the surface stands off the plane it settles to, and how that moves.
///
/// **The modes of the vessel, worked out rather than assumed.** Small waves
/// on a liquid of depth h are sums of shapes φ that satisfy ∇²φ = −k²φ over
/// the surface and meet the wall square (∂φ/∂n = 0), each ringing at its own
/// frequency, ω² = (gk + σk³/ρ)·tanh(kh): gravity and surface tension pulling
/// it back, the depth holding it. In a round vessel those shapes are Bessel
/// functions and the k are known zeros; in any other they are whatever the
/// outline makes them. So the surface is laid out as a grid over the plane's
/// cut through the vessel, its Laplacian with the wall's condition is built
/// on the cells inside, and its lowest [modeCount] shapes and k² are found by
/// Lanczos. A round vessel gets its Bessel modes back to a few per cent,
/// which is the test that this is the same physics.
///
/// **Volume stays by construction.** Every shape but the flat one averages
/// to nought over the surface, and the flat one is never kept, so no wave
/// adds or takes away liquid.
///
/// **Viscosity damps them**, twice over. Most of it is lost in the thin
/// layer where the liquid slides past the wall, and for the first mode of a
/// round vessel the measured rate is Stephens and Dodge's,
/// ζ = 0.83·√(ν / √(gR³))·[1 + 0.318 / sinh(1.84h/R)·(1 + (1 − h/R) /
/// cosh(1.84h/R))]; a boundary layer is √(2ν/ω) thick, so a mode n's decay
/// rate goes as the root of its frequency. The rest is lost in the bulk,
/// 2νk², which is what quickly kills short ripples. A vessel that is not
/// round is given the radius of the round one with its surface's area.
final class FreeSurface {
  FreeSurface({required this.medium, this.cells = 40, this.modeCount = 12});

  /// The liquid at the surface: the top one, when there are layers.
  FluidMedium medium;

  /// How many cells the grid has across its wider side.
  final int cells;

  /// How many of the lowest shapes are kept.
  final int modeCount;

  /// How far the plane may turn, radians, before the modes are found again.
  static const double reuseTurn = 0.05;

  _Grid? _grid;
  List<Float64List> _modes = const [];
  Float64List _k2 = Float64List(0);
  Float64List _amplitude = Float64List(0);
  Float64List _rate = Float64List(0);
  Float64List? _field;

  /// The plane the surface settles to, in the vessel's frame: its normal and
  /// height along it, as last laid out.
  Vector3 get up => _grid?.up ?? Vector3(0, 1, 0);
  double get height => _grid?.height ?? 0.0;

  /// The surface's area, square metres.
  double get area => _grid == null ? 0.0 : _grid!.count * _grid!.cell2;

  /// How much liquid the waves hold above the plane, cubic metres: nought,
  /// since no mode but the flat one has any, and that one is never kept.
  /// For a test to hold the surface to.
  double get displacedVolume {
    final grid = _grid;
    if (grid == null || _modes.isEmpty) return 0.0;
    return _heights().fold(0.0, (sum, h) => sum + h) * grid.cell2;
  }

  /// The wavenumbers of the modes kept, lowest first.
  List<double> get wavenumbers => [for (final k2 in _k2) math.sqrt(k2)];

  /// Lays the surface out over the plane `up · p = height` through [shape],
  /// keeping the liquid where it was: the waves there are carried over, and
  /// a plane that has turned or moved leaves them that much further from it.
  ///
  /// A plane that has turned by less than [reuseTurn] and moved by less than
  /// half a cell keeps the modes it has: the cut has hardly changed shape,
  /// and the modes are what cost time to find. Only the liquid left behind
  /// by the move is added to the waves.
  void layOut(VesselShape shape, Vector3 up, double height) {
    final old = _grid;
    if (old != null &&
        _modes.isNotEmpty &&
        1.0 - old.up.dot(up.normalized()) < 0.5 * reuseTurn * reuseTurn &&
        (height - old.height).abs() < 0.5 * old.cell) {
      final moved = old.movedTo(up, height);
      final behind = Float64List(moved.count);
      for (var i = 0; i < moved.count; i++) {
        final p = moved.point(i);
        behind[i] = -(old.up.dot(p) - old.height);
      }
      _grid = moved;
      final added = _project(behind);
      for (var n = 0; n < added.length; n++) {
        _amplitude[n] += added[n];
      }
      _field = null;
      return;
    }
    final oldHeights = old == null ? null : _heights();
    final oldRates = old == null ? null : _sumModes(_rate);
    final grid = _Grid.cut(shape, up, height, cells);
    _grid = grid;
    _field = null;
    if (grid.count < 6) {
      _modes = const [];
      _k2 = Float64List(0);
      _amplitude = Float64List(0);
      _rate = Float64List(0);
      return;
    }
    final (shapes, k2) = _lowestModes(grid, modeCount);
    _modes = shapes;
    _k2 = k2;
    // The liquid stays: what stood off the old plane stands off the new one
    // by that, less how far the new plane is above the old one there.
    final heights = Float64List(grid.count);
    final rates = Float64List(grid.count);
    for (var i = 0; i < grid.count; i++) {
      final p = grid.point(i);
      if (old != null) {
        heights[i] = old.sample(oldHeights!, p) - (old.up.dot(p) - old.height);
        rates[i] = old.sample(oldRates!, p);
      }
    }
    _amplitude = _project(heights);
    _rate = _project(rates);
  }

  /// Moves the waves on by [dt] seconds under gravity [g], over a liquid
  /// [depth] deep on average: each mode exactly, as the damped oscillator it
  /// is, so any step is stable.
  void step(double dt, {required double g, required double depth}) {
    if (_modes.isEmpty) return;
    // Still water stays still: nothing to ring.
    var still = true;
    for (var n = 0; n < _amplitude.length && still; n++) {
      still = _amplitude[n] == 0.0 && _rate[n] == 0.0;
    }
    if (still) return;
    final nu = medium.kinematicViscosity;
    final tension = medium.surfaceTension / medium.density;
    final h = math.max(depth, 1e-6);
    double omega(double k) =>
        math.sqrt(math.max((g * k + tension * k * k * k) * _tanh(k * h), 0.0));
    final k1 = math.sqrt(_k2[0]);
    final w1 = omega(k1);
    final radius = math.sqrt(area / math.pi);
    final boundary = _stephens(nu, g, radius, h) * w1;
    _omega2 = Float64List(_modes.length);
    _decay = Float64List(_modes.length);
    for (var n = 0; n < _modes.length; n++) {
      final k = math.sqrt(_k2[n]);
      final w = omega(k);
      final decay =
          boundary * math.sqrt(w / math.max(w1, 1e-9)) + 2.0 * nu * k * k;
      _omega2[n] = w * w;
      _decay[n] = decay;
      final wd = math.sqrt(math.max(w * w - decay * decay, 1e-12));
      final c = Portable.cos(wd * dt);
      final s = Portable.sin(wd * dt);
      final e = Portable.exp(-decay * dt);
      final a = _amplitude[n];
      final v = _rate[n];
      final b = (v + decay * a) / wd;
      _amplitude[n] = e * (a * c + b * s);
      _rate[n] = e * (v * c - (decay * b + a * wd) * s);
    }
    _field = null;
  }

  Float64List _omega2 = Float64List(0);
  Float64List _decay = Float64List(0);

  /// The force the waves put on the vessel, newtons, in its frame, for a
  /// liquid of [density]: the liquid's centre of mass moves as the surface
  /// rocks, and what moves it pushes back on the glass. Each mode shifts the
  /// centre by its first moment over the surface times its amplitude, so the
  /// force is −ρ Σ Mₙ äₙ, with äₙ = −ωₙ²aₙ − 2σₙȧₙ as the mode rings.
  Vector3 force(double density) {
    final grid = _grid;
    final out = Vector3.zero();
    if (grid == null || _omega2.length != _modes.length) return out;
    for (var n = 0; n < _modes.length; n++) {
      final moment = Vector3.zero();
      final shape = _modes[n];
      for (var i = 0; i < grid.count; i++) {
        moment.addScaled(grid.e1, shape[i] * grid.cellsU[i]);
        moment.addScaled(grid.e2, shape[i] * grid.cellsV[i]);
      }
      moment.scale(grid.cell2);
      final accel = -_omega2[n] * _amplitude[n] - 2.0 * _decay[n] * _rate[n];
      out.addScaled(moment, -density * accel);
    }
    return out;
  }

  /// How wide a [knock] spreads, metres: the patch's standard deviation.
  double get knockSpread => 2.0 * (_grid?.cell ?? 0.0);

  /// Knocks the surface at [point] (vessel frame) [strength] metres high,
  /// over a patch two cells across: what is not a wave — the patch's mean —
  /// is not kept, so no liquid is added.
  void knock(Vector3 point, double strength) {
    final grid = _grid;
    if (grid == null || _modes.isEmpty) return;
    final spread = knockSpread;
    final bump = Float64List(grid.count);
    for (var i = 0; i < grid.count; i++) {
      final d = grid.point(i) - point;
      final along = grid.up.dot(d);
      final r2 = d.length2 - along * along;
      bump[i] = strength * Portable.exp(-r2 / (2.0 * spread * spread));
    }
    final added = _project(bump);
    for (var n = 0; n < added.length; n++) {
      _amplitude[n] += added[n];
    }
    _field = null;
  }

  /// How far the surface stands off its plane, along [up], over [point]
  /// (vessel frame); nought outside it.
  double displacement(Vector3 point) {
    final grid = _grid;
    if (grid == null || _modes.isEmpty) return 0.0;
    return grid.sample(_heights(), point);
  }

  /// Whether nothing moves that the eye would see: every mode under a tenth
  /// of a millimetre, and slower than that a radian.
  bool get settled {
    for (var n = 0; n < _amplitude.length; n++) {
      if (_amplitude[n].abs() * _norm(n) > 1e-4) return false;
      if (_rate[n].abs() * _norm(n) > 1e-3) return false;
    }
    return true;
  }

  /// Takes every wave away.
  void calm() {
    _amplitude = Float64List(_amplitude.length);
    _rate = Float64List(_rate.length);
    _field = null;
  }

  /// The surface's displacement at each cell.
  Float64List _heights() => _field ??= _sumModes(_amplitude);

  Float64List _sumModes(Float64List weights) {
    final grid = _grid!;
    final out = Float64List(grid.count);
    for (var n = 0; n < _modes.length && n < weights.length; n++) {
      final w = weights[n];
      if (w == 0.0) continue;
      final shape = _modes[n];
      for (var i = 0; i < out.length; i++) {
        out[i] += w * shape[i];
      }
    }
    return out;
  }

  /// The largest a mode stands anywhere, per unit amplitude.
  /// The largest a mode gets anywhere on the surface, once a layout.
  double _norm(int n) {
    if (!identical(_normsOf, _modes)) {
      _normsOf = _modes;
      _norms = [
        for (final mode in _modes)
          mode.fold(0.0, (most, x) => math.max(most, x.abs())),
      ];
    }
    return _norms[n];
  }

  List<Float64List>? _normsOf;
  List<double> _norms = const [];

  /// The most the waves can stand off the plane anywhere just now: no more
  /// than every mode at its peak at once.
  double get reach {
    var sum = 0.0;
    for (var n = 0; n < _amplitude.length; n++) {
      sum += _amplitude[n].abs() * _norm(n);
    }
    return sum;
  }

  /// [values] over the cells as amplitudes of the kept modes: the modes are
  /// orthonormal under the area, so each is the area-weighted dot product.
  Float64List _project(Float64List values) {
    final cell2 = _grid!.cell2;
    final out = Float64List(_modes.length);
    for (var n = 0; n < _modes.length; n++) {
      var sum = 0.0;
      final shape = _modes[n];
      for (var i = 0; i < values.length; i++) {
        sum += values[i] * shape[i];
      }
      out[n] = sum * cell2;
    }
    return out;
  }

  static double _tanh(double x) {
    if (x > 20.0) return 1.0;
    final e = Portable.exp(-2.0 * x);
    return (1.0 - e) / (1.0 + e);
  }

  /// Stephens and Dodge's damping ratio for the first mode of a round
  /// vessel of [radius], liquid [depth] deep.
  static double _stephens(double nu, double g, double radius, double depth) {
    final r = math.max(radius, 1e-6);
    final ratio = 1.84 * depth / r;
    final sinh = 0.5 * (Portable.exp(ratio) - Portable.exp(-ratio));
    final cosh = 0.5 * (Portable.exp(ratio) + Portable.exp(-ratio));
    final shallow = ratio > 30.0
        ? 0.0
        : 0.318 / math.max(sinh, 1e-9) * (1.0 + (1.0 - depth / r) / cosh);
    return 0.83 * math.sqrt(nu / math.sqrt(g * r * r * r)) * (1.0 + shallow);
  }

  /// The lowest [count] non-flat modes of [grid]'s Laplacian with the wall's
  /// condition, orthonormal under the area, and their k².
  static (List<Float64List>, Float64List) _lowestModes(_Grid grid, int count) {
    final n = grid.count;
    final inv = 1.0 / grid.cell2;
    // The graph Laplacian: each cell against the neighbours it has inside.
    // A neighbour outside is the wall, and leaving it out is ∂φ/∂n = 0.
    Float64List apply(Float64List x) {
      final y = Float64List(n);
      for (var i = 0; i < n; i++) {
        var sum = 0.0;
        for (final j in grid.neighbours[i]) {
          sum += x[i] - x[j];
        }
        y[i] = sum * inv;
      }
      return y;
    }

    // The lowest of L are the highest of L⁻¹, and well apart there, where
    // near nought they crowd together and Lanczos on L itself would take
    // hundreds of steps to tell them apart. L⁻¹ is applied by conjugate
    // gradients, on the flat-free part where L can be inverted.
    Float64List solve(Float64List b) {
      final x = Float64List(n);
      final r = Float64List.fromList(b);
      _removeMean(r);
      final p = Float64List.fromList(r);
      var rr = _dot(r, r);
      final stop = 1e-24 * math.max(rr, 1e-300);
      for (var it = 0; it < 4 * n && rr > stop; it++) {
        final ap = apply(p);
        final step = rr / _dot(p, ap);
        for (var i = 0; i < n; i++) {
          x[i] += step * p[i];
          r[i] -= step * ap[i];
        }
        final next = _dot(r, r);
        final ratio = next / rr;
        rr = next;
        for (var i = 0; i < n; i++) {
          p[i] = r[i] + ratio * p[i];
        }
      }
      _removeMean(x);
      return x;
    }

    final steps = math.min(n - 1, 3 * count + 12);
    final basis = <Float64List>[];
    final alpha = <double>[];
    final beta = <double>[];
    // A start that is not flat, with the flat part taken out: the Krylov
    // space then never holds the flat mode.
    var q = Float64List(n);
    for (var i = 0; i < n; i++) {
      q[i] = Portable.sin(1.0 + 0.7 * i) + 0.3 * Portable.cos(0.31 * i * i);
    }
    _removeMean(q);
    _normalise(q);
    var previous = Float64List(n);
    var b = 0.0;
    for (var m = 0; m < steps; m++) {
      basis.add(q);
      final w = solve(q);
      for (var i = 0; i < n; i++) {
        w[i] -= b * previous[i];
      }
      final a = _dot(w, q);
      for (var i = 0; i < n; i++) {
        w[i] -= a * q[i];
      }
      // Full reorthogonalisation, twice: Lanczos alone loses it and finds
      // the same mode again.
      for (var pass = 0; pass < 2; pass++) {
        for (final v in basis) {
          final c = _dot(w, v);
          for (var i = 0; i < n; i++) {
            w[i] -= c * v[i];
          }
        }
        _removeMean(w);
      }
      alpha.add(a);
      b = math.sqrt(_dot(w, w));
      if (b < 1e-12 * a.abs() || m == steps - 1) break;
      beta.add(b);
      previous = q;
      q = Float64List(n);
      for (var i = 0; i < n; i++) {
        q[i] = w[i] / b;
      }
    }
    final size = alpha.length;
    final (values, vectors) = _tridiagonalEigen(alpha, beta, size);
    // Highest of L⁻¹ first, which is lowest of L.
    final order = List<int>.generate(size, (i) => i)
      ..sort((x, y) => values[y].compareTo(values[x]));
    final modes = <Float64List>[];
    final k2 = <double>[];
    final scale = 1.0 / math.sqrt(grid.cell2);
    for (final r in order) {
      if (values[r] <= 0.0) continue;
      final lambda = 1.0 / values[r];
      final shape = Float64List(n);
      for (var j = 0; j < size; j++) {
        final weight = vectors[j * size + r];
        final v = basis[j];
        for (var i = 0; i < n; i++) {
          shape[i] += weight * v[i];
        }
      }
      _normalise(shape);
      for (var i = 0; i < n; i++) {
        shape[i] *= scale;
      }
      modes.add(shape);
      k2.add(lambda);
      if (modes.length == count) break;
    }
    return (modes, Float64List.fromList(k2));
  }

  static double _dot(Float64List a, Float64List b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  static void _normalise(Float64List a) {
    final l = math.sqrt(_dot(a, a));
    if (l == 0.0) return;
    for (var i = 0; i < a.length; i++) {
      a[i] /= l;
    }
  }

  static void _removeMean(Float64List a) {
    var mean = 0.0;
    for (final x in a) {
      mean += x;
    }
    mean /= a.length;
    for (var i = 0; i < a.length; i++) {
      a[i] -= mean;
    }
  }

  /// The eigenvalues and eigenvectors (column r of the row-major matrix) of
  /// the symmetric tridiagonal matrix with [diagonal] and [off] — the
  /// implicit QL method with Wilkinson shifts.
  static (Float64List, Float64List) _tridiagonalEigen(
    List<double> diagonal,
    List<double> off,
    int n,
  ) {
    final d = Float64List.fromList(diagonal);
    final e = Float64List(n);
    for (var i = 0; i < n - 1 && i < off.length; i++) {
      e[i] = off[i];
    }
    final z = Float64List(n * n);
    for (var i = 0; i < n; i++) {
      z[i * n + i] = 1.0;
    }
    for (var l = 0; l < n; l++) {
      var iterations = 0;
      while (true) {
        var m = l;
        for (; m < n - 1; m++) {
          final dd = d[m].abs() + d[m + 1].abs();
          if (e[m].abs() <= 1e-15 * dd) break;
        }
        if (m == l) break;
        if (++iterations > 60) break;
        var g = (d[l + 1] - d[l]) / (2.0 * e[l]);
        var r = _hypot(g, 1.0);
        g = d[m] - d[l] + e[l] / (g + (g >= 0 ? r.abs() : -r.abs()));
        var s = 1.0;
        var c = 1.0;
        var p = 0.0;
        var i = m - 1;
        for (; i >= l; i--) {
          var f = s * e[i];
          final b = c * e[i];
          r = _hypot(f, g);
          e[i + 1] = r;
          if (r == 0.0) {
            d[i + 1] -= p;
            e[m] = 0.0;
            break;
          }
          s = f / r;
          c = g / r;
          g = d[i + 1] - p;
          r = (d[i] - g) * s + 2.0 * c * b;
          p = s * r;
          d[i + 1] = g + p;
          g = c * r - b;
          for (var k = 0; k < n; k++) {
            f = z[k * n + i + 1];
            z[k * n + i + 1] = s * z[k * n + i] + c * f;
            z[k * n + i] = c * z[k * n + i] - s * f;
          }
        }
        if (r == 0.0 && i >= l) continue;
        d[l] -= p;
        e[l] = g;
        e[m] = 0.0;
      }
    }
    return (d, z);
  }

  static double _hypot(double a, double b) => math.sqrt(a * a + b * b);
}

/// A square grid laid over a plane's cut through a vessel: the cells whose
/// middles are inside, and which of their four neighbours are too.
final class _Grid {
  _Grid._({
    required this.up,
    required this.height,
    required this.origin,
    required this.e1,
    required this.e2,
    required this.cell,
    required this.u0,
    required this.v0,
    required this.columns,
    required this.rows,
    required this.index,
    required this.cellsU,
    required this.cellsV,
    required this.neighbours,
  });

  factory _Grid.cut(VesselShape shape, Vector3 up, double height, int cells) {
    final n = up.normalized();
    final helper = n.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1);
    final e1 = (helper - n * n.dot(helper))..normalize();
    final e2 = n.cross(e1);
    final origin = n * height;
    final s1 = shape.span(e1);
    final s2 = shape.span(e2);
    final cell = math.max(s1.high - s1.low, s2.high - s2.low) / cells;
    final columns = math.max(1, ((s1.high - s1.low) / cell).ceil());
    final rows = math.max(1, ((s2.high - s2.low) / cell).ceil());
    final index = Int32List(columns * rows)..fillRange(0, columns * rows, -1);
    final us = <double>[];
    final vs = <double>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final u = s1.low + (c + 0.5) * cell;
        final v = s2.low + (r + 0.5) * cell;
        if (shape.contains(origin + e1 * u + e2 * v)) {
          index[r * columns + c] = us.length;
          us.add(u);
          vs.add(v);
        }
      }
    }
    final neighbours = <List<int>>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        if (index[r * columns + c] < 0) continue;
        neighbours.add([
          for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)])
            if (c + dc >= 0 &&
                c + dc < columns &&
                r + dr >= 0 &&
                r + dr < rows &&
                index[(r + dr) * columns + c + dc] >= 0)
              index[(r + dr) * columns + c + dc],
        ]);
      }
    }
    return _Grid._(
      up: n,
      height: height,
      origin: origin,
      e1: e1,
      e2: e2,
      cell: cell,
      u0: s1.low,
      v0: s2.low,
      columns: columns,
      rows: rows,
      index: index,
      cellsU: Float64List.fromList(us),
      cellsV: Float64List.fromList(vs),
      neighbours: neighbours,
    );
  }

  final Vector3 up;
  final double height;
  final Vector3 origin;
  final Vector3 e1;
  final Vector3 e2;
  final double cell;
  final double u0;
  final double v0;
  final int columns;
  final int rows;
  final Int32List index;
  final Float64List cellsU;
  final Float64List cellsV;
  final List<List<int>> neighbours;

  int get count => cellsU.length;

  /// The same cells on the plane `up · p = height`: a plane that has hardly
  /// moved cuts the vessel in hardly another outline.
  _Grid movedTo(Vector3 up, double height) {
    final n = up.normalized();
    final helper = n.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1);
    final f1 = (helper - n * n.dot(helper))..normalize();
    return _Grid._(
      up: n,
      height: height,
      origin: n * height,
      e1: f1,
      e2: n.cross(f1),
      cell: cell,
      u0: u0,
      v0: v0,
      columns: columns,
      rows: rows,
      index: index,
      cellsU: cellsU,
      cellsV: cellsV,
      neighbours: neighbours,
    );
  }

  double get cell2 => cell * cell;

  /// The middle of cell [i], on the plane.
  Vector3 point(int i) => origin + e1 * cellsU[i] + e2 * cellsV[i];

  /// [values] at [point] seen square to the plane: bilinear between the
  /// cells round it that are inside, the nearest such when none are.
  double sample(Float64List values, Vector3 point) {
    final d = point - origin;
    final u = (e1.dot(d) - u0) / cell - 0.5;
    final v = (e2.dot(d) - v0) / cell - 0.5;
    final c0 = u.floor();
    final r0 = v.floor();
    final fu = u - c0;
    final fv = v - r0;
    var sum = 0.0;
    var weight = 0.0;
    for (final (dc, dr, w) in [
      (0, 0, (1 - fu) * (1 - fv)),
      (1, 0, fu * (1 - fv)),
      (0, 1, (1 - fu) * fv),
      (1, 1, fu * fv),
    ]) {
      final c = c0 + dc;
      final r = r0 + dr;
      if (c < 0 || c >= columns || r < 0 || r >= rows) continue;
      final i = index[r * columns + c];
      if (i < 0) continue;
      sum += values[i] * w;
      weight += w;
    }
    if (weight > 1e-9) return sum / weight;
    // Outside every cell: the nearest one inside, as the wall's own value.
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < count; i++) {
      final du = cellsU[i] - (u + 0.5) * cell - u0;
      final dv = cellsV[i] - (v + 0.5) * cell - v0;
      final dd = du * du + dv * dv;
      if (dd < bestD) {
        bestD = dd;
        best = i;
      }
    }
    return best < 0 ? 0.0 : values[best];
  }
}
