/// A part of `collision_shape.dart` — see the seal, there.
part of 'collision_shape.dart';

/// A convex collision volume described by its support function: the one
/// shape a game or a plugin adds of its own.
///
/// **The open door in a sealed hierarchy.** [CollisionShape] stays sealed so a
/// `switch` over the five built-in shapes is checked, and this is the sixth
/// case every such switch now names: whatever a game invents — a cone, a
/// rounded box, a hull read from a model — comes in as a subclass of this.
///
/// ## What a subclass gives
///
/// * [support]: the point of the shape, centred on the origin, furthest along
///   a direction. That one function is enough for every overlap: two convex
///   shapes overlap exactly when the GJK walk over the Minkowski difference
///   of their supports reaches the origin, and every built-in shape answers
///   a support too ([CollisionShape.supportPoint]).
/// * [boundsHalfExtents]: the box the broadphase files it under.
///
/// ## What it gets by default, and may do better
///
/// * Moving through the world ([expandedPlanes]) and rays ([raycast]) take
///   the bounding box, as the box, sphere and capsule do; override with the
///   shape's real faces for a body that slides along them.
/// * Against ground ([overlapsHeightfield]), the field's own prisms grown by
///   this shape's [supportAlong]: as exact as the field is against a box.
/// * Inertia ([inertia]) of its bounding box, solid.
///
/// **Deterministic**: the walk is in doubles, in a fixed order, with a fixed
/// iteration cap, and reads no clock.
abstract base class CustomShape extends CollisionShape {
  const CustomShape();

  /// Writes into [out] the point of this shape, centred on the origin,
  /// furthest along the direction (`dx`, `dy`, `dz`), which need not be of
  /// unit length. Any point of the shape that is furthest will do.
  void support(double dx, double dy, double dz, Vector3 out);

  @override
  void supportPoint(double dx, double dy, double dz, Vector3 out) =>
      support(dx, dy, dz, out);

  @override
  int get expandedPlaneCount => CollisionShape.boundsPlaneCount;

  @override
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out) =>
      boundsExpandedPlanes(position, half, out);

  /// The shape's true reach along a unit direction, from [support].
  @override
  double supportAlong(double nx, double ny, double nz) {
    final point = Vector3.zero();
    support(nx, ny, nz, point);
    return point.x * nx + point.y * ny + point.z * nz;
  }

  /// The inertia of a body of [mass] kilograms shaped like this, about its
  /// centre, in kilogram square metres. By default the solid bounding box's.
  Vector3 inertia(double mass) {
    final h = boundsHalfExtents;
    final third = mass / 3.0;
    return Vector3(
      third * (h.y * h.y + h.z * h.z),
      third * (h.x * h.x + h.z * h.z),
      third * (h.x * h.x + h.y * h.y),
    );
  }

  @override
  bool overlaps(
    Vector3 position,
    CollisionShape other,
    Vector3 otherPosition,
  ) => other.overlapsCustom(otherPosition, this, position);

  @override
  bool overlapsBox(Vector3 position, CollisionBox box, Vector3 boxPosition) =>
      convexOverlap(this, position, box, boxPosition);

  @override
  bool overlapsSphere(
    Vector3 position,
    CollisionSphere sphere,
    Vector3 spherePosition,
  ) => convexOverlap(this, position, sphere, spherePosition);

  @override
  bool overlapsCapsule(
    Vector3 position,
    CollisionCapsule capsule,
    Vector3 capsulePosition,
  ) => convexOverlap(this, position, capsule, capsulePosition);

  @override
  bool overlapsWedge(
    Vector3 position,
    CollisionWedge wedge,
    Vector3 wedgePosition,
  ) => convexOverlap(this, position, wedge, wedgePosition);

  @override
  bool overlapsHeightfield(
    Vector3 position,
    CollisionHeightfield field,
    Vector3 fieldPosition,
  ) {
    // The field's prisms under this shape, each grown by this shape's reach:
    // the centre inside every grown plane of one of them is an overlap. The
    // same Minkowski sum `CollisionHeightfield.overlapsBox` asks.
    final scratch = Float64List(4 * field.partPlaneCount);
    final parts = field._partsAround(
      fieldPosition,
      position,
      boundsHalfExtents,
    );
    for (final part in parts) {
      final count = field.partPlanes(part, fieldPosition, this, scratch);
      var inside = true;
      for (var i = 0; i < count && inside; i++) {
        final base = i * 4;
        inside =
            scratch[base + 3] -
                (scratch[base] * position.x +
                    scratch[base + 1] * position.y +
                    scratch[base + 2] * position.z) >
            0.0;
      }
      if (inside) return true;
    }
    return false;
  }

  @override
  bool overlapsCustom(
    Vector3 position,
    CustomShape custom,
    Vector3 customPosition,
  ) => convexOverlap(this, position, custom, customPosition);

  @override
  double raycast(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  ) => raycastBounds(position, origin, direction, maxDistance, outNormal);
}

