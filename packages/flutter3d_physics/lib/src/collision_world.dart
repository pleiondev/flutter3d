import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SnapshotPart, WorldPosition;
import 'package:vector_math/vector_math.dart';

import 'character_mover.dart';
import 'collider.dart';
import 'collision_shape.dart';
import 'physics_backend.dart';
import 'ray_hit.dart';
import 'spatial_grid.dart';
import 'sweep_hit.dart';
import 'tolerances.dart';
import 'world_rays.dart';

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
  CollisionWorld({
    double cellSize = 4.0,
    this.backend = const DartPhysics(),
    WorldProperties? properties,
    MaterialCatalog? materials,
  }) : properties = properties ?? WorldProperties.standard,
       // Not an initializing formal: the parameter is public, the field is
       // filled lazily when nobody gave one.
       // ignore: prefer_initializing_formals
       _materials = materials,
       _staticGrid = SpatialGrid(cellSize: cellSize),
       _moverGrid = SpatialGrid(cellSize: cellSize);

  /// What this world is made of: its gravity, its air, its wind, its medium
  /// and its step rate — [WorldProperties.standard] unless the world was made
  /// with, or later given, another.
  ///
  /// **The one place everything in the world reads them.** A game sets its
  /// own where it stages the world (the platformer's 24 m/s²), a level's
  /// `world` overrides it on top, and the dynamics, the characters, the
  /// navigation's jump arcs, the particles, the cloth and the liquids read
  /// it here rather than carrying a number of their own. A change is a
  /// change to the simulation: the dynamics' saved state carries it, so a
  /// rewind puts back the world it was saved under.
  WorldProperties properties;

  /// The physical materials this world's colliders, liquids and medium are
  /// named from: the engine's own (`MaterialCatalog.builtIn`) unless the
  /// world was given the engine's catalogue, plugins' materials and all.
  MaterialCatalog get materials => _materials ??= MaterialCatalog.builtIn();
  set materials(MaterialCatalog value) => _materials = value;
  MaterialCatalog? _materials;

  /// What simulates this world's physics: its rigid bodies
  /// (`backend.dynamics(world)`), its characters' moves and rays
  /// (`backend.attach(world)`), its cloth and its liquids. The Dart reference
  /// unless the world was made with another — the backend belongs to the
  /// world, never to the process (see [PhysicsBackend]).
  final PhysicsBackend backend;

  /// What moves the characters in this world, or null for their own
  /// sweeps — see [CharacterMover]. The physics core sets one for a world it
  /// mirrors.
  CharacterMover? characterMover;

  /// What casts this world's rays, or null for its own walk — see
  /// [WorldRays]. Not asked for a ray that wants triggers.
  WorldRays? rays;

  /// What sweeps shapes through this world, or null for its own walk — see
  /// [WorldSweeps]. Not asked for a sweep with a [ContactFilter].
  WorldSweeps? sweeps;

  /// What keeps a copy of this world, brought up to date at the end of every
  /// [update] — see [WorldMirror].
  final List<WorldMirror> mirrors = <WorldMirror>[];

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

  /// The static colliders, for a caller that has to find its own among them
  /// — a level that put its walls here through `addTo` and later has to take
  /// one out. Read-only: adding and removing go through [add] and [remove],
  /// which keep the grid's indices true.
  Iterable<Collider> get statics => _statics;

  /// The moving colliders — bodies, characters, doors and lifts — for a
  /// caller that mirrors the world elsewhere, as the native dynamics does.
  /// Read-only, as [statics] is.
  Iterable<Collider> get movers => _movers;

  /// How many moving colliders are in the world.
  ///
  /// [colliderCount] is what the engine's own checks watch, because the total is
  /// what a leak shows up in. This half is for a profiler: movers are the ones
  /// re-inserted into the grid every step, so this is the number that predicts
  /// what a step costs, and the static count that does not.
  int get moverCount => _movers.length;

  // Scratch, reused by every query.
  /// Which way a depenetration would push, handed to a [ContactFilter].
  final Vector3 _pushNormal = Vector3.zero();

  final Vector3 _queryMin = Vector3.zero();
  final Vector3 _queryMax = Vector3.zero();
  final Vector3 _candidateNormal = Vector3.zero();

  /// The scratch handed to a [ContactFilter]. One per world, rewritten before
  /// each call; see [SweptContact] for why it is not allocated per contact.
  final SweptContact _contact = SweptContact();

  /// The planes of whichever solid is being tested right now, four doubles
  /// each. Grown if a shape ever asks for more; never shrunk.
  Float64List _planes = Float64List(CollisionShape.boundsPlaneCount * 4);

  /// Which convex parts of the shape being tested lie near the query, and how
  /// many of them there were. Grown the same way [_planes] is.
  ///
  /// A field of ground is many parts and everything else is one, so this holds
  /// a single zero for four shapes out of five and is the reason the fifth
  /// needs no separate path through any query.
  Int32List _parts = Int32List(16);

  /// Which of the current part's planes are seams rather than surfaces, as a
  /// bit per plane. See [CollisionShape.partSeams].
  int _seams = 0;

  /// The mover, when a caller offered only a size.
  ///
  /// [depenetrate] takes half-extents, because its callers have a box and not
  /// always a shape, and growth is a question for a *shape* — see
  /// [CollisionShape.supportAlong]. Rewritten per call rather than allocated,
  /// like everything else in this block.
  final CollisionBox _asBox = CollisionBox(Vector3.zero());

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

  /// Bumped whenever a collider joins or leaves: a mirror of this world —
  /// the physics core's — asks it to know when to look for new ones without
  /// walking every collider on every query.
  int get revision => _revision;
  int _revision = 0;

  /// Adds a collider and returns it, so the call can be inlined into a field.
  Collider add(Collider collider) {
    collider.world = this;
    collider.refreshBounds();
    _ids[collider] = _nextId++;
    _revision++;

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
  Collider addBox(Vector3 center, Vector3 size, {Object? userData}) => add(
    Collider(
      shape: CollisionBox.size(size),
      position: center,
      userData: userData,
    ),
  );

  void remove(Collider collider) {
    collider.world = null;
    _reporters.remove(collider);
    _ids.remove(collider);
    _revision++;

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
    _revision++;
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

  // MARK: - The floating origin

  final List<WeakReference<Vector3>> _alsoShifted = <WeakReference<Vector3>>[];

  /// Shifts [point] with this world's origin from now on: a position this
  /// world's colliders do not hold themselves — a character controller's, a
  /// camera rig's. Held weakly, so a point nobody else holds is let go.
  void shiftsWithOrigin(Vector3 point) =>
      _alsoShifted.add(WeakReference<Vector3>(point));

  WorldPosition _origin = WorldPosition.origin;

  /// The place in the world this world's float32 positions are relative to:
  /// a collider at `(0, 0, 0)` is here. [WorldPosition.origin] until
  /// [moveOriginTo] moves it.
  WorldPosition get origin => _origin;

  /// Moves the origin to [to]: every collider, and every point given to
  /// [shiftsWithOrigin], moves the other way by the difference, taken in
  /// doubles, so nothing moves in the world and what is near the new origin
  /// gets float32's full precision back. Kinematic deltas are not touched —
  /// this is not motion.
  ///
  /// **The one origin call of a physics world**, the same as the native
  /// core's `NativeWorld.moveOriginTo`. The physics hook of item 18:
  /// `EngineLoop.shiftsPhysics` calls it with `OriginShifted.to`. A backend's
  /// own copy of the world is told through its [mirrors] at the next
  /// [update]; a backend that holds an origin of its own (the native core)
  /// is moved by its own hook.
  void moveOriginTo(WorldPosition to) {
    final by = to.relativeTo(_origin);
    _origin = to;
    final (:x, :y, :z) = by;
    if (x == 0.0 && y == 0.0 && z == 0.0) return;
    for (final collider in <Collider>[..._statics, ..._movers]) {
      final p = collider.position;
      p.setValues(p.x - x, p.y - y, p.z - z);
      collider.refreshBounds();
    }
    _alsoShifted.removeWhere((weak) {
      final point = weak.target;
      if (point == null) return true;
      point.setValues(point.x - x, point.y - y, point.z - z);
      return false;
    });
    _reindexStatics();
    _rebuildMoverGrid();
  }

  /// [origin] as a part of the loop's snapshots, restored before every
  /// other part ([SnapshotPart.restoresFirst]).
  ///
  /// **Why the origin is state.** Every position this world and its
  /// characters hold is relative to it, and a snapshot of a body is a snapshot
  /// of a relative position: restored under another origin it lands
  /// somewhere else. So the origin goes back first — [moveOriginTo] the one
  /// captured, which carries the level's static colliders along — and the
  /// bodies' own parts then write their positions over it in the frame they
  /// were taken in. `EngineLoop.shiftsPhysics` registers it.
  SnapshotPart get originPart => _CollisionOriginPart(this);

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
    for (final mirror in mirrors) {
      mirror.mirror();
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
  /// [CollisionShape.partPlanes] — the bounding box for a box, a sphere and a
  /// capsule, five real faces for a ramp, and one prism per triangle for a
  /// field of ground. [CollisionShape.expandedPlanes] explains why the bounding
  /// box is the right trade for moving a body and the wrong one for deciding a
  /// hit.
  ///
  /// **The normal this reports is not always an axis.** It was for as long as
  /// every shape offered its bounding box, and a good deal of code was written
  /// in that world; anything comparing `normal.y` against a walkable limit is
  /// still right, and anything assuming two of the three components are zero is
  /// not. See [SweepHit.normal].
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
    if (allow == null) {
      if (sweeps case final WorldSweeps elsewhere) {
        return elsewhere.sweep(
          shape,
          origin,
          delta,
          out,
          mask: mask,
          ignore: ignore,
        );
      }
    }

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
      _sweepAgainst(origin, shape, delta, other, out, allow);
    }

    _staticGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      consider(_statics[i]);
    });
    _moverGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      consider(_movers[i]);
    });
    return out.didHit;
  }

  void _sweepAgainst(
    Vector3 origin,
    CollisionShape mover,
    Vector3 delta,
    Collider other,
    SweepHit out,
    ContactFilter? allow,
  ) {
    // A moving shape against a still one is a *point* against the still one
    // grown by the mover's own reach, and the shape is the one that says what
    // that grown solid is.
    //
    // Once per convex part of it, and four shapes out of five have exactly
    // one. The nearest part wins, the way the nearest collider does: a body
    // crossing a field of ground is inside the reach of two or three triangles
    // at a time and has to be stopped by whichever it meets first.
    final parts = _partsOf(other, _queryMin, _queryMax);
    for (var p = 0; p < parts; p++) {
      final part = _parts[p];
      final count = _partPlanesOf(other, part, mover);
      final t = _sweepPointPlanes(origin, delta, count);
      if (t >= out.fraction) continue;
      // The filter is asked *here* rather than in `consider`, and the normal is
      // the reason: whether a contact counts is usually a question about which
      // way the surface faces, and that is not known until the plane walk has
      // found which face was crossed.
      // A caller that only wants to skip whole colliders has [mask] already.
      if (allow != null) {
        _contact.set(other, _candidateNormal);
        if (!allow(_contact)) continue;
      }

      out.fraction = t;
      out.normal.setFrom(_candidateNormal);
      out.collider = other;
    }
  }

  /// Fills [_parts] with the parts of [other] inside the box [min]..[max].
  ///
  /// The buffer grows and is asked again when a shape had more parts than it
  /// could hold — see [CollisionShape.partsIn], which returns the total rather
  /// than what it managed to write, so this cannot silently walk half a field.
  int _partsOf(Collider other, Vector3 min, Vector3 max) {
    var count = other.shape.partsIn(other.indexedAt, min, max, _parts);
    if (count > _parts.length) {
      _parts = Int32List(count);
      count = other.shape.partsIn(other.indexedAt, min, max, _parts);
    }
    return count;
  }

  /// Fills [_planes] with one part of [other] grown to hold [mover], and says
  /// how many. Records that part's seams in [_seams].
  ///
  /// Around [Collider.indexedAt] rather than `position`, which is the same
  /// thing for everything except a mover that has already moved this step —
  /// and for that one it is deliberately the older of the two. See the field.
  int _partPlanesOf(Collider other, int part, CollisionShape mover) {
    final count = other.shape.partPlaneCount;
    if (_planes.length < count * 4) {
      _planes = Float64List(count * 4);
    }
    _seams = other.shape.partSeams(part);
    return other.shape.partPlanes(part, other.indexedAt, mover, _planes);
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

    // **The face it came in through is a seam, so it came in through nothing.**
    // Where two pieces of one shape meet, each ends in a face the other
    // continues past; a body crossing the join enters that face and would be
    // stopped by a wall nobody drew. Dropping the whole contact rather than
    // choosing another face is right because the piece next door is walked too
    // and reports the surface that is really there. See
    // [CollisionShape.partSeams].
    if ((_seams & (1 << entering)) != 0) return 1.0;

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
    final rays = this.rays;
    if (rays != null && !includeTriggers) {
      return rays.raycast(
        origin,
        direction,
        maxDistance,
        out,
        mask: mask,
        ignore: ignore,
      );
    }
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
    return out.didHit;
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
  /// therefore the one that does not fling the player across the room. Once per
  /// convex part of what it is inside, so a body standing where three triangles
  /// of a hillside meet is told one thing by each and lifted by the deepest of
  /// them rather than by their sum — see [_ask].
  ///
  /// Needed because nothing guarantees a clean state — a lift can close on the
  /// player, a level can spawn them badly, and floating point can leave them a
  /// hair inside a wall after a slide.
  bool depenetrate(
    Vector3 center,
    Vector3 halfExtents,
    Vector3 out, {
    int mask = Layers.all,
    Collider? ignore,
    ContactFilter? allow,
  }) {
    out.setZero();
    var corrected = false;
    _asBox.halfExtents.setFrom(halfExtents);

    // Where the box is asked about: [center], and once more where a mover's
    // push would put it (below).
    final at = _depenetrateAt..setFrom(center);

    void resolve(Collider other) {
      if (identical(other, ignore)) return;
      if (!other.isSolid) return;
      if ((mask & other.layer) == 0) return;

      // Once per convex part, the same way a sweep is — a body standing on a
      // field of ground is inside the reach of two or three triangles at once
      // and each of them has its own way out.
      final parts = _partsOf(other, _queryMin, _queryMax);
      for (var p = 0; p < parts; p++) {
        if (_pushOutOfPart(other, _parts[p], at, allow)) corrected = true;
      }
    }

    void resolveStatics() {
      _queryMin.setValues(
        at.x - halfExtents.x,
        at.y - halfExtents.y,
        at.z - halfExtents.z,
      );
      _queryMax.setValues(
        at.x + halfExtents.x,
        at.y + halfExtents.y,
        at.z + halfExtents.z,
      );
      for (var i = 0; i < 6; i++) {
        _deepest[i] = 0.0;
      }
      _staticGrid.forEachInBox(_queryMin, _queryMax, (int i) {
        resolve(_statics[i]);
      });
    }

    resolveStatics();
    for (var i = 0; i < 6; i++) {
      _held[i] = _deepest[i];
      _deepest[i] = 0.0;
    }
    _moverGrid.forEachInBox(_queryMin, _queryMax, (int i) {
      resolve(_movers[i]);
    });

    // **What does not move wins against what does.** A static pushing one
    // way and a mover the other is a body being closed on — a platform
    // coming down onto the floor — and the net of the two is the middle of
    // the gap, which a correction of the net jumps across every step: the
    // body flipped between above the floor and half a metre into it, and
    // once the platform reached the floor the middle was under it. The
    // floor holds; the body is left inside the platform, which a game can
    // see and call a crushing. Between two statics, or two movers, both
    // pushes still apply.
    var moverOnly = false;
    for (var axis = 0; axis < 6; axis += 2) {
      final heldDown = _held[axis], heldUp = _held[axis + 1];
      if (heldDown == 0.0 &&
          heldUp == 0.0 &&
          (_deepest[axis] > 0.0 || _deepest[axis + 1] > 0.0)) {
        moverOnly = true;
      }
      _deepest[axis] = math.max(heldDown, heldUp > 0.0 ? 0.0 : _deepest[axis]);
      _deepest[axis + 1] = math.max(
        heldUp,
        heldDown > 0.0 ? 0.0 : _deepest[axis + 1],
      );
    }
    for (var i = 0; i < 6; i++) {
      _pushed[i] = _deepest[i];
    }

    // **Nor does a mover push a body into a static.** Standing on the floor
    // under a platform coming down, only the platform overlaps the body,
    // and its push out alone set the body into the floor — to be lifted
    // back by the rule above the step after, and pushed down again the step
    // after that. So a push only a mover made is asked of the statics where
    // it would leave the body, and gives back on that axis what they push.
    if (moverOnly) {
      at
        ..x += _pushed[1] - _pushed[0]
        ..y += _pushed[3] - _pushed[2]
        ..z += _pushed[5] - _pushed[4];
      resolveStatics();
      for (var axis = 0; axis < 6; axis += 2) {
        if (_held[axis] != 0.0 || _held[axis + 1] != 0.0) continue;
        // A push down is given back by a push up, at most all of it.
        _pushed[axis] = math.max(0.0, _pushed[axis] - _deepest[axis + 1]);
        _pushed[axis + 1] = math.max(0.0, _pushed[axis + 1] - _deepest[axis]);
      }
    }
    for (var i = 0; i < 6; i++) {
      _deepest[i] = _pushed[i];
    }

    // **The deepest push in each direction, not the sum of them.** It used to
    // be `out.y += push`, once per collider, and that double-counts in the most
    // ordinary situation there is: a body standing on the seam between two
    // floor brushes overlaps both, by the same tenth of a metre, upwards, for
    // the same reason — and was lifted two tenths. Every floor in every level
    // is a row of brushes, so this fired constantly, and it went unnoticed
    // because the error is small and always upward, which reads as a body that
    // sits a little high rather than as a bug.
    //
    // **Opposing pushes of one kind both apply**, and that is not an
    // oversight: resolving them as "whichever face spoke last" pushes the
    // player through a wall, which is what the crushing test caught when this
    // was first written as a projection. A static against a mover is settled
    // above, for the static.
    out.x += _deepest[1] - _deepest[0];
    out.y += _deepest[3] - _deepest[2];
    out.z += _deepest[5] - _deepest[4];
    return corrected;
  }

  /// Pushes [center] out of one convex part of [other], if it is inside it.
  ///
  /// The shallowest face wins: that is the shortest way out, and therefore the
  /// one that does not fling the player across the room.
  bool _pushOutOfPart(
    Collider other,
    int part,
    Vector3 center,
    ContactFilter? allow,
  ) {
    // The same planes a sweep would use, asked the other question: not "when
    // does the point cross a face" but "which face is it nearest to now".
    final count = _partPlanesOf(other, part, _asBox);
    var shallowest = double.infinity;
    var through = -1;

    for (var i = 0; i < count; i++) {
      final base = i * 4;
      // How far inside this face the centre sits, and therefore how far it
      // would have to travel along the normal to leave through it.
      final depth =
          _planes[base + 3] -
          (_planes[base] * center.x +
              _planes[base + 1] * center.y +
              _planes[base + 2] * center.z);
      // Outside one face is outside the solid, whatever the other five say —
      // and a seam counts here, because a body past a seam really has left this
      // piece of the shape. It is only as a way *out* that a seam is refused.
      if (depth <= 0.0) return false;
      if ((_seams & (1 << i)) != 0) continue;
      if (through < 0 || depth < shallowest) {
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

    // Every way out was a seam, which happens to a body deep inside a field of
    // ground with a triangle on all sides. The piece it is nearest the surface
    // of has a real way out, and this body is inside that one too.
    if (through < 0) return false;

    final base = through * 4;
    // Which way this push would go, so the filter is asked the same question
    // here as in a sweep: not "which collider" but "which way does it face".
    // Without this a body that sweeps through a one-way platform is ejected
    // out of its side by the very next depenetration, which is the bug a mask
    // on its own leaves behind.
    _pushNormal.setValues(_planes[base], _planes[base + 1], _planes[base + 2]);
    if (allow != null) {
      _contact.set(other, _pushNormal);
      if (!allow(_contact)) return false;
    }
    _ask(_pushNormal, shallowest);
    return true;
  }

  /// Records a push of [depth] along [normal], keeping the deepest asked for in
  /// each of the six directions.
  ///
  /// **The push is split into its three components rather than filed under one
  /// direction**, and for an axis-aligned normal that is the same arithmetic it
  /// always was: two of the three components are zero and the third is the
  /// whole depth. It stops being the same the moment a face is not an axis. The
  /// first version asked which of the six a normal pointed *most* along and
  /// filed the whole depth there, so a body a centimetre inside a slope was
  /// lifted a centimetre straight up — short of the way out by the cosine of
  /// the slope, every step, for as long as it stood there.
  ///
  /// The six buckets survive because they are what stops a body on a seam being
  /// pushed out twice: two floor brushes, or two triangles of one field, ask
  /// for the same push for the same reason, and the answer is that push and not
  /// two of them.
  void _ask(Vector3 normal, double depth) {
    final x = normal.x * depth;
    final y = normal.y * depth;
    final z = normal.z * depth;
    if (x < 0.0) {
      if (-x > _deepest[0]) _deepest[0] = -x;
    } else if (x > _deepest[1]) {
      _deepest[1] = x;
    }
    if (y < 0.0) {
      if (-y > _deepest[2]) _deepest[2] = -y;
    } else if (y > _deepest[3]) {
      _deepest[3] = y;
    }
    if (z < 0.0) {
      if (-z > _deepest[4]) _deepest[4] = -z;
    } else if (z > _deepest[5]) {
      _deepest[5] = z;
    }
  }

  /// The deepest push asked for in each of the six directions, this call.
  ///
  /// Order: -x, +x, -y, +y, -z, +z.
  final Float64List _deepest = Float64List(6);

  /// [_deepest] as the statics alone asked for it, in [depenetrate].
  final Float64List _held = Float64List(6);

  /// The pushes [depenetrate] settled on, while [_deepest] asks the statics
  /// again.
  final Float64List _pushed = Float64List(6);

  /// Where [depenetrate] asks about the box.
  final Vector3 _depenetrateAt = Vector3.zero();

  static bool _boundsOverlap(Aabb3 a, Aabb3 b) =>
      a.min.x < b.max.x &&
      a.max.x > b.min.x &&
      a.min.y < b.max.y &&
      a.max.y > b.min.y &&
      a.min.z < b.max.z &&
      a.max.z > b.min.z;
}

final class _CollisionOriginPart extends SnapshotPart {
  const _CollisionOriginPart(this.world);

  final CollisionWorld world;

  @override
  String get id => 'flutter3d.physics.origin';

  @override
  bool get restoresFirst => true;

  @override
  Object? capture() {
    final at = world.origin;
    return <double>[at.x, at.y, at.z];
  }

  @override
  void restore(Object? data, int version) {
    if (data case [final num x, final num y, final num z]) {
      world.moveOriginTo(
        WorldPosition(x.toDouble(), y.toDouble(), z.toDouble()),
      );
    }
  }
}
