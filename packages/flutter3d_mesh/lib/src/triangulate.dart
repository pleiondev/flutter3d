/// Cutting a face of any valency into triangles.
///
/// **A fan is what the spike did, and it is wrong for exactly the faces a
/// modeller makes.** Fanning from the first vertex works for a convex face and
/// puts triangles outside the outline of every concave one — an L-shaped
/// six-gon fanned from the wrong corner covers the notch. That is not a
/// rendering artefact to live with: the same triangles are what a raycast hits,
/// what an area is measured over, and what an exporter writes.
///
/// So there are three cases, in the order they are cheap:
///
///   * **A triangle** is already one.
///   * **A quad** is a choice between two diagonals, decided by which one keeps
///     both halves on the same side of the face — the one thing a bowtie or a
///     dented quad gets wrong — and, where both are inside, by which is
///     shorter, since a short diagonal makes fatter triangles and a fat
///     triangle interpolates and rasterises better.
///   * **Anything larger** is ear clipping in the plane the face's own Newell
///     normal defines. Quadratic in the corners, which is the right complexity
///     for faces with five to a few dozen corners; a face with a thousand is a
///     face something else generated, and `mesh-71`'s unwrap is where those
///     get looked at.
///
/// **A face that cannot be cut is fanned, and says so.** Self-intersecting
/// outlines exist in files people have; refusing them loses the model, and
/// pretending they were fine loses the report. So the fallback is the naive
/// answer plus a flag the caller can put in front of somebody.
library;

import 'package:vector_math/vector_math.dart';

/// Cuts faces into triangles, reusing its own buffers.
///
/// **One object held across calls rather than a function.** Triangulating every
/// face of a 100 000-face mesh through a function that allocates its working
/// lists is 300 000 allocations for arithmetic that touches at most a few dozen
/// numbers at a time — the shape of cost that does not show in a microbenchmark
/// and shows in a garbage collector's pauses while somebody drags a vertex.
final class FaceTriangulator {
  /// Corner positions of the face being cut, projected to two dimensions.
  final List<double> _x = <double>[];
  final List<double> _y = <double>[];

  /// Which corner of the face each of those is, so the output names the
  /// caller's own indices rather than positions in a scratch list.
  final List<int> _corner = <int>[];

  /// Corners still to be cut off, in winding order.
  final List<int> _remaining = <int>[];

  /// Whether the last face fell back to a fan.
  ///
  /// A caller — the conversion to `MeshData`, an exporter, the readiness check
  /// — reads this to report a face that could not be cut properly, which is
  /// what `mesh-27`'s issue list is for.
  bool get fannedLastFace => _fanned;
  bool _fanned = false;

  /// Cuts the polygon given by [points] and calls [emit] with each triangle, as
  /// positions in [points] rather than as coordinates.
  ///
  /// Returns how many triangles were emitted: `points.length - 2` whenever the
  /// outline is a simple polygon, which every face a modeller builds is.
  int triangulate(
    List<Vector3> points,
    void Function(int a, int b, int c) emit,
  ) {
    _fanned = false;
    final count = points.length;
    if (count < 3) return 0;
    if (count == 3) {
      emit(0, 1, 2);
      return 1;
    }

    final normal = _newellNormal(points);
    if (count == 4) return _quad(points, normal, emit);

    _project(points, normal);
    return _earClip(emit);
  }