/// Whether convex [a] at [aPosition] and convex [b] at [bPosition] overlap,
/// by the GJK walk over the Minkowski difference of their supports.
///
/// **Touching is not overlapping**, as for the built-in pairs: the walk
/// answers true only when the origin is strictly inside the difference, up to
/// the walk's tolerance. A heightfield is not convex and is refused here;
/// [CustomShape.overlapsHeightfield] asks the field's prisms instead.
bool convexOverlap(
  CollisionShape a,
  Vector3 aPosition,
  CollisionShape b,
  Vector3 bPosition,
) {
  assert(
    a is! CollisionHeightfield && b is! CollisionHeightfield,
    'ground is not convex; ask the field',
  );
  final pa = Vector3.zero();
  final pb = Vector3.zero();
  // The support of A − B along d: A's furthest along d less B's furthest
  // along −d, each placed.
  (double, double, double) supportOf(double dx, double dy, double dz) {
    a.supportPoint(dx, dy, dz, pa);
    b.supportPoint(-dx, -dy, -dz, pb);
    return (
      (aPosition.x + pa.x) - (bPosition.x + pb.x),
      (aPosition.y + pa.y) - (bPosition.y + pb.y),
      (aPosition.z + pa.z) - (bPosition.z + pb.z),
    );
  }

  return _Gjk(supportOf).intersects(
    aPosition.x - bPosition.x,
    aPosition.y - bPosition.y,
    aPosition.z - bPosition.z,
  );
}

/// The boolean GJK walk, in doubles.
final class _Gjk {
  _Gjk(this._support);

  final (double, double, double) Function(double, double, double) _support;

  /// Up to four points of the simplex, x y z each, newest last.
  final List<double> _s = List<double>.filled(12, 0.0);
  int _n = 0;
  double _dx = 0.0, _dy = 0.0, _dz = 0.0;

  static const int _maxIterations = 64;
  static const double _epsilon = 1e-12;

  bool intersects(double startX, double startY, double startZ) {
    var dx = startX, dy = startY, dz = startZ;
    if (dx * dx + dy * dy + dz * dz < _epsilon) dx = 1.0;
    var (ax, ay, az) = _support(dx, dy, dz);
    _n = 0;
    _push(ax, ay, az);
    _dx = -ax;
    _dy = -ay;
    _dz = -az;
    for (var i = 0; i < _maxIterations; i++) {
      if (_dx * _dx + _dy * _dy + _dz * _dz < _epsilon) return true;
      (ax, ay, az) = _support(_dx, _dy, _dz);
      if (ax * _dx + ay * _dy + az * _dz <= 0.0) return false;
      _push(ax, ay, az);
      if (_evolve()) return true;
    }
    // Out of iterations only on a degenerate pair at the boundary: touching,
    // which is not overlapping.
    return false;
  }

  void _aim((double, double, double) d) {
    _dx = d.$1;
    _dy = d.$2;
    _dz = d.$3;
  }

  void _push(double x, double y, double z) {
    _s[3 * _n] = x;
    _s[3 * _n + 1] = y;
    _s[3 * _n + 2] = z;
    _n++;
  }

  void _set(List<int> keep) {
    final copy = <double>[
      for (final k in keep) ...<double>[
        _s[3 * k],
        _s[3 * k + 1],
        _s[3 * k + 2],
      ],
    ];
    for (var i = 0; i < copy.length; i++) {
      _s[i] = copy[i];
    }
    _n = keep.length;
  }

  // The simplex's newest point is A; reduce to the feature nearest the
  // origin and point the search at it. True when the origin is enclosed.
  bool _evolve() {
    switch (_n) {
      case 2:
        return _line();
      case 3:
        return _triangle();
      default:
        return _tetrahedron();
    }
  }

  static (double, double, double) _cross(
    double ax,
    double ay,
    double az,
    double bx,
    double by,
    double bz,
  ) => (ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx);

  bool _line() {
    // A newest (index 1), B (index 0).
    final ax = _s[3], ay = _s[4], az = _s[5];
    final bx = _s[0], by = _s[1], bz = _s[2];
    final abx = bx - ax, aby = by - ay, abz = bz - az;
    final aox = -ax, aoy = -ay, aoz = -az;
    if (abx * aox + aby * aoy + abz * aoz > 0.0) {
      // Towards the origin, perpendicular to AB: (AB × AO) × AB.
      final (cx, cy, cz) = _cross(abx, aby, abz, aox, aoy, aoz);
      _aim(_cross(cx, cy, cz, abx, aby, abz));
      if (_dx * _dx + _dy * _dy + _dz * _dz < _epsilon) {
        // The origin is on the segment.
        return true;
      }
    } else {
      _set(const <int>[1]);
      _aim((aox, aoy, aoz));
    }
    return false;
  }

