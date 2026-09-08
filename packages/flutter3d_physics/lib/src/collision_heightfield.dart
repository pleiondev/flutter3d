/// A part of `collision_shape.dart` — see the seal, there.
part of 'collision_shape.dart';

/// Ground as a grid of sampled heights: the fifth shape, and the first one that
/// is not convex.
///
/// **Why it could not simply be a sixth wedge.** The four shapes before this
/// one are each a single convex solid, and that is what let every query in
/// `CollisionWorld` be one walk over one set of planes. A field of samples is
/// not one solid and no set of planes describes it: two triangles meeting along
/// a ridge are a shape with a dent in it, and the intersection of half-spaces
/// can only ever be convex. So this shape answers a different question:
/// [partsIn] hands back the convex pieces that lie near what is being asked
/// about, and the walk runs once per piece.
///
/// **The pieces are prisms, not triangles.** A triangle is a surface with no
/// inside, and the Minkowski trick every sweep here rests on needs a solid to
/// grow. Each triangle is therefore extended straight down, past the field's
/// lowest sample by its [thickness], which makes a convex solid of five faces:
/// the sloping top, which is the ground a body stands on, a floor underneath
/// the whole field, and three vertical sides.
///
/// ## The seams, which are the whole difficulty
///
/// Two of those three vertical sides are usually **not surfaces at all**. They
/// are where this prism meets the next one, and the ground continues straight
/// through them. A body walking across a field meets one every metre, and a
/// sweep that reports them stops the body dead against an invisible wall or
/// bounces it into the air — the classic failure of every triangle-soup
/// collider, and the one this file was written around rather than into.
///
/// [partSeams] is the answer: each part says which of its planes face another
/// part of the same field, and [CollisionWorld] refuses to report a contact on
/// one. Nothing is lost by refusing, because a heightfield has no vertical
/// walls to begin with — a cliff in a field of samples is a very steep
/// triangle, and the body is stopped by that triangle's *top* face, which is
/// real.
///
/// The field's outer rim is not a seam and its faces stay, but they are not a
/// fence: a body resting the width of a skin above the surface is outside every
/// prism, so it walks over the side and falls. **Measured, not assumed** — the
/// ground simply ends where its samples do, and a game that needs an edge puts
/// one there.
///
/// ## The surface is triangles, so the answers are too
///
/// Four samples make a quad, and a quad is not flat unless its corners happen
/// to agree. The split is `(0,0)–(1,1)` — the corner nearest the field's origin
/// joined to the one furthest — because a split has to be one decision made in
/// one place or two pieces of code describe two different surfaces. That is the
/// same rule, and the same diagonal, that the level format's own field of
/// heights follows, so a body stands on the ground that is drawn.
///
/// ## Where the samples come from
///
/// **Here, and copied in.** The simulation has a field of heights of its own
/// and it is the one a level document carries — but the simulation depends on
/// this package, so this package cannot look at it without making a circle out
/// of a line. The samples are therefore handed over: a caller that has a level
/// field builds one of these from the same `Float32List`, which is a copy of
/// the same bits rather than a second rounding of them, and the two describe
/// the same surface because they split the quad the same way.
final class CollisionHeightfield extends CollisionShape {
  /// Builds a field from [heights], row-major, `columns * rows` of them.
  ///
  /// The samples are read once, here, for [lowest] and [highest]: the shape's
  /// bounds are a property of the numbers, and a field whose heights changed
  /// under it would be indexed in cells it no longer occupies.
  CollisionHeightfield({
    required this.columns,
    required this.rows,
    required this.cellSize,
    required Float32List heights,
    double? thickness,
  }) : assert(columns > 1 && rows > 1, 'a field of one sample has no surface'),
       assert(cellSize > 0.0, 'a cell of no width has no place to stand'),
       assert(
         heights.length == columns * rows,
         'the field is columns * rows samples and nothing else',
       ),
       assert(thickness == null || thickness > 0.0),
       _heights = heights,
       lowest = _least(heights),
       highest = _most(heights),
       thickness = thickness ?? cellSize;

