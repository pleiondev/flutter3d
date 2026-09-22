/// Automatic skin-weight computation — `anim-22`'s own row: distance to bone
/// segments, visibility through the mesh's own [TriangleBvh], then
/// smooth/mirror/prune/normalize as explicit passes over the raw result.
///
/// **Distance, not heat diffusion.** The plan's own row text names heat
/// diffusion and says "after" — a later row's own job, not this one's. What
/// this gives a fresh rig is the same starting point a modeller's brush
/// (`anim-10`'s own `paintWeight`) already touches up afterwards: close
/// enough to be useful, not a physically-simulated diffusion.
///
/// **Why visibility matters more than distance here.** A cylinder with two
/// legs standing side by side has vertices on the inner thigh of one leg
/// closer, in straight-line distance, to the *other* leg's bone than a
/// vertex on the same leg's own outer wall is to its own bone's far end.
/// Distance alone binds those vertices to both legs and a walk cycle tears
/// the mesh apart at the crotch. A bone's own segment sits *inside* the
/// volume its own limb's mesh encloses — the leg's own wall is between the
/// bone and anything outside that leg — so a straight-line visibility test
/// against the mesh's own [TriangleBvh] tells the two cases apart: a bone
/// reached without crossing any triangle is this vertex's own limb; a bone
/// only reached by first punching through some wall belongs to a limb nothing
/// here should bind to.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart'
    show WeightPair, normalizeWeights;
import 'package:vector_math/vector_math.dart' hide Ray;

import 'bone_map.dart';
import 'portable_pow.dart';

/// [WeightPair] is `flutter3d_mesh`'s own type, and every function on this
/// page hands one back or takes one in — exported here so a caller of
/// `bindWeights` never has to add that package as a dependency of its own
/// just to spell the return type.
export 'package:flutter3d_mesh/flutter3d_mesh.dart' show WeightPair;

/// Simultaneous bone influences a vertex may keep — the plan's own decision
/// log entry З1, "four influences as a hard limit"
/// (`doc/model-editor-plan.md`), the same cap `flutter3d_mesh`'s
/// `toVertexAttributes` bakes into storage. [pruneSkinWeights]' own default.
const int kMaxSkinInfluences = 4;

/// One bone, as the line segment [bindWeights] measures distance and
/// visibility against — [head] to [tail], both bind-pose world positions.
///
/// The rig algorithms have no `Skeleton`/`Joint` type of their own: `anim-21`'s
/// own `ProjectSkeleton` (this package's `rig_template.dart`) addresses
/// a joint only by a single rest *position*, one level up, alongside a
/// `ModelProject` that knows each joint's parent. A [BoneSegment] is what
/// turns that into the shape this row needs — ordinarily a parent joint's own
/// world position as [head] and its child's as [tail], one per non-root
/// joint — without the algorithm reaching for `ModelProject` itself.
final class BoneSegment {
  const BoneSegment(this.head, this.tail, {this.name});

  final Vector3 head;
  final Vector3 tail;

  /// This bone's own name, in `bone_map.dart`'s own left/right convention
  /// (`leftKnee`/`rightKnee`, `anim-17`'s own [humanoidBoneNames]) — what
  /// [mirrorSkinWeights] reads, through [mirrorBoneName], to find a bone's
  /// mirror partner. Left `null` for a caller with no naming scheme; that
  /// bone's own influence is then left unmirrored.
  final String? name;

  @override
  String toString() =>
      'BoneSegment($head -> $tail${name == null ? '' : ', $name'})';
}

/// [point]'s closest position on the segment [a]-[b], clamped to the segment
/// rather than the infinite line.
Vector3 _closestPointOnSegment(Vector3 point, Vector3 a, Vector3 b) {
  final ab = b - a;
  final lengthSquared = ab.length2;
  if (lengthSquared < 1e-12) return a.clone();
  var t = (point - a).dot(ab) / lengthSquared;
  if (t < 0.0) {
    t = 0.0;
  } else if (t > 1.0) {
    t = 1.0;
  }
  return a + ab.scaled(t);
}