  bool _triangle() {
    // A newest (2), B (1), C (0).
    final ax = _s[6], ay = _s[7], az = _s[8];
    final bx = _s[3], by = _s[4], bz = _s[5];
    final cx = _s[0], cy = _s[1], cz = _s[2];
    final abx = bx - ax, aby = by - ay, abz = bz - az;
    final acx = cx - ax, acy = cy - ay, acz = cz - az;
    final aox = -ax, aoy = -ay, aoz = -az;
    final (nx, ny, nz) = _cross(abx, aby, abz, acx, acy, acz);

    // Outside edge AC?
    final (e1x, e1y, e1z) = _cross(nx, ny, nz, acx, acy, acz);
    if (e1x * aox + e1y * aoy + e1z * aoz > 0.0) {
      if (acx * aox + acy * aoy + acz * aoz > 0.0) {
        _set(const <int>[0, 2]);
        final (tx, ty, tz) = _cross(acx, acy, acz, aox, aoy, aoz);
        _aim(_cross(tx, ty, tz, acx, acy, acz));
        return false;
      }
      return _lineFromAB(abx, aby, abz, aox, aoy, aoz);
    }
    // Outside edge AB?
    final (e2x, e2y, e2z) = _cross(abx, aby, abz, nx, ny, nz);
    if (e2x * aox + e2y * aoy + e2z * aoz > 0.0) {
      return _lineFromAB(abx, aby, abz, aox, aoy, aoz);
    }
    // Above or below the triangle.
    final side = nx * aox + ny * aoy + nz * aoz;
    if (side.abs() < _epsilon) return true;
    if (side > 0.0) {
      _aim((nx, ny, nz));
    } else {
      // Wind the other way so the next point lands on the origin's side.
      _set(const <int>[1, 0, 2]);
      _aim((-nx, -ny, -nz));
    }
    return false;
  }

  bool _lineFromAB(
    double abx,
    double aby,
    double abz,
    double aox,
    double aoy,
    double aoz,
  ) {
    if (abx * aox + aby * aoy + abz * aoz > 0.0) {
      _set(const <int>[1, 2]);
      final (tx, ty, tz) = _cross(abx, aby, abz, aox, aoy, aoz);
      _aim(_cross(tx, ty, tz, abx, aby, abz));
    } else {
      _set(const <int>[2]);
      _aim((aox, aoy, aoz));
    }
    return false;
  }

  bool _tetrahedron() {
    // A newest (3), then B (2), C (1), D (0).
    final ax = _s[9], ay = _s[10], az = _s[11];
    final bx = _s[6], by = _s[7], bz = _s[8];
    final cx = _s[3], cy = _s[4], cz = _s[5];
    final dx = _s[0], dy = _s[1], dz = _s[2];
    final aox = -ax, aoy = -ay, aoz = -az;
    final abx = bx - ax, aby = by - ay, abz = bz - az;
    final acx = cx - ax, acy = cy - ay, acz = cz - az;
    final adx = dx - ax, ady = dy - ay, adz = dz - az;

    // Each face through A, its normal turned away from the fourth point.
    (double, double, double) outward(
      double ux,
      double uy,
      double uz,
      double vx,
      double vy,
      double vz,
      double wx,
      double wy,
      double wz,
    ) {
      var (nx, ny, nz) = _cross(ux, uy, uz, vx, vy, vz);
      if (nx * wx + ny * wy + nz * wz > 0.0) {
        nx = -nx;
        ny = -ny;
        nz = -nz;
      }
      return (nx, ny, nz);
    }

    final faces = <(List<int>, (double, double, double))>[
      (
        const <int>[1, 2, 3],
        outward(abx, aby, abz, acx, acy, acz, adx, ady, adz),
      ),
      (
        const <int>[0, 1, 3],
        outward(acx, acy, acz, adx, ady, adz, abx, aby, abz),
      ),
      (
        const <int>[2, 0, 3],
        outward(adx, ady, adz, abx, aby, abz, acx, acy, acz),
      ),
    ];
    for (final (keep, (nx, ny, nz)) in faces) {
      if (nx * aox + ny * aoy + nz * aoz > 0.0) {
        // The origin is beyond this face: carry on from the triangle.
        _set(keep);
        return _triangle();
      }
    }
    return true;
  }
}