  /// How far below its lowest sample the ground is solid, in metres.
  ///
  /// **A surface has no inside, and the sweep needs one.** Each triangle is
  /// turned into a solid by extending it downwards, and a solid of no depth is
  /// no solid at all: a perfectly level field — which is most of the ground in
  /// most games — would be a set of prisms whose floor is their own ceiling,
  /// and a body would fall through it because there was never anything there to
  /// enter.
  ///
  /// It is therefore a real distance and it means something: a body that gets
  /// *under* the ground by more than this is beneath the world and stays there.
  /// One cell by default, which is the same scale as the ground's own
  /// resolution and far more than a step of a falling body covers.
  final double thickness;

  /// Samples along +X.
  final int columns;

  /// Samples along +Z.
  final int rows;

  /// Metres between neighbouring samples, the same along both axes.
  final double cellSize;

  final Float32List _heights;

  /// The lowest and highest sample, which are what the bounds are made of.
  final double lowest;
  final double highest;

  /// How far the field reaches along +X and +Z, in metres.
  double get width => (columns - 1) * cellSize;
  double get depth => (rows - 1) * cellSize;

  /// The height at sample [column], [row], in the field's own numbers.
  double sample(int column, int row) => _heights[row * columns + column];

  /// **Centred on the collider's position, like every other shape.**
  ///
  /// A field is naturally described from a corner, and describing it that way
  /// here would have been wrong in a way nothing would say out loud: the
  /// broadphase indexes a collider by its centre and its half-extents, so a
  /// shape whose solid sits somewhere else is a shape the grid hands to the
  /// wrong queries. The corner is therefore derived from the centre — see
  /// [_baseX] — and a caller places the ground by its middle.
  ///
  /// The [thickness] is counted **both ways** rather than only downwards, where
  /// the solid actually is. That leaves a little slack above the highest hill
  /// and buys a symmetric box, so a caller placing the ground puts the middle
  /// of its *surface* at the position it chose rather than the middle of a
  /// solid whose depth it would have to think about. Slack in a broadphase box
  /// costs one narrow test that answers no.
  @override
  Vector3 get boundsHalfExtents =>
      Vector3(width * 0.5, (highest - lowest) * 0.5 + thickness, depth * 0.5);

  /// Where sample `(0, 0)` sits when the shape is centred at [position].
  double _baseX(Vector3 position) => position.x - width * 0.5;
  double _baseZ(Vector3 position) => position.z - depth * 0.5;

  /// What to add to a stored sample to get a world height.
  double _baseY(Vector3 position) => position.y - (highest + lowest) * 0.5;

  /// The height of the drawn surface under `(x, z)`, in world space.
  ///
  /// Outside the field this is the nearest edge's height rather than a throw or
  /// a nought, for the reason the level format's field gives: a body walking
  /// off the map should meet the edge it can see, and a zero here is a cliff to
  /// the origin plane that exists in no picture.
  double heightAt(Vector3 position, double x, double z) {
    final u = (x - _baseX(position)) / cellSize;
    final v = (z - _baseZ(position)) / cellSize;
    final column = u.floor().clamp(0, columns - 2);
    final row = v.floor().clamp(0, rows - 2);
    final du = (u - column).clamp(0.0, 1.0);
    final dv = (v - row).clamp(0.0, 1.0);

    final h00 = sample(column, row);
    final h10 = sample(column + 1, row);
    final h01 = sample(column, row + 1);
    final h11 = sample(column + 1, row + 1);

    final local = du >= dv
        ? h00 + (h10 - h00) * du + (h11 - h10) * dv
        : h00 + (h11 - h01) * du + (h01 - h00) * dv;
    return _baseY(position) + local;
  }

  // MARK: - The convex pieces

  /// How many cells across and along the field has.
  int get _cellsX => columns - 1;
  int get _cellsZ => rows - 1;

  @override
  int get partPlaneCount => 5;