/// Every vertex directly joined to another by a triangle edge in [triangles]
/// (flat triples of vertex indices) — the "mesh adjacency"
/// [smoothSkinWeights] blends against, built straight from the same triangle
/// list [bindWeights]' own [TriangleBvh] indexes, so a caller supplies the
/// mesh's shape exactly once.
Map<int, List<int>> vertexAdjacency(List<int> triangles) {
  final neighbors = <int, Set<int>>{};
  void link(int a, int b) {
    (neighbors[a] ??= <int>{}).add(b);
    (neighbors[b] ??= <int>{}).add(a);
  }

  for (var i = 0; i + 2 < triangles.length; i += 3) {
    final a = triangles[i];
    final b = triangles[i + 1];
    final c = triangles[i + 2];
    link(a, b);
    link(b, c);
    link(c, a);
  }
  return <int, List<int>>{
    for (final entry in neighbors.entries)
      entry.key: entry.value.toList(growable: false),
  };
}

TriangleBvh _buildBvh(List<Vector3> positions, List<int> triangles) {
  final flat = Float32List(positions.length * 3);
  for (var i = 0; i < positions.length; i++) {
    flat[i * 3] = positions[i].x;
    flat[i * 3 + 1] = positions[i].y;
    flat[i * 3 + 2] = positions[i].z;
  }
  return TriangleBvh.fromArrays(flat, Uint32List.fromList(triangles));
}

/// Whether a straight line from [from] to [to] reaches [to] without crossing
/// any triangle of [bvh] — [bindWeights]' own "видимость по BVH".
///
/// The ray starts a small step past [from] along its own direction rather
/// than exactly at it, so it does not immediately register a hit against the
/// very triangles [from] itself sits on — a vertex is always on the surface
/// of *some* face, and without the offset every test would report itself as
/// occluded by its own mesh.
bool _isVisible(TriangleBvh bvh, Vector3 from, Vector3 to) {
  final delta = to - from;
  final distance = delta.length;
  if (distance < 1e-9) return true;

  final direction = delta.scaled(1.0 / distance);
  final skip = math.min(distance * 0.5, 1e-4 + distance * 1e-3);
  final origin = from + direction.scaled(skip);
  final remaining = distance - skip;
  if (remaining <= 0.0) return true;

  final ray = Ray(origin, direction);
  final hit = bvh.raycast(ray, maxDistance: remaining);
  return hit == null;
}