  /// The face's own plane normal, by Newell's method.
  ///
  /// Newell rather than the cross product of two edges, because three
  /// consecutive corners of a real face are often nearly collinear — a loop cut
  /// leaves them that way — and a cross product there is a normal made of
  /// rounding error pointing anywhere at all.
  Vector3 _newellNormal(List<Vector3> points) {
    final normal = Vector3.zero();
    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final ahead = points[(i + 1) % points.length];
      normal
        ..x += (current.y - ahead.y) * (current.z + ahead.z)
        ..y += (current.z - ahead.z) * (current.x + ahead.x)
        ..z += (current.x - ahead.x) * (current.y + ahead.y);
    }
    final length = normal.length;
    return length == 0
        ? (normal..setValues(0, 1, 0))
        : (normal..scale(1 / length));
  }

  /// Which of the two diagonals to cut a quad along.
  int _quad(
    List<Vector3> points,
    Vector3 normal,
    void Function(int a, int b, int c) emit,
  ) {
    _project(points, normal);

    // A diagonal is usable when both triangles it makes wind the same way as
    // the face. On a dented or bowtie quad exactly one of the two passes, and
    // choosing the other is how a fan puts a triangle outside the outline.
    final a02 = _windsConsistently(0, 1, 2) && _windsConsistently(0, 2, 3);
    final a13 = _windsConsistently(1, 2, 3) && _windsConsistently(1, 3, 0);

    final bool useZeroTwo;
    if (a02 != a13) {
      useZeroTwo = a02;
    } else {
      // Both work, or neither does: take the shorter diagonal, which leaves the
      // fatter pair of triangles — better for interpolation, and better for
      // anything that later asks a triangle for its normal.
      final d02 = points[0].distanceToSquared(points[2]);
      final d13 = points[1].distanceToSquared(points[3]);
      useZeroTwo = d02 <= d13;
      _fanned = !a02 && !a13;
    }

    if (useZeroTwo) {
      emit(0, 1, 2);
      emit(0, 2, 3);
    } else {
      emit(1, 2, 3);
      emit(1, 3, 0);
    }
    return 2;
  }

  /// Flattens the face onto the plane its normal defines, dropping the axis the
  /// normal is most aligned with — the projection that keeps the most area and
  /// costs two array reads per corner.
  void _project(List<Vector3> points, Vector3 normal) {
    _x.clear();
    _y.clear();
    _corner.clear();
    _remaining.clear();

    final ax = normal.x.abs();
    final ay = normal.y.abs();
    final az = normal.z.abs();
    // Which pair of axes survives, and in which order: the order is chosen so
    // that a face wound counter-clockwise around its normal stays
    // counter-clockwise in two dimensions, which every winding test below
    // depends on.
    final int first;
    final int second;
    final bool flip;
    if (ax >= ay && ax >= az) {
      first = 1;
      second = 2;
      flip = normal.x < 0;
    } else if (ay >= az) {
      first = 2;
      second = 0;
      flip = normal.y < 0;
    } else {
      first = 0;
      second = 1;
      flip = normal.z < 0;
    }

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final u = point[first];
      final v = point[second];
      _x.add(flip ? -u : u);
      _y.add(v);
      _corner.add(i);
      _remaining.add(i);
    }
  }

  /// Twice the signed area of the projected triangle: positive when it winds
  /// the same way as the face.
  double _cross(int a, int b, int c) =>
      (_x[b] - _x[a]) * (_y[c] - _y[a]) - (_y[b] - _y[a]) * (_x[c] - _x[a]);

  bool _windsConsistently(int a, int b, int c) => _cross(a, b, c) > 0;

  /// Whether the projected point [p] is inside the triangle `a b c`, edges
  /// included.
  ///
  /// **The boundary counts, and that is the whole of it.** Ask only for the
  /// strict interior and an L-shape's reflex corner — which sits exactly *on*
  /// the diagonal of the ear that would swallow the notch — stops blocking it:
  /// the ear is taken, and the triangles cover a square unit the face does not
  /// have. Measured on the L in `triangulate_test.dart`: three units of area
  /// against four.
  bool _inside(int a, int b, int c, int p) {
    if (p == a || p == b || p == c) return false;
    final d1 = _cross(a, b, p);
    final d2 = _cross(b, c, p);
    final d3 = _cross(c, a, p);
    return d1 >= 0 && d2 >= 0 && d3 >= 0;
  }

  /// Whether the corner at position [at] in [_remaining] turns the wrong way.
  ///
  /// **Only a reflex corner can invalidate an ear**, which is the textbook
  /// filter: a convex corner sitting inside a candidate ear would mean the
  /// outline crosses itself, and this is not the place that finds out. Asking
  /// only these is an optimisation and not a correctness fix — with the second
  /// pass below in place, checking every corner gives the same triangles more
  /// slowly, which is what happens when the filter is taken out and the tests
  /// stay green.
  ///
  /// Strictly the wrong way, so a corner whose two edges are collinear counts
  /// as straight rather than reflex: those are what the second pass exists for.
  bool _isReflex(int at) {
    final count = _remaining.length;
    final previous = _remaining[(at - 1 + count) % count];
    final current = _remaining[at];
    final next = _remaining[(at + 1) % count];
    return _cross(previous, current, next) < 0;
  }

  int _earClip(void Function(int a, int b, int c) emit) {
    var emitted = 0;
    // Each pass round the outline must cut at least one ear, or the outline is
    // not a simple polygon and no amount of looking will find one.
    var guard = _remaining.length * _remaining.length;

    while (_remaining.length > 3) {
      var cut = false;
      // **Two passes, and the second one is not a nicety.** A straight corner —
      // three collinear points, which a comb's base and a loop cut both produce
      // — is neither convex nor reflex: the triangle at it has no area, so it
      // is never an ear by the strict test, and it is never cut. Left standing,
      // it eventually surrounds the outline with corners nothing can remove,
      // and a face that could have been cut properly falls back to a fan.
      //
      // So convex corners go first, and only when none is left does a straight
      // corner get taken with a degenerate triangle. That keeps the count at
      // `n - 2`, keeps every corner in the output — which the conversion needs,
      // one GPU vertex per corner — and covers exactly the same area, since
      // what is emitted has none.
      for (var pass = 0; pass < 2 && !cut; pass++) {
        for (var i = 0; i < _remaining.length; i++) {
          final previous =
              _remaining[(i - 1 + _remaining.length) % _remaining.length];
          final current = _remaining[i];
          final next = _remaining[(i + 1) % _remaining.length];

          final turn = _cross(previous, current, next);
          // A reflex corner is not an ear on either pass: the triangle at it
          // lies outside the face.
          if (pass == 0 ? turn <= 0 : turn != 0) continue;

          if (pass == 0) {
            var clear = true;
            for (var other = 0; other < _remaining.length; other++) {
              if (!_isReflex(other)) continue;
              if (_inside(previous, current, next, _remaining[other])) {
                clear = false;
                break;
              }
            }
            if (!clear) continue;
          }

          emit(_corner[previous], _corner[current], _corner[next]);
          emitted++;
          _remaining.removeAt(i);
          cut = true;
          break;
        }
      }

      if (!cut || --guard < 0) {
        // Nothing left to cut and more than three corners standing: the outline
        // crosses itself, or every corner is collinear. A fan is not right, and
        // it is what there is — with the flag saying so, which is the whole
        // difference between a fallback and a bug.
        _fanned = true;
        for (var i = 1; i + 1 < _remaining.length; i++) {
          emit(
            _corner[_remaining[0]],
            _corner[_remaining[i]],
            _corner[_remaining[i + 1]],
          );
          emitted++;
        }
        return emitted;
      }
    }

    emit(
      _corner[_remaining[0]],
      _corner[_remaining[1]],
      _corner[_remaining[2]],
    );
    return emitted + 1;
  }
}
