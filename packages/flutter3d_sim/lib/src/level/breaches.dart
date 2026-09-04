import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import '../physics/layers.dart';
import 'level.dart';

/// What is left of a brush when a box is taken out of it.
///
/// **Exact, because the world is boxes.** Constructive solid geometry over
/// arbitrary meshes is a research problem with a literature; over
/// axis-aligned boxes it is arithmetic. A box minus a box is at most six
/// boxes — the slab on each side of the hole along X, then along Y inside
/// that, then along Z inside that — and every one of them is a [Brush] like
/// the one it came from, with the same material and the same answer about
/// shadows, which is why nothing downstream has to know a wall was ever
/// whole.
///
/// A brush the hole misses comes back alone; a brush the hole swallows comes
/// back as nothing. A ramp is never cut — a wedge minus a box is not a set
/// of wedges — and comes back alone whatever the hole.
List<Brush> subtractBox(Brush brush, Aabb3 hole) {
  if (brush.ramp != null) return <Brush>[brush];
  final lo = brush.min;
  final hi = brush.max;
  final hl = hole.min;
  final hh = hole.max;
  if (hl.x >= hi.x ||
      hh.x <= lo.x ||
      hl.y >= hi.y ||
      hh.y <= lo.y ||
      hl.z >= hi.z ||
      hh.z <= lo.z) {
    return <Brush>[brush];
  }
  final out = <Brush>[];
  void piece(double x0, double x1, double y0, double y1, double z0, double z1) {
    // Thinner than a millimetre is float32 rounding, not a wall.
    if (x1 - x0 <= 1e-3 || y1 - y0 <= 1e-3 || z1 - z0 <= 1e-3) return;
    out.add(
      Brush(
        centre: Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        size: Vector3(x1 - x0, y1 - y0, z1 - z0),
        material: brush.material,
        solid: brush.solid,
        // The mode and not the boolean: a wall cut in half is still a wall one
        // brush thick, and a `doubleSided` one that came back as `on` would
        // leak light along the seam the hole just made.
        shadowCasting: brush.shadowCasting,
        surface: brush.surface,
        layer: brush.layer,
      ),
    );
  }

  // The hole, clipped to the brush: what is actually removed.
  final cx0 = hl.x > lo.x ? hl.x : lo.x;
  final cx1 = hh.x < hi.x ? hh.x : hi.x;
  final cy0 = hl.y > lo.y ? hl.y : lo.y;
  final cy1 = hh.y < hi.y ? hh.y : hi.y;
  final cz0 = hl.z > lo.z ? hl.z : lo.z;
  final cz1 = hh.z < hi.z ? hh.z : hi.z;

  // Slabs either side along X, full height and depth.
  piece(lo.x, cx0, lo.y, hi.y, lo.z, hi.z);
  piece(cx1, hi.x, lo.y, hi.y, lo.z, hi.z);
  // Within the hole's X range: below and above, full depth.
  piece(cx0, cx1, lo.y, cy0, lo.z, hi.z);
  piece(cx0, cx1, cy1, hi.y, lo.z, hi.z);
  // Within the hole's X and Y range: in front and behind.
  piece(cx0, cx1, cy0, cy1, lo.z, cz0);
  piece(cx0, cx1, cy0, cy1, cz1, hi.z);
  return out;
}

/// The holes a run has blown in its level, and the level with them in it.
///
/// **A breach changes the mesh and the collision together, or it is a
/// picture of a hole.** The walls the player sees are batches built from the
/// level's brushes; the walls the player walks into are colliders built from
/// the same brushes. So a hole is a change to the brush list, from which both
/// follow: this class keeps the current brushes, swaps the colliders of the
/// ones a hole cut for the colliders of what is left, and bumps [version] so
/// whoever draws the level knows to build its batches again.
///
/// ## In the snapshot
///
/// The holes, not the brushes: a hole is six numbers and a cut brush is the
/// original with the holes reapplied, in order. Restoring puts the original
/// colliders back and replays the holes, which is also how a demo of a run
/// with a rocket in it arrives at the same walls.
///
/// ## What a breach does to the rest of the level
///
/// The visibility table was baked from walls without holes in them, and a
/// hole is a new line of sight; the bridge drops the table when it rebuilds
/// the batches, and the level draws everything from then on. The navigation
/// grid keeps its walls: a monster does not learn a new route through a
/// breach, which is a limit and not a bug — it was baked from the brushes,
/// and it is baked once.
///
/// The baked light is kept, and [origins] is how. A lightmap is planned by
/// brush index, and a cut replaces one brush with up to six in its place, so
/// every index after the hole shifts; the pieces remember which brush they
/// came out of, and the geometry hands each face of a piece the texels of the
/// face it is part of.
final class Breaches {
  Breaches(this.level, this.world, {bool Function(Brush)? breakable})
    : breakable = breakable ?? _solidWalls,
      brushes = List<Brush>.of(level.brushes),
      origins = List<int>.generate(level.brushes.length, (int i) => i) {
    _adoptColliders();
  }

  final Level level;
  final CollisionWorld world;

  /// Which brushes a blast can cut. The default is every solid brush that is
  /// not a ramp; a game that wants only its walls to crumble says so here.
  final bool Function(Brush) breakable;

  static bool _solidWalls(Brush brush) => brush.solid && brush.ramp == null;

  /// The level's brushes as they are now: the originals the holes missed and
  /// the pieces of the ones they cut.
  final List<Brush> brushes;