/// Computes raw, un-pruned, un-normalized per-vertex bone weights for
/// [positions] (bind-pose vertex positions) against [bones], using inverse
/// distance to each bone's own segment and — when [useVisibility] is true —
/// a [TriangleBvh] built over [triangles] (flat vertex-index triples) to drop
/// a bone a vertex has no straight line of sight to.
///
/// **Raw, deliberately.** This is the plan's own "raw per-vertex weight map"
/// — [pruneSkinWeights], [normalizeSkinWeights], [smoothSkinWeights] and
/// [mirrorSkinWeights] are separate passes a caller chains afterwards, the
/// same way `anim-09`'s own paint operations are separate primitives rather
/// than one function that does everything.
///
/// A vertex with no [bones] entry left visible (every one occluded — the
/// degenerate case of a vertex sealed inside geometry nothing else reaches)
/// falls back to every bone's raw distance weight unmasked, so a vertex is
/// never left bound to nothing.
///
/// The result addresses bones by their position in [bones] — the same local
/// index [WeightPair.joint] already means elsewhere in this engine — not by
/// any [ModelObject] id; a caller maps that back itself.
Map<int, List<WeightPair>> bindWeights({
  required List<Vector3> positions,
  required List<int> triangles,
  required List<BoneSegment> bones,
  double falloffPower = 2.0,
  bool useVisibility = true,
  double epsilon = 1e-4,
}) {
  if (bones.isEmpty) return <int, List<WeightPair>>{};

  final bvh = useVisibility ? _buildBvh(positions, triangles) : null;
  final result = <int, List<WeightPair>>{};

  for (var v = 0; v < positions.length; v++) {
    final vertex = positions[v];
    final closestPoints = <Vector3>[
      for (final bone in bones)
        _closestPointOnSegment(vertex, bone.head, bone.tail),
    ];
    final raw = <double>[
      for (final closest in closestPoints)
        1.0 / powPositive((closest - vertex).length + epsilon, falloffPower),
    ];

    var visible = List<bool>.filled(bones.length, true);
    if (bvh != null) {
      visible = <bool>[
        for (var i = 0; i < bones.length; i++)
          _isVisible(bvh, vertex, closestPoints[i]),
      ];
      if (!visible.any((value) => value)) {
        // Nothing survived visibility: fall back to raw distance rather than
        // leave this vertex bound to no bone at all.
        visible = List<bool>.filled(bones.length, true);
      }
    }

    result[v] = <WeightPair>[
      for (var i = 0; i < bones.length; i++)
        if (visible[i]) WeightPair(i, raw[i]),
    ];
  }
  return result;
}

/// Drops influences below [threshold] and keeps at most [maxInfluences] of
/// what remains (the largest ones), for every vertex in [weights].
///
/// **Not a renormalize.** [normalizeSkinWeights] is the separate pass for
/// that, per the plan's own "prune" and "normalize" as two named steps
/// rather than one — a caller wanting the ordinary pipeline runs this first
/// and normalizes after, so the influences it drops here do not skew what
/// the survivors are renormalized against them by their weight-before-drop.
Map<int, List<WeightPair>> pruneSkinWeights(
  Map<int, List<WeightPair>> weights, {
  int maxInfluences = kMaxSkinInfluences,
  double threshold = 1e-3,
}) => <int, List<WeightPair>>{
  for (final entry in weights.entries)
    entry.key:
        (entry.value.where((pair) => pair.weight >= threshold).toList()
              ..sort((a, b) => b.weight.compareTo(a.weight)))
            .take(maxInfluences)
            .toList(growable: false),
};

/// Rescales every vertex's own weights in [weights] to sum to one, via
/// `flutter3d_mesh`'s own [normalizeWeights] — the same renormalize
/// `anim-09`'s paint operations already use, so a seam vertex bound equally
/// to two bones reads as exactly 0.5/0.5 rather than half of whatever the
/// raw falloff happened to sum to.
Map<int, List<WeightPair>> normalizeSkinWeights(
  Map<int, List<WeightPair>> weights,
) => <int, List<WeightPair>>{
  for (final entry in weights.entries) entry.key: normalizeWeights(entry.value),
};

/// Blends each vertex in [weights] [lambda] of the way toward the average of
/// its own [adjacency] neighbours' weights, [iterations] times —
/// [vertexAdjacency]'s own consumer, and the same shrink-resistant Laplacian
/// shape `flutter3d_mesh`'s `smoothVertexWeights` already applies to an
/// `EditMesh` directly, worked out here over the plain vertex-index map
/// [bindWeights] itself produces instead.
///
/// Reads every vertex's weights before writing any of them back, each pass,
/// so a vertex order does not change the result: otherwise a vertex earlier
/// in iteration order would blend toward a neighbour's *already-blended*
/// weights from the same pass.
Map<int, List<WeightPair>> smoothSkinWeights(
  Map<int, List<WeightPair>> weights,
  Map<int, List<int>> adjacency, {
  double lambda = 0.5,
  int iterations = 1,
}) {
  var current = weights;
  for (var iteration = 0; iteration < iterations; iteration++) {
    final next = <int, List<WeightPair>>{};
    for (final vertex in current.keys) {
      final neighbors = adjacency[vertex] ?? const <int>[];
      if (neighbors.isEmpty) {
        next[vertex] = current[vertex]!;
        continue;
      }

      final own = <int, double>{
        for (final pair in current[vertex]!) pair.joint: pair.weight,
      };
      final average = <int, double>{};
      for (final neighbor in neighbors) {
        for (final pair in current[neighbor] ?? const <WeightPair>[]) {
          average[pair.joint] =
              (average[pair.joint] ?? 0) + pair.weight / neighbors.length;
        }
      }

      final joints = <int>{...own.keys, ...average.keys};
      next[vertex] = <WeightPair>[
        for (final joint in joints)
          WeightPair(
            joint,
            (own[joint] ?? 0) +
                ((average[joint] ?? 0) - (own[joint] ?? 0)) * lambda,
          ),
      ];
    }
    current = next;
  }
  return current;
}