  @override
  int partsIn(Vector3 position, Vector3 min, Vector3 max, Int32List out) {
    final baseX = _baseX(position);
    final baseZ = _baseZ(position);
    final baseY = _baseY(position);
    // Nothing at all when the box misses the field: the caller then walks no
    // parts rather than walking the nearest one, which is the difference
    // between ground that ends and ground that follows you.
    if (max.x < baseX || min.x > baseX + width) return 0;
    if (max.z < baseZ || min.z > baseZ + depth) return 0;
    if (max.y < baseY + lowest - thickness || min.y > baseY + highest) return 0;

    final fromColumn = ((min.x - baseX) / cellSize).floor().clamp(
      0,
      _cellsX - 1,
    );
    final toColumn = ((max.x - baseX) / cellSize).floor().clamp(0, _cellsX - 1);
    final fromRow = ((min.z - baseZ) / cellSize).floor().clamp(0, _cellsZ - 1);
    final toRow = ((max.z - baseZ) / cellSize).floor().clamp(0, _cellsZ - 1);

    var written = 0;
    for (var row = fromRow; row <= toRow; row++) {
      for (var column = fromColumn; column <= toColumn; column++) {
        final cell = (row * _cellsX + column) * 2;
        // Both triangles of the cell, and the count is returned whether or not
        // the buffer could hold them — a caller that asked with too small a
        // list resizes and asks again rather than quietly colliding with half
        // the ground.
        if (written < out.length) out[written] = cell;
        written++;
        if (written < out.length) out[written] = cell + 1;
        written++;
      }
    }
    return written;
  }

  /// The five planes of one triangle's prism, grown to hold [mover].
  ///
  /// Order matters and is relied on by [partSeams]: the sloping top, the floor
  /// under the field, then the three vertical sides in the order the triangle's
  /// edges are walked.
  @override
  int partPlanes(
    int part,
    Vector3 position,
    CollisionShape mover,
    Float64List out,
  ) {
    final cell = part >> 1;
    final upper = (part & 1) == 1;
    final column = cell % _cellsX;
    final row = cell ~/ _cellsX;

    final baseX = _baseX(position) + column * cellSize;
    final baseZ = _baseZ(position) + row * cellSize;
    final baseY = _baseY(position);
    final s = cellSize;

    final h00 = baseY + sample(column, row);
    final h10 = baseY + sample(column + 1, row);
    final h01 = baseY + sample(column, row + 1);
    final h11 = baseY + sample(column + 1, row + 1);

    // The three corners, in the order the diagonal `(0,0)–(1,1)` leaves them.
    // The lower triangle is the half where the distance along X is the greater.
    final ax = baseX, az = baseZ, ay = h00;
    final double bx, by, bz, cx, cy, cz;
    if (upper) {
      bx = baseX + s;
      by = h11;
      bz = baseZ + s;
      cx = baseX;
      cy = h01;
      cz = baseZ + s;
    } else {
      bx = baseX + s;
      by = h10;
      bz = baseZ;
      cx = baseX + s;
      cy = h11;
      cz = baseZ + s;
    }

    var i = 0;
    void plane(double nx, double ny, double nz, double through) {
      out[i] = nx;
      out[i + 1] = ny;
      out[i + 2] = nz;
      // Grown by the moving body's own reach along this normal, which is the
      // Minkowski sum in closed form — see [CollisionShape.partPlanes].
      out[i + 3] = through + mover.supportAlong(nx, ny, nz);
      i += 4;
    }

    // The sloping top: the triangle's own plane, facing up. Flat across the
    // triangle rather than smoothed between neighbours, because that is the
    // face the ground is drawn as and a body has to rest on the one it can see.
    var nx = (by - ay) * (cz - az) - (bz - az) * (cy - ay);
    var ny = (bz - az) * (cx - ax) - (bx - ax) * (cz - az);
    var nz = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    if (ny < 0.0) {
      nx = -nx;
      ny = -ny;
      nz = -nz;
    }
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    nx /= length;
    ny /= length;
    nz /= length;
    plane(nx, ny, nz, nx * ax + ny * ay + nz * az);

    // The floor under the whole field, so the prism is a solid and not a
    // surface with no inside. A body under the ground meets this, which is the
    // honest answer for a surface with an underside. See [thickness].
    plane(0.0, -1.0, 0.0, -(baseY + lowest - thickness));

    _side(ax, az, bx, bz, cx, cz, plane);
    _side(bx, bz, cx, cz, ax, az, plane);
    _side(cx, cz, ax, az, bx, bz, plane);
    return 5;
  }

  /// The vertical plane through the edge `(x0, z0)–(x1, z1)`, facing away from
  /// the third corner.
  static void _side(
    double x0,
    double z0,
    double x1,
    double z1,
    double otherX,
    double otherZ,
    void Function(double, double, double, double) plane,
  ) {
    var nx = z1 - z0;
    var nz = -(x1 - x0);
    final length = math.sqrt(nx * nx + nz * nz);
    nx /= length;
    nz /= length;
    // Outward means the remaining corner is behind it.
    if (nx * (otherX - x0) + nz * (otherZ - z0) > 0.0) {
      nx = -nx;
      nz = -nz;
    }
    plane(nx, 0.0, nz, nx * x0 + nz * z0);
  }