  /// Which brush of the authored level each of [brushes] came out of.
  ///
  /// Same length as [brushes], same order: `origins[i]` indexes
  /// `level.brushes`. A brush no hole has touched points at itself; the six
  /// pieces of a cut one all point at the brush they were cut from, and a
  /// piece cut again keeps pointing at the same original.
  ///
  /// **This is the only thing that survives a cut and is not a brush.** It is
  /// what lets `BrushGeometry.build` carry a lightmap through a breach: the
  /// atlas was planned for the authored brushes, and without a way back to one
  /// of them a piece has no texels of its own. Handed on rather than looked up
  /// by geometry, because a piece is a box like any other box and nothing
  /// about its numbers says which wall it used to be.
  final List<int> origins;

  /// Every hole so far, in the order they were blown.
  final List<Aabb3> holes = <Aabb3>[];

  /// Bumped on every breach, so a renderer can tell the walls changed.
  int get version => _version;
  int _version = 0;

  /// The collider standing for each current brush, for the swap.
  final Map<Brush, Collider> _colliders = <Brush, Collider>{};

  /// Finds the colliders `Level.addTo` made for the brushes, by the brush
  /// each carries as its user data. A brush with no collider — one that is
  /// not solid — has no entry and is never cut.
  void _adoptColliders() {
    for (final collider in world.statics) {
      final data = collider.userData;
      if (data is Brush && level.brushes.contains(data)) {
        _colliders[data] = collider;
      }
    }
  }

  /// Blows a hole where a blast landed on a surface.
  ///
  /// [at] is the point of contact and [normal] the surface's outward normal
  /// there; the hole is [width] across the surface, [height] up it, and
  /// [depth] into it — starting a little outside so the skin comes away too.
  /// Two metres deep by default, which goes through the walls a dungeon has
  /// and not through the level's outer shell if that is thicker.
  void blast(
    Vector3 at,
    Vector3 normal, {
    double width = 1.6,
    double height = 2.0,
    double depth = 2.0,
  }) {
    // The axis the surface faces: the hole's depth runs along it, the other
    // two carry width and height, with height on Y unless the surface is a
    // floor or a ceiling.
    final ax = normal.x.abs();
    final ay = normal.y.abs();
    final az = normal.z.abs();
    final Vector3 half;
    if (ay >= ax && ay >= az) {
      half = Vector3(width / 2, depth / 2, width / 2);
    } else if (ax >= az) {
      half = Vector3(depth / 2, height / 2, width / 2);
    } else {
      half = Vector3(width / 2, height / 2, depth / 2);
    }
    // From a little outside the surface to [depth] inside it, so the hole
    // starts just before the wall rather than leaving a film of it at the
    // entrance, and goes the whole of [depth] into it rather than [depth]
    // less the film.
    const skin = 0.1;
    final near = at + normal * skin;
    final far = at - normal * depth;
    final centre = (near + far) * 0.5;
    final along = (far - near).length / 2;
    if (ay >= ax && ay >= az) {
      half.y = along;
    } else if (ax >= az) {
      half.x = along;
    } else {
      half.z = along;
    }
    hole(Aabb3.minMax(centre - half, centre + half));
  }

  /// Takes [box] out of every breakable brush it overlaps.
  void hole(Aabb3 box) {
    holes.add(Aabb3.copy(box));
    _apply(box);
    _version++;
  }

  void _apply(Aabb3 box) {
    for (var i = brushes.length - 1; i >= 0; i--) {
      final brush = brushes[i];
      if (!breakable(brush)) continue;
      final pieces = subtractBox(brush, box);
      if (pieces.length == 1 && identical(pieces.first, brush)) continue;
      final origin = origins[i];
      brushes.removeAt(i);
      brushes.insertAll(i, pieces);
      origins.removeAt(i);
      origins.insertAll(i, List<int>.filled(pieces.length, origin));
      final old = _colliders.remove(brush);
      if (old != null) world.remove(old);
      for (final piece in pieces) {
        if (old == null) continue;
        _colliders[piece] = world.add(
          Collider(
            shape: CollisionBox(piece.halfExtents),
            position: piece.centre,
            layer: piece.layer ?? CollisionLayers.world,
            userData: piece,
          ),
        );
      }
    }
  }

  /// The holes, as six numbers each.
  Map<String, Object?> save() => <String, Object?>{
    'holes': <List<double>>[
      for (final hole in holes)
        <double>[
          hole.min.x,
          hole.min.y,
          hole.min.z,
          hole.max.x,
          hole.max.y,
          hole.max.z,
        ],
    ],
  };

  /// Puts the level back and blows the saved holes again, in order.
  void restore(Map<String, Object?> from) {
    // Back to the level as authored: the pieces' colliders out, the
    // originals' in.
    for (final collider in _colliders.values) {
      world.remove(collider);
    }
    _colliders.clear();
    brushes
      ..clear()
      ..addAll(level.brushes);
    origins
      ..clear()
      ..addAll(List<int>.generate(level.brushes.length, (int i) => i));
    for (final brush in level.brushes) {
      if (!brush.solid) continue;
      final ramp = brush.ramp;
      _colliders[brush] = world.add(
        Collider(
          shape: ramp == null
              ? CollisionBox(brush.halfExtents)
              : CollisionWedge(brush.halfExtents, uphill: ramp),
          position: brush.centre,
          layer: brush.layer ?? CollisionLayers.world,
          userData: brush,
        ),
      );
    }
    holes.clear();
    final saved = from['holes'];
    if (saved is List<Object?>) {
      for (final entry in saved) {
        if (entry is! List<Object?> || entry.length != 6) continue;
        final n = <double>[for (final v in entry) (v! as num).toDouble()];
        final box = Aabb3.minMax(
          Vector3(n[0], n[1], n[2]),
          Vector3(n[3], n[4], n[5]),
        );
        holes.add(box);
        _apply(box);
      }
    }
    _version++;
  }
}
