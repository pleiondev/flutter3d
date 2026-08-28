import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'ray_hit.dart';
import 'spatial_grid.dart';
import 'sweep_hit.dart';
import 'tolerances.dart';

export 'ray_hit.dart';
export 'sweep_hit.dart';

/// Everything in the level that can be collided with, and the queries over it.
///
/// ## One system, not two
///
/// Movement and triggers share this. Sweeping the player against a list of
/// brushes and checking pickups separately would be less code today, and it
/// goes wrong in a specific way: two broadphases with two notions of what
/// overlaps what eventually disagree, and the disagreement reaches the player
/// as a health pack they are standing inside and cannot pick up.
///
/// ## Nothing here is quadratic
///
/// Two grids. Static colliders are indexed once, when they are added; movers —
/// monsters, projectiles, lifts, the player — are re-indexed at the top of
/// every [update]. Every query then costs the number of colliders near it
/// rather than the number in the level, and overlap dispatch costs the number
/// of *reporting* colliders times their local density.
///
/// Rebuilding a grid each step sounds expensive and is not: the cells keep
/// their lists between rebuilds, so after a few frames it allocates nothing and
/// costs one integer append per collider per cell it covers.
final class CollisionWorld {
  CollisionWorld({double cellSize = 4.0})
    : _staticGrid = SpatialGrid(cellSize: cellSize),
      _moverGrid = SpatialGrid(cellSize: cellSize);

  final SpatialGrid _staticGrid;
  final SpatialGrid _moverGrid;

  final List<Collider> _statics = <Collider>[];

  /// Kinematic bodies, triggers, and anything else that moves or reports.
  final List<Collider> _movers = <Collider>[];

  /// Colliders that ask to be told what they touch.
  final List<Collider> _reporters = <Collider>[];

  /// Scratch copy of [_reporters], walked while callbacks run.
  final List<Collider> _reporting = <Collider>[];

  /// Pairs overlapping as of the last [update], so the next one can tell a
  /// start from a continuation from an end.
  Set<int> _overlapping = <int>{};
  Set<int> _nextOverlapping = <int>{};
  final Map<int, Collider> _pairA = <int, Collider>{};
  final Map<int, Collider> _pairB = <int, Collider>{};

  int _nextId = 0;
  final Map<Collider, int> _ids = <Collider, int>{};

  int get colliderCount => _statics.length + _movers.length;
  int get staticCount => _statics.length;
  int get moverCount => _movers.length;

  // Scratch, reused by every query.
  /// Which way a depenetration would push, handed to a [ContactFilter].
  final Vector3 _pushNormal = Vector3.zero();

  final Vector3 _queryMin = Vector3.zero();
  final Vector3 _queryMax = Vector3.zero();
  final Vector3 _candidateNormal = Vector3.zero();

  /// The planes of whichever solid is being tested right now, four doubles
  /// each. Grown if a shape ever asks for more; never shrunk.
  Float64List _planes = Float64List(CollisionShape.boundsPlaneCount * 4);

  /// How far inside a face a point may be and still count as touching it, in
  /// metres.
  ///
  /// A micrometre — [Nearly.still], under the name this file reads it by.
  ///
  /// The alias stays because "touching" is what the ray code is asking, and
  /// the shared constant is where the argument for the number lives.
  static const double _touching = Nearly.still;

  /// What this world calls [collider], or null if it does not hold it.
  ///
  /// A number handed out in the order colliders were added, and the only
  /// stable name a collider has: the object's identity is not one, because
  /// `identityHashCode` differs between two runs of the same program and is
  /// not injective, so two different pairs can answer to it.
  ///
  /// **Exposed for the warm start**, which needs to recognise the same contact
  /// on the next step and was keying on `identityHashCode` — where a collision
  /// seeds a contact with an impulse belonging to a different one, and the pile
  /// behaves differently that one time. The pair key inside this class has
  /// wanted the same thing all along.
  int? idOf(Collider collider) => _ids[collider];