  /// Which of [partPlanes]' five planes are seams rather than surfaces.
  ///
  /// The diagonal always is — it is where the cell's two triangles meet. The
  /// other two sides are seams when the cell next door exists and are the
  /// field's own rim when it does not. The top and the floor never are.
  ///
  /// **This is the method that decides whether a body can walk.** Without it a
  /// field of ground is a field of invisible walls one cell apart; the tests in
  /// `heightfield_test.dart` under "the seams between triangles" are what say
  /// so, and they fail loudly when this returns nothing.
  @override
  int partSeams(int part) {
    final cell = part >> 1;
    final upper = (part & 1) == 1;
    final column = cell % _cellsX;
    final row = cell ~/ _cellsX;

    // Bit two is the edge A–B, bit three B–C, bit four C–A, matching the order
    // the sides are written in.
    if (upper) {
      // A–B is the diagonal; B–C is the cell's far side along Z; C–A its near
      // side along X.
      return (1 << 2) |
          (row < _cellsZ - 1 ? 1 << 3 : 0) |
          (column > 0 ? 1 << 4 : 0);
    }
    // A–B is the near side along Z, B–C the far side along X, C–A the diagonal.
    return (row > 0 ? 1 << 2 : 0) |
        (column < _cellsX - 1 ? 1 << 3 : 0) |
        (1 << 4);
  }

  /// **No planes at all**, and that is the honest answer.
  ///
  /// A field of triangles is not one convex solid, so there is no set of planes
  /// whose intersection is it. Writing the bounding box here would make the
  /// ground a block of stone with the hills inside it, and nothing in a test
  /// would say so — the same trap [CollisionShape.expandedPlanes] was made
  /// abstract to avoid. Returning none means a caller that walks this shape as
  /// a single solid finds nothing, which is a miss and not a wrong answer;
  /// every query in [CollisionWorld] goes through [partsIn] instead.
  @override
  int get expandedPlaneCount => 0;

  @override
  int expandedPlanes(Vector3 position, Vector3 half, Float64List out) => 0;

  // MARK: - Overlap

  @override
  bool overlaps(
    Vector3 position,
    CollisionShape other,
    Vector3 otherPosition,
  ) => other.overlapsHeightfield(otherPosition, this, position);

  /// Whether [point] is under the surface at [position], allowing [margin].
  ///
  /// Read off the drawn surface rather than out of the prisms, because the
  /// question "is this inside the ground" has an exact answer for a field of
  /// heights and the prisms only approximate it near a seam.
  bool containsPoint(Vector3 position, Vector3 point, {double margin = 0.0}) {
    // Off the field is off the ground. [heightAt] answers with the nearest edge
    // there, which is what a body walking to the rim wants and the wrong answer
    // to this question: without the guard the ground would reach out past its
    // own bounds for ever.
    final u = point.x - _baseX(position);
    final v = point.z - _baseZ(position);
    if (u < -margin || v < -margin) return false;
    if (u > width + margin || v > depth + margin) return false;
    return point.y - margin <= heightAt(position, point.x, point.z) &&
        point.y + margin >= _baseY(position) + lowest - thickness;
  }

  @override
  bool overlapsBox(Vector3 position, CollisionBox box, Vector3 boxPosition) {
    // The box against each prism under its footprint, grown by the box — the
    // same Minkowski sum the sweep uses, asked at one instant. Conservative at
    // a triangle's edges for the reason [CollisionWedge.overlapsBox] gives, and
    // for the same price: a pickup resting in a crease is collected early by
    // the width of a corner.
    final scratch = Float64List(20);
    final parts = _partsAround(position, boxPosition, box.halfExtents);
    for (final part in parts) {
      final count = partPlanes(part, position, box, scratch);
      var inside = true;
      for (var i = 0; i < count && inside; i++) {
        final base = i * 4;
        inside =
            scratch[base + 3] -
                (scratch[base] * boxPosition.x +
                    scratch[base + 1] * boxPosition.y +
                    scratch[base + 2] * boxPosition.z) >
            0.0;
      }
      if (inside) return true;
    }
    return false;
  }