double _axisComponent(Vector3 v, int axis) => switch (axis) {
  0 => v.x,
  1 => v.y,
  _ => v.z,
};

Vector3 _withAxisComponent(Vector3 v, int axis, double value) => switch (axis) {
  0 => Vector3(value, v.y, v.z),
  1 => Vector3(v.x, value, v.z),
  _ => Vector3(v.x, v.y, value),
};

/// Copies each vertex's weights in [weights] onto its mirror image across
/// the plane perpendicular to [axis] (`0`=x, `1`=y, `2`=z, matching
/// `flutter3d_mesh`'s own `mirrorWeights` convention) at [plane], remapping
/// bone indices through [bones]' own names via [mirrorBoneName] —
/// `anim-17`'s own left/right dictionary, reused rather than a second naming
/// scheme invented here.
///
/// A bone with no [BoneSegment.name] (or a mirrored name absent from
/// [bones]) keeps its own index unmirrored — the same fallback a centerline
/// bone straddling the plane wants. Pairing a vertex with its mirror image is
/// a nearest-position search among [positions]' own keys in [weights], not a
/// stored one-to-one map, so it only makes sense for a mesh symmetric enough
/// to mirror at all — [mirrorWeights]' own same restriction.
Map<int, List<WeightPair>> mirrorSkinWeights(
  Map<int, List<WeightPair>> weights,
  List<Vector3> positions,
  List<BoneSegment> bones, {
  int axis = 0,
  double plane = 0.0,
  double tolerance = 1e-4,
}) {
  final boneIndexByName = <String, int>{
    for (var i = 0; i < bones.length; i++)
      if (bones[i].name != null) bones[i].name!: i,
  };
  int mirrorOf(int joint) {
    if (joint < 0 || joint >= bones.length) return joint;
    final name = bones[joint].name;
    if (name == null) return joint;
    return boneIndexByName[mirrorBoneName(name)] ?? joint;
  }

  final vertices = weights.keys.toList(growable: false);
  final result = <int, List<WeightPair>>{
    for (final entry in weights.entries) entry.key: entry.value,
  };

  for (final vertex in vertices) {
    // Nothing to copy from an unbound vertex — and, more to the point,
    // running it anyway would overwrite an already-mirrored partner with
    // emptiness the moment iteration reached the *un*bound side of a pair.
    if (weights[vertex]!.isEmpty) continue;

    final own = _axisComponent(positions[vertex], axis);
    if ((own - plane).abs() <= tolerance) continue;

    final target = _withAxisComponent(positions[vertex], axis, 2 * plane - own);

    int? best;
    var bestDistance = double.infinity;
    for (final candidate in vertices) {
      if (candidate == vertex) continue;
      final distance = (positions[candidate] - target).length;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    if (best == null || bestDistance > tolerance) continue;

    result[best] = <WeightPair>[
      for (final pair in weights[vertex]!)
        WeightPair(mirrorOf(pair.joint), pair.weight),
    ];
  }
  return result;
}