  /// Adds a collider and returns it, so the call can be inlined into a field.
  Collider add(Collider collider) {
    collider.world = this;
    collider.refreshBounds();
    _ids[collider] = _nextId++;

    if (collider.kind == ColliderKind.static) {
      _statics.add(collider);
      _staticGrid.insert(_statics.length - 1, collider.bounds);
    } else {
      _movers.add(collider);
    }
    if (collider.listener != null) _reporters.add(collider);
    return collider;
  }

  /// Keeps the reporter list in step with a collider whose listener changed.
  ///
  /// Called by [Collider]'s listener setter. See the note there: a listener
  /// attached after the collider joined the world is the normal case.
  void refreshReporter(Collider collider) {
    if (collider.listener != null) {
      if (!_reporters.contains(collider)) _reporters.add(collider);
    } else {
      _reporters.remove(collider);
    }
  }

  /// Removes [collider] once the current step's callbacks have finished.
  ///
  /// [remove] renumbers the very lists the overlap dispatch is walking, and the
  /// grid holds indices into them. A pickup collecting itself does exactly that
  /// from inside a callback, which is common enough to deserve a safe door
  /// rather than a warning in a doc comment.
  void removeLater(Collider collider) => _pendingRemoval.add(collider);

  final List<Collider> _pendingRemoval = <Collider>[];

  /// Convenience for level geometry, which is authored as centre plus size.
  Collider addBox(Vector3 centre, Vector3 size, {Object? userData}) => add(
    Collider(
      shape: CollisionBox.size(size),
      position: centre,
      userData: userData,
    ),
  );

  void remove(Collider collider) {
    collider.world = null;
    _reporters.remove(collider);
    _ids.remove(collider);

    // Both grids hold indices into their list, so removing from either
    // renumbers every entry after it. Re-indexing here rather than leaving it
    // until the next update is not tidiness: a query made in between walks the
    // stale index and reads past the end of the list.
    //
    // That is exactly what happened. A collected pickup removed itself, and
    // the occlusion raycast the audio mixer runs later in the same step threw
    // RangeError — every frame, which killed the game loop and with it the
    // input. Nothing had queried between a removal and an update before.
    if (_movers.remove(collider)) _rebuildMoverGrid();
    if (_statics.remove(collider)) _reindexStatics();
  }

  void clear() {
    _statics.clear();
    _movers.clear();
    _reporters.clear();
    _staticGrid.clear();
    _moverGrid.clear();
    _ids.clear();
    _overlapping.clear();
    _nextOverlapping.clear();
    _pairA.clear();
    _pairB.clear();
    _pendingRemoval.clear();
    _nextId = 0;
  }

  /// Re-indexes everything that moves, without firing any callbacks.
  ///
  /// Separate from [update] because a step has two moving halves: the doors and
  /// lifts go first, and the character controller has to sweep against where
  /// they are now rather than where they were last step — a lift indexed one
  /// step late is a lift a fast player can pass through.
  void reindex() => _rebuildMoverGrid();

  /// Re-indexes everything that moves and fires overlap callbacks.
  ///
  /// Called once per simulation step, after everything has moved. Before, and a
  /// trigger reports where things were rather than where they are.
  void update() {
    _rebuildMoverGrid();
    _dispatchOverlaps();
    if (_pendingRemoval.isNotEmpty) {
      for (final collider in _pendingRemoval) {
        remove(collider);
      }
      _pendingRemoval.clear();
    }
  }

  /// Clears the per-step motion of every kinematic body.
  ///
  /// Separate from [update] because the character controller reads that motion
  /// to carry a passenger, and it has to still be there when it does.
  void clearKinematicDeltas() {
    for (final mover in _movers) {
      mover.clearDelta();
    }
  }

  void _rebuildMoverGrid() {
    _moverGrid.clearEntries();
    for (var i = 0; i < _movers.length; i++) {
      final mover = _movers[i];
      mover.refreshBounds();
      _moverGrid.insert(i, mover.bounds);
    }
  }

  void _reindexStatics() {
    _staticGrid.clear();
    for (var i = 0; i < _statics.length; i++) {
      _staticGrid.insert(i, _statics[i].bounds);
    }
  }

  // MARK: - Overlap events