  @override
  bool overlapsSphere(
    Vector3 position,
    CollisionSphere sphere,
    Vector3 spherePosition,
  ) => containsPoint(position, spherePosition, margin: sphere.radius);

  @override
  bool overlapsCapsule(
    Vector3 position,
    CollisionCapsule capsule,
    Vector3 capsulePosition,
  ) {
    // The lowest point of the capsule's segment, which is the one that reaches
    // the ground first. An upright capsule over a field needs no other probe:
    // the surface is a height function, so nothing above the feet can be under
    // the ground while the feet are not.
    final feet = Vector3(
      capsulePosition.x,
      capsulePosition.y - capsule.halfHeight,
      capsulePosition.z,
    );
    return containsPoint(position, feet, margin: capsule.radius);
  }

  @override
  bool overlapsWedge(
    Vector3 position,
    CollisionWedge wedge,
    Vector3 wedgePosition,
  ) =>
      // A ramp standing on a hill, which is a question no level asks: both are
      // ground, and ground does not move. The wedge's centre against the
      // surface, said out loud rather than dressed up.
      containsPoint(position, wedgePosition, margin: wedge.halfExtents.y);

  @override
  bool overlapsHeightfield(
    Vector3 position,
    CollisionHeightfield field,
    Vector3 fieldPosition,
  ) =>
      // Two fields of ground against each other, which is a question with no
      // caller: a level has one piece of ground and it does not move. The
      // bounding boxes, so the answer is cheap and wrong in a direction that
      // reports too much rather than too little.
      (position.x - fieldPosition.x).abs() <
          boundsHalfExtents.x + field.boundsHalfExtents.x &&
      (position.y - fieldPosition.y).abs() <
          boundsHalfExtents.y + field.boundsHalfExtents.y &&
      (position.z - fieldPosition.z).abs() <
          boundsHalfExtents.z + field.boundsHalfExtents.z;

  /// The parts under a box of [half] at [at], as a plain list.
  ///
  /// For the overlap tests, which are asked once per pair per step rather than
  /// several times inside a sweep — the allocation is affordable there and the
  /// hot path in [CollisionWorld] uses [partsIn] against its own buffer.
  List<int> _partsAround(Vector3 position, Vector3 at, Vector3 half) {
    final min = Vector3(at.x - half.x, at.y - half.y, at.z - half.z);
    final max = Vector3(at.x + half.x, at.y + half.y, at.z + half.z);
    final probe = Int32List(32);
    final count = partsIn(position, min, max, probe);
    if (count <= probe.length) {
      return <int>[for (var i = 0; i < count; i++) probe[i]];
    }
    final wide = Int32List(count);
    partsIn(position, min, max, wide);
    return wide.toList();
  }

  // MARK: - Rays

