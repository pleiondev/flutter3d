import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'spatial_grid.dart';

/// Where a swept shape first touched something.
///
/// Reused between queries rather than returned fresh: the character controller
/// runs several sweeps per step, sixty times a second, and an allocation here
/// is an allocation on the hottest path in the game.
final class SweepHit {
  /// Fraction of the requested motion completed before contact, in `[0, 1]`.
  /// One means nothing was in the way.
  double fraction = 1.0;

  /// Surface normal at the contact, always axis-aligned because sweeps run
  /// against bounds.
  final Vector3 normal = Vector3.zero();

  Collider? collider;

  bool get hit => fraction < 1.0;

  void reset() {
    fraction = 1.0;
    normal.setZero();
    collider = null;
  }
}

/// Where a ray met something.
final class RayHit {
  double distance = -1.0;
  final Vector3 point = Vector3.zero();
  final Vector3 normal = Vector3.zero();
  Collider? collider;

  bool get hit => distance >= 0.0;

  void reset() {
    distance = -1.0;
    point.setZero();
    normal.setZero();
    collider = null;
  }
}

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
  final Vector3 _queryMin = Vector3.zero();
  final Vector3 _queryMax = Vector3.zero();
  final Vector3 _expandedMin = Vector3.zero();
  final Vector3 _expandedMax = Vector3.zero();
  final Vector3 _candidateNormal = Vector3.zero();

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
    _movers.remove(collider);
    _reporters.remove(collider);
    if (_statics.remove(collider)) _reindexStatics();
    _ids.remove(collider);
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

  /// Re-indexes everything that moves and fires overlap callbacks.
  ///
  /// Called once per simulation step, after everything has moved. Before, and a
  /// trigger reports where things were rather than where they are.
  /// Re-indexes everything that moves, without firing any callbacks.
  ///
  /// Separate from [update] because a step has two moving halves: the doors and
  /// lifts go first, and the character controller has to sweep against where
  /// they are now rather than where they were last step — a lift indexed one
  /// step late is a lift a fast player can pass through.
  void reindex() => _rebuildMoverGrid();

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
  int _pairKey(Collider a, Collider b) {
    final ia = _ids[a] ?? -1;
    final ib = _ids[b] ?? -1;
    final lo = ia < ib ? ia : ib;
    final hi = ia < ib ? ib : ia;
    return (lo << 32) ^ (hi & 0xFFFFFFFF);
  }

  // MARK: - Queries

  /// Sweeps [shape] from [origin] along [delta] against everything solid.
  ///
  /// Runs against bounds rather than exact shapes; [CollisionShape] explains
  /// why that is the right trade for moving a body and the wrong one for
  /// deciding a hit.
  bool sweep(
    CollisionShape shape,
    Vector3 origin,
    Vector3 delta,
    SweepHit out, {
    int mask = CollisionLayers.all,
    Collider? ignore,
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
      _sweepAgainst(origin, half, delta, other, out);
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
  ) {
    // A box against a box is a point against the first grown by the second's
    // half-extents — the Minkowski sum of two axis-aligned boxes.
    _expandedMin.setValues(
      other.bounds.min.x - half.x,
      other.bounds.min.y - half.y,
      other.bounds.min.z - half.z,
    );
    _expandedMax.setValues(
      other.bounds.max.x + half.x,
      other.bounds.max.y + half.y,
      other.bounds.max.z + half.z,
    );

    final t = _sweepPointBox(origin, delta, _expandedMin, _expandedMax);
    if (t < out.fraction) {
      out.fraction = t;
      out.normal.setFrom(_candidateNormal);
      out.collider = other;
    }
  }

  /// The slab test: how far along [delta] a point stays inside every slab.
  ///
  /// Writes the normal into [_candidateNormal] and returns the fraction, or 1.0
  /// for no contact.
  ///
  /// A point that starts inside the box is reported as no hit. That reads as a
  /// bug and is the opposite: a body which refuses to move whenever it is
  /// already intersecting is a body that stays stuck forever the first time
  /// floating point leaves it a micrometre inside a wall. Getting out is
  /// [depenetrate]'s job, and it runs first.
  double _sweepPointBox(
    Vector3 origin,
    Vector3 delta,
    Vector3 boxMin,
    Vector3 boxMax,
  ) {
    var tNear = double.negativeInfinity;
    var tFar = double.infinity;
    var hitAxis = -1;
    var hitSign = 0.0;

    for (var axis = 0; axis < 3; axis++) {
      final o = origin[axis];
      final d = delta[axis];
      final lo = boxMin[axis];
      final hi = boxMax[axis];

      if (d.abs() < 1e-12) {
        // Moving parallel to this pair of faces: either between them for the
        // whole sweep, or never.
        if (o < lo || o > hi) return 1.0;
        continue;
      }

      final inverse = 1.0 / d;
      var enter = (lo - o) * inverse;
      var exit = (hi - o) * inverse;
      final sign = d > 0.0 ? -1.0 : 1.0;
      if (enter > exit) {
        final swap = enter;
        enter = exit;
        exit = swap;
      }

      if (enter > tNear) {
        tNear = enter;
        hitAxis = axis;
        hitSign = sign;
      }
      if (exit < tFar) tFar = exit;
      if (tNear > tFar) return 1.0;
    }

    if (hitAxis < 0) return 1.0;
    if (tNear < 0.0 || tNear >= 1.0) return 1.0;

    _candidateNormal.setZero();
    _candidateNormal[hitAxis] = hitSign;
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
    int mask = CollisionLayers.all,
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
    int mask = CollisionLayers.all,
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
  /// The axis with the smallest overlap wins: it is the shallowest way out, and
  /// therefore the one that does not fling the player across the room.
  ///
  /// Needed because nothing guarantees a clean state — a lift can close on the
  /// player, a level can spawn them badly, and floating point can leave them a
  /// hair inside a wall after a slide.
  bool depenetrate(
    Vector3 centre,
    Vector3 halfExtents,
    Vector3 out, {
    int mask = CollisionLayers.all,
    Collider? ignore,
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

      final box = other.bounds;
      final overlapX =
          math.min(_queryMax.x, box.max.x) - math.max(_queryMin.x, box.min.x);
      if (overlapX <= 0.0) return;
      final overlapY =
          math.min(_queryMax.y, box.max.y) - math.max(_queryMin.y, box.min.y);
      if (overlapY <= 0.0) return;
      final overlapZ =
          math.min(_queryMax.z, box.max.z) - math.max(_queryMin.z, box.min.z);
      if (overlapZ <= 0.0) return;

      corrected = true;
      if (overlapY <= overlapX && overlapY <= overlapZ) {
        out.y += centre.y < other.position.y ? -overlapY : overlapY;
      } else if (overlapX <= overlapZ) {
        out.x += centre.x < other.position.x ? -overlapX : overlapX;
      } else {
        out.z += centre.z < other.position.z ? -overlapZ : overlapZ;
      }
    }

    _staticGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      resolve(_statics[i]);
    });
    _moverGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      resolve(_movers[i]);
    });
    return corrected;
  }

  static bool _boundsOverlap(Aabb3 a, Aabb3 b) =>
      a.min.x < b.max.x &&
      a.max.x > b.min.x &&
      a.min.y < b.max.y &&
      a.max.y > b.min.y &&
      a.min.z < b.max.z &&
      a.max.z > b.min.z;
}