  void _dispatchOverlaps() {
    _nextOverlapping.clear();

    // Over a copy, because a callback is allowed to attach or detach a
    // listener — a key that has just been collected does — and that would
    // otherwise be a modification of the list being walked.
    _reporting
      ..clear()
      ..addAll(_reporters);

    for (final reporter in _reporting) {
      final min = reporter.bounds.min;
      final max = reporter.bounds.max;
      _staticGrid.forEachInBox(min, max, (int i) {
        _considerPair(reporter, _statics[i]);
      });
      _moverGrid.forEachInBox(min, max, (int i) {
        final other = _movers[i];
        if (identical(other, reporter)) return;
        _considerPair(reporter, other);
      });
    }

    // Anything overlapping last step and not this one has ended.
    for (final key in _overlapping) {
      if (_nextOverlapping.contains(key)) continue;
      final a = _pairA[key];
      final b = _pairB[key];
      if (a != null && b != null) {
        a.listener?.onCollisionEnd(a, b);
        b.listener?.onCollisionEnd(b, a);
      }
      _pairA.remove(key);
      _pairB.remove(key);
    }

    final swap = _overlapping;
    _overlapping = _nextOverlapping;
    _nextOverlapping = swap;
  }

  void _considerPair(Collider a, Collider b) {
    if (!a.interactsWith(b)) return;
    if (!_boundsOverlap(a.bounds, b.bounds)) return;
    if (!a.shape.overlaps(a.position, b.shape, b.position)) return;

    final key = _pairKey(a, b);
    // Both sides may report, and each would find the pair once.
    if (_nextOverlapping.contains(key)) return;
    _nextOverlapping.add(key);
    _pairA[key] = a;
    _pairB[key] = b;

    if (_overlapping.contains(key)) {
      a.listener?.onCollision(a, b);
      b.listener?.onCollision(b, a);
    } else {
      a.listener?.onCollisionStart(a, b);
      b.listener?.onCollisionStart(b, a);
    }
  }

  /// An order-independent key, so a pair is the same pair whichever collider
  /// noticed it.
  ///
  /// Packed by multiplication rather than by `lo << 32`. That shift is a
  /// native-only idiom — on the web an `int` is a double and a bitwise
  /// operation is done in 32 bits, so it discards `lo` entirely and every pair
  /// sharing its higher id becomes one key. Two colliders overlapping the same
  /// third one would then be a single pair: the second is swallowed by the
  /// `contains` check above, and its `onCollisionStart` and `onCollisionEnd`
  /// never fire. The product is exact while ids stay under 2^21.
  int _pairKey(Collider a, Collider b) {
    final ia = _ids[a] ?? -1;
    final ib = _ids[b] ?? -1;
    final lo = ia < ib ? ia : ib;
    final hi = ia < ib ? ib : ia;
    return lo * 0x100000000 + (hi & 0xFFFFFFFF);
  }

  // MARK: - Queries