  /// Walks the ray cell by cell and meets the first triangle it crosses.
  ///
  /// **Cell by cell rather than over the ray's bounding box**, for the reason
  /// the world's own ray walk gives: a shot fired diagonally across a field has
  /// a bounding box covering most of it, and testing every triangle in that box
  /// is the whole field for a ray that touches four of it.
  @override
  double raycast(
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Vector3 outNormal,
  ) {
    // Clipped to the field's bounds first, so the walk starts on the ground
    // rather than wherever the shot was fired from.
    final half = boundsHalfExtents;
    var enter = 0.0;
    var leave = maxDistance;
    for (var axis = 0; axis < 3; axis++) {
      final lo = position[axis] - half[axis];
      final hi = position[axis] + half[axis];
      final o = origin[axis];
      final d = direction[axis];
      if (d.abs() < Nearly.parallel) {
        if (o < lo || o > hi) return -1.0;
        continue;
      }
      final inverse = 1.0 / d;
      var near = (lo - o) * inverse;
      var far = (hi - o) * inverse;
      if (near > far) {
        final swap = near;
        near = far;
        far = swap;
      }
      if (near > enter) enter = near;
      if (far < leave) leave = far;
      if (enter > leave) return -1.0;
    }

    final baseX = _baseX(position);
    final baseZ = _baseZ(position);
    // A hair inside, so a ray entering exactly on a boundary starts in the cell
    // it is heading into rather than in the one behind it.
    final startX = origin.x + direction.x * enter - baseX;
    final startZ = origin.z + direction.z * enter - baseZ;
    var column = (startX / cellSize).floor().clamp(0, _cellsX - 1);
    var row = (startZ / cellSize).floor().clamp(0, _cellsZ - 1);

    final stepColumn = direction.x > 0.0 ? 1 : -1;
    final stepRow = direction.z > 0.0 ? 1 : -1;
    // How far along the ray one whole cell is, and how far to the next
    // boundary. Infinite when the ray does not move along that axis at all,
    // which keeps the comparison below from ever choosing it.
    final acrossX = direction.x.abs() < Nearly.parallel
        ? double.infinity
        : cellSize / direction.x.abs();
    final acrossZ = direction.z.abs() < Nearly.parallel
        ? double.infinity
        : cellSize / direction.z.abs();
    var nextX = acrossX.isInfinite
        ? double.infinity
        : enter +
              ((direction.x > 0.0
                          ? (column + 1) * cellSize - startX
                          : startX - column * cellSize) /
                      direction.x.abs())
                  .clamp(0.0, double.infinity);
    var nextZ = acrossZ.isInfinite
        ? double.infinity
        : enter +
              ((direction.z > 0.0
                          ? (row + 1) * cellSize - startZ
                          : startZ - row * cellSize) /
                      direction.z.abs())
                  .clamp(0.0, double.infinity);

    final scratch = Float64List(20);
    while (true) {
      for (var t = 0; t < 2; t++) {
        final part = (row * _cellsX + column) * 2 + t;
        final hit = _raycastPart(
          part,
          position,
          origin,
          direction,
          maxDistance,
          scratch,
          outNormal,
        );
        if (hit >= 0.0) return hit;
      }
      if (nextX < nextZ) {
        if (nextX > leave) return -1.0;
        column += stepColumn;
        if (column < 0 || column >= _cellsX) return -1.0;
        nextX += acrossX;
      } else {
        if (nextZ > leave) return -1.0;
        row += stepRow;
        if (row < 0 || row >= _cellsZ) return -1.0;
        nextZ += acrossZ;
      }
    }
  }

  /// The ray against one triangle, as a point against its prism.
  ///
  /// The prism rather than the triangle, so the arithmetic is the same plane
  /// walk everything else here does. The floor and the seams are skipped: a ray
  /// that meets the underside of the ground or the join between two triangles
  /// has met nothing a shot can hit.
  double _raycastPart(
    int part,
    Vector3 position,
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    Float64List scratch,
    Vector3 outNormal,
  ) {
    final count = partPlanes(part, position, _noReach, scratch);
    final seams = partSeams(part) | (1 << 1);
    var near = 0.0;
    var far = maxDistance;
    var entering = -1;

    for (var i = 0; i < count; i++) {
      final base = i * 4;
      final nx = scratch[base];
      final ny = scratch[base + 1];
      final nz = scratch[base + 2];
      final approach = nx * direction.x + ny * direction.y + nz * direction.z;
      final outside =
          nx * origin.x + ny * origin.y + nz * origin.z - scratch[base + 3];

      if (approach.abs() < Nearly.parallel) {
        if (outside > 0.0) return -1.0;
        continue;
      }
      final t = -outside / approach;
      if (approach < 0.0) {
        if (t > near) {
          near = t;
          entering = i;
        }
      } else if (t < far) {
        far = t;
      }
      if (near > far) return -1.0;
    }

    if (entering < 0 || near > maxDistance) return -1.0;
    if ((seams & (1 << entering)) != 0) return -1.0;
    final base = entering * 4;
    outNormal.setValues(scratch[base], scratch[base + 1], scratch[base + 2]);
    return near;
  }
}

/// A body of no size at all, for the queries that ask about a point.
///
/// A shape rather than a zero vector because growth is a question about the
/// thing being moved — see [CollisionShape.supportAlong] — and a point is a
/// thing that reaches nowhere.
final CollisionBox _noReach = CollisionBox(Vector3.zero());

double _least(Float32List values) {
  var least = values[0].toDouble();
  for (var i = 1; i < values.length; i++) {
    if (values[i] < least) least = values[i].toDouble();
  }
  return least;
}

double _most(Float32List values) {
  var most = values[0].toDouble();
  for (var i = 1; i < values.length; i++) {
    if (values[i] > most) most = values[i].toDouble();
  }
  return most;
}