  /// Sweeps [shape] from [origin] along [delta] against everything solid.
  ///
  /// Against whatever faces the other shape declares through
  /// [CollisionShape.expandedPlanes] — the bounding box for all three of them
  /// today, which that method explains is the right trade for moving a body
  /// and the wrong one for deciding a hit.
  bool sweep(
    CollisionShape shape,
    Vector3 origin,
    Vector3 delta,
    SweepHit out, {
    int mask = Layers.all,
    Collider? ignore,
    ContactFilter? allow,
  }) {
    out.reset();
    if (delta.x == 0.0 && delta.y == 0.0 && delta.z == 0.0) return false;

    final half = shape.boundsHalfExtents;
    _queryMin.setValues(
      math.min(origin.x, origin.x + delta.x) - half.x,
      math.min(origin.y, origin.y + delta.y) - half.y,
      math.min(origin.z, origin.z + delta.z) - half.z,
    );
    _queryMax.setValues(
      math.max(origin.x, origin.x + delta.x) + half.x,
      math.max(origin.y, origin.y + delta.y) + half.y,
      math.max(origin.z, origin.z + delta.z) + half.z,
    );

    void consider(Collider other) {
      if (identical(other, ignore)) return;
      if (!other.isSolid) return;
      if ((mask & other.layer) == 0) return;
      _sweepAgainst(origin, half, delta, other, out, allow);
    }

    _staticGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      consider(_statics[i]);
    });
    _moverGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      consider(_movers[i]);
    });
    return out.hit;
  }

  void _sweepAgainst(
    Vector3 origin,
    Vector3 half,
    Vector3 delta,
    Collider other,
    SweepHit out,
    ContactFilter? allow,
  ) {
    // A moving shape against a still one is a *point* against the still one
    // grown by the mover's half-extents, and the shape is the one that says
    // what that grown solid is.
    final count = _planesOf(other, half);
    final t = _sweepPointPlanes(origin, delta, count);
    if (t >= out.fraction) return;
    // The filter is asked *here* rather than in `consider`, and the normal is
    // the reason: whether a contact counts is usually a question about which
    // way the surface faces, and that is not known until the plane walk has
    // found which face was crossed.
    // A caller that only wants to skip whole colliders has [mask] already.
    if (allow != null && !allow(other, _candidateNormal)) return;

    out.fraction = t;
    out.normal.setFrom(_candidateNormal);
    out.collider = other;
  }

  /// Fills [_planes] with [other]'s solid grown by [half], and says how many.
  ///
  /// Around [Collider.indexedAt] rather than `position`, which is the same
  /// thing for everything except a mover that has already moved this step —
  /// and for that one it is deliberately the older of the two. See the field.
  int _planesOf(Collider other, Vector3 half) {
    final count = other.shape.expandedPlaneCount;
    if (_planes.length < count * 4) {
      _planes = Float64List(count * 4);
    }
    return other.shape.expandedPlanes(other.indexedAt, half, _planes);
  }

  /// How far along [delta] a point stays inside all [count] planes of
  /// [_planes].
  ///
  /// Writes the normal into [_candidateNormal] and returns the fraction, or 1.0
  /// for no contact. The last plane the point crosses on the way in is the one
  /// it touches, and the first it crosses on the way out ends the interval; the
  /// two passing each other means the solid was missed.
  ///
  /// A point that starts inside is reported as no hit. That reads as a bug and
  /// is the opposite: a body which refuses to move whenever it is already
  /// intersecting is a body that stays stuck forever the first time floating
  /// point leaves it a micrometre inside a wall. Getting out is [depenetrate]'s
  /// job, and it runs first.
  double _sweepPointPlanes(Vector3 origin, Vector3 delta, int count) {
    var tNear = double.negativeInfinity;
    var tFar = double.infinity;
    var entering = -1;
    var tNearApproach = -1.0;

    for (var i = 0; i < count; i++) {
      final base = i * 4;
      final nx = _planes[base];
      final ny = _planes[base + 1];
      final nz = _planes[base + 2];

      final approach = nx * delta.x + ny * delta.y + nz * delta.z;
      // Positive outside the plane, negative within it.
      final outside =
          nx * origin.x + ny * origin.y + nz * origin.z - _planes[base + 3];

      if (approach.abs() < Nearly.parallel) {
        // Travelling parallel to this face: either the right side of it for the
        // whole sweep, or never.
        if (outside > 0.0) return 1.0;
        continue;
      }

      final t = -outside / approach;
      if (approach < 0.0) {
        // Facing the plane, so this is where the point comes in.
        if (t > tNear) {
          tNear = t;
          tNearApproach = approach;
          entering = i;
        }
      } else if (t < tFar) {
        tFar = t;
      }
      if (tNear > tFar) return 1.0;
    }

    if (entering < 0) return 1.0;
    if (tNear >= 1.0) return 1.0;
    // **A point sitting *on* the face it is entering is touching it, not inside
    // it.** The two differ by float noise — a body put exactly on a surface by
    // [depenetrate] reads as thirty nanometres under it — and calling that
    // "already inside" costs a landing: the body falls a sixtieth of a second
    // further in, where it really is inside, and the fall never stops. The
    // slack is a micrometre of *distance*, converted here to a fraction of this
    // particular move, and it is a thousandth of the millimetre of clearance
    // every contact already backs off by.
    if (tNear < -_touching / tNearApproach.abs()) return 1.0;
    if (tNear < 0.0) tNear = 0.0;

    final base = entering * 4;
    _candidateNormal.setValues(
      _planes[base],
      _planes[base + 1],
      _planes[base + 2],
    );
    return tNear;
  }

  /// Fires a ray and reports the nearest thing it met.
  ///
  /// Exact per shape, unlike [sweep]: this decides whether a shot hit, and a
  /// bounding box would let the player kill a monster by shooting past its
  /// shoulder.
  bool raycast(
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    RayHit out, {
    int mask = Layers.all,
    Collider? ignore,
    bool includeTriggers = false,
  }) {
    out.reset();
    var nearest = maxDistance;

    void consider(Collider other) {
      if (identical(other, ignore)) return;
      if (!includeTriggers && !other.isSolid) return;
      if ((mask & other.layer) == 0) return;

      final distance = other.shape.raycast(
        other.position,
        origin,
        direction,
        nearest,
        _candidateNormal,
      );
      if (distance < 0.0 || distance > nearest) return;

      nearest = distance;
      out.distance = distance;
      out.collider = other;
      out.normal.setFrom(_candidateNormal);
      out.point
        ..setFrom(direction)
        ..scale(distance)
        ..add(origin);
    }

    // Walked cell by cell rather than through the ray's bounding box: a
    // diagonal shot down a corridor has a bounding box covering most of the
    // level.
    _staticGrid.forEachAlongRay(origin, direction, maxDistance, (int i) {
      consider(_statics[i]);
    });
    _moverGrid.forEachAlongRay(origin, direction, maxDistance, (int i) {
      consider(_movers[i]);
    });
    return out.hit;
  }

  /// Collects everything [shape] at [position] currently overlaps.
  ///
  /// Exact, and the list is filled rather than returned so a caller inside the
  /// step can reuse it.
  void overlap(
    CollisionShape shape,
    Vector3 position,
    List<Collider> out, {
    int mask = Layers.all,
    Collider? ignore,
    bool includeTriggers = true,
  }) {
    out.clear();
    final half = shape.boundsHalfExtents;
    _queryMin.setValues(
      position.x - half.x,
      position.y - half.y,
      position.z - half.z,
    );
    _queryMax.setValues(
      position.x + half.x,
      position.y + half.y,
      position.z + half.z,
    );

    void consider(Collider other) {
      if (identical(other, ignore)) return;
      if (!includeTriggers && !other.isSolid) return;
      if ((mask & other.layer) == 0) return;
      if (!shape.overlaps(position, other.shape, other.position)) return;
      out.add(other);
    }

    _staticGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      consider(_statics[i]);
    });
    _moverGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      consider(_movers[i]);
    });
  }

  /// Pushes a box out of anything solid it is already inside.
  ///
  /// The face it is nearest to wins: that is the shallowest way out, and
  /// therefore the one that does not fling the player across the room.
  ///
  /// Needed because nothing guarantees a clean state — a lift can close on the
  /// player, a level can spawn them badly, and floating point can leave them a
  /// hair inside a wall after a slide.
  bool depenetrate(
    Vector3 centre,
    Vector3 halfExtents,
    Vector3 out, {
    int mask = Layers.all,
    Collider? ignore,
    ContactFilter? allow,
  }) {
    out.setZero();
    var corrected = false;

    _queryMin.setValues(
      centre.x - halfExtents.x,
      centre.y - halfExtents.y,
      centre.z - halfExtents.z,
    );
    _queryMax.setValues(
      centre.x + halfExtents.x,
      centre.y + halfExtents.y,
      centre.z + halfExtents.z,
    );

    void resolve(Collider other) {
      if (identical(other, ignore)) return;
      if (!other.isSolid) return;
      if ((mask & other.layer) == 0) return;

      // The same planes a sweep would use, asked the other question: not "when
      // does the point cross a face" but "which face is it nearest to now".
      final count = _planesOf(other, halfExtents);
      var shallowest = double.infinity;
      var through = -1;

      for (var i = 0; i < count; i++) {
        final base = i * 4;
        // How far inside this face the centre sits, and therefore how far it
        // would have to travel along the normal to leave through it.
        final depth =
            _planes[base + 3] -
            (_planes[base] * centre.x +
                _planes[base + 1] * centre.y +
                _planes[base + 2] * centre.z);
        // Outside one face is outside the solid, whatever the other five say.
        if (depth <= 0.0) return;
        if (depth < shallowest) {
          shallowest = depth;
          through = i;
        } else if (depth == shallowest &&
            _planes[base + 1].abs() > _planes[through * 4 + 1].abs()) {
          // **A tie goes to the most upright face.** A body wedged into the
          // join between a floor and a wall is exactly as far inside both, and
          // lifting it out is the answer that leaves it standing where it was;
          // shoving it sideways moves the player for them. This is what the
          // per-axis form said by testing y first, kept as something a shape
          // with faces that are not axes can still obey.
          through = i;
        }
      }

      final base = through * 4;
      // Which way this push would go, so the filter is asked the same question
      // here as in a sweep: not "which collider" but "which way does it face".
      // Without this a body that sweeps through a one-way platform is ejected
      // out of its side by the very next depenetration, which is the bug a mask
      // on its own leaves behind.
      _pushNormal.setValues(
        _planes[base],
        _planes[base + 1],
        _planes[base + 2],
      );
      if (allow != null && !allow(other, _pushNormal)) return;
      corrected = true;
      _ask(_directionOf(_pushNormal), shallowest);
    }

    for (var i = 0; i < 6; i++) {
      _deepest[i] = 0.0;
    }

    _staticGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      resolve(_statics[i]);
    });
    _moverGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      resolve(_movers[i]);
    });

    // **The deepest push in each direction, not the sum of them.** It used to
    // be `out.y += push`, once per collider, and that double-counts in the most
    // ordinary situation there is: a body standing on the seam between two
    // floor brushes overlaps both, by the same tenth of a metre, upwards, for
    // the same reason — and was lifted two tenths. Every floor in every level
    // is a row of brushes, so this fired constantly, and it went unnoticed
    // because the error is small and always upward, which reads as a body that
    // sits a little high rather than as a bug.
    //
    // **Opposing pushes still both apply**, and that is not an oversight. A
    // body being closed on by a platform is told two different things, and the
    // answer is the net of them — resolving it as "whichever face spoke last"
    // pushes the player through the floor, which is what the crushing test
    // caught when this was first written as a projection.
    out.x += _deepest[1] - _deepest[0];
    out.y += _deepest[3] - _deepest[2];
    out.z += _deepest[5] - _deepest[4];
    return corrected;
  }

  /// Records a push of [depth] in one of the six directions, keeping the
  /// deepest.
  void _ask(int direction, double depth) {
    if (depth > _deepest[direction]) _deepest[direction] = depth;
  }

  /// Which of the six directions [normal] points along.
  ///
  /// The six survive the move to planes because they are what stops a body on
  /// a seam being pushed out twice, and that is a statement about opposing
  /// pairs rather than about axes. A normal that is not one of the six has no
  /// bucket to be deepest in, and there is none today: every plane written here
  /// comes from a bounding box.
  static int _directionOf(Vector3 normal) {
    if (normal.y != 0.0) return normal.y < 0.0 ? 2 : 3;
    if (normal.x != 0.0) return normal.x < 0.0 ? 0 : 1;
    return normal.z < 0.0 ? 4 : 5;
  }

  /// The deepest push asked for in each of the six directions, this call.
  ///
  /// Order: -x, +x, -y, +y, -z, +z.
  final Float64List _deepest = Float64List(6);

  static bool _boundsOverlap(Aabb3 a, Aabb3 b) =>
      a.min.x < b.max.x &&
      a.max.x > b.min.x &&
      a.min.y < b.max.y &&
      a.max.y > b.min.y &&
      a.min.z < b.max.z &&
      a.max.z > b.min.z;
}
