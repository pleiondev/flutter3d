/// Authoring operations over the weights `mesh-60`'s storage already holds —
/// `anim-09`'s own row: `paintWeight`, `normalizeVertexWeights`,
/// `pruneVertexWeights`, `mirrorWeights`, `smoothVertexWeights`,
/// `gradientWeights`, `assignSelection`.
///
/// **Named for what they do rather than the plan's own two shorter names.**
/// The row calls out `VertexWeights` and `pruneTo`; there is no
/// `VertexWeights` type here — a vertex's weights are `mesh-60`'s own
/// `WeightPair` list, and a persistent *class* wrapping that list would hold
/// no state of its own beyond what `EditMesh` already stores — and `pruneTo`
/// is [pruneVertexWeights], named to read the same way as its five siblings
/// once `paint`/`normalize`/`mirror`/`smooth`/`gradient` all needed the
/// `...Weights`/`Vertex...` disambiguation from their one-word forms in the
/// plan.
///
/// **What is not here.** A brush's own sampling, falloff and BVH picking
/// (`anim-10`) and turning a weight into a displayed vertex colour
/// (`anim-11`/`view-18`) are separate, later rows that read or call these —
/// [paintWeight] is the one-vertex primitive a brush calls per hit, not the
/// brush itself.
library;

import 'package:vector_math/vector_math.dart';

import '../edit_mesh.dart';
import '../weight_ops.dart';

/// Adds [strength] to [joint]'s pull on [vertex]: accumulates onto whatever
/// is already stored, or creates a new influence when [joint] was not one of
/// them, then caps to [maxInfluences] and renormalizes — `mesh-60`'s own
/// truncate-and-renormalize, wired to one vertex at a time.
void paintWeight(
  EditMesh mesh,
  int vertex,
  int joint,
  double strength, {
  int maxInfluences = 4,
}) {
  final merged = <int, double>{
    for (final pair in weightsOf(mesh, vertex)) pair.joint: pair.weight,
  };
  merged[joint] = (merged[joint] ?? 0) + strength;
  final capped = limitInfluences(<WeightPair>[
    for (final entry in merged.entries) WeightPair(entry.key, entry.value),
  ], maxInfluences);
  mesh.setSkin(vertex, toVertexAttributes(capped));
}

/// Renormalizes [vertex]'s stored weights to sum to one, without changing
/// which joints they name or how many there are.
void normalizeVertexWeights(EditMesh mesh, int vertex) {
  mesh.setSkin(
    vertex,
    toVertexAttributes(normalizeWeights(weightsOf(mesh, vertex))),
  );
}

/// Truncates [vertex]'s stored weights to its [maxInfluences] largest and
/// renormalizes what is left.
void pruneVertexWeights(EditMesh mesh, int vertex, int maxInfluences) {
  mesh.setSkin(
    vertex,
    toVertexAttributes(limitInfluences(weightsOf(mesh, vertex), maxInfluences)),
  );
}

/// Sets every vertex in [vertices] to [weight] at [joint], dropping every
/// other influence — a hard "this whole selection belongs to this bone"
/// rather than [paintWeight]'s accumulation onto whatever was already there.
void assignSelection(
  EditMesh mesh,
  Iterable<int> vertices,
  int joint,
  double weight,
) {
  for (final vertex in vertices) {
    mesh.setSkin(
      vertex,
      toVertexAttributes(<WeightPair>[WeightPair(joint, weight)]),
    );
  }
}

/// Copies weights from each of [vertices] onto its mirror image across the
/// plane perpendicular to [axis] (`0`=x, `1`=y, `2`=z) at [plane], remapping
/// joints through [jointMirror] — a joint absent from [jointMirror] keeps
/// its own index, which is what a spine or a head bone straddling the plane
/// wants.
///
/// A vertex within [tolerance] of the plane is left alone, since there is no
/// "other side" for it to be paired with. Pairing is a nearest-position
/// search among [vertices] for each one, not a stable one-to-one matching —
/// correct for a mesh symmetric enough to mirror at all, which is the only
/// case this is for.
void mirrorWeights(
  EditMesh mesh,
  Iterable<int> vertices, {
  required int axis,
  required Map<int, int> jointMirror,
  double plane = 0.0,
  double tolerance = 1e-4,
}) {
  final list = vertices.toList(growable: false);
  final positions = <int, Vector3>{for (final v in list) v: mesh.positionOf(v)};

  for (final vertex in list) {
    final own = _axisComponent(positions[vertex]!, axis);
    if ((own - plane).abs() <= tolerance) continue;

    final target = Vector3.copy(positions[vertex]!);
    _setAxisComponent(target, axis, 2 * plane - own);

    int? best;
    var bestDistance = double.infinity;
    for (final candidate in list) {
      if (candidate == vertex) continue;
      final distance = (positions[candidate]! - target).length;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    if (best == null || bestDistance > tolerance) continue;

    final remapped = <WeightPair>[
      for (final pair in weightsOf(mesh, vertex))
        WeightPair(jointMirror[pair.joint] ?? pair.joint, pair.weight),
    ];
    mesh.setSkin(best, toVertexAttributes(remapped));
  }
}

/// Blends each of [vertices]' own weights [lambda] of the way toward the
/// average of its neighbours' weights, [iterations] times — the same
/// shrink-resistant-for-noise Laplacian `smoothVertices` already applies to
/// position, aimed at a weight vector instead. Softens a hard paint edge
/// without needing anyone to have first smoothed the mesh's shape.
///
/// Reads every vertex's weights before writing any of them back, each pass —
/// otherwise a vertex earlier in [vertices] would blend toward its
/// neighbour's *already-blended* weights this same pass, and the result
/// would depend on iteration order rather than only on neighbour count.
void smoothVertexWeights(
  EditMesh mesh,
  Iterable<int> vertices, {
  double lambda = 0.5,
  int iterations = 1,
  int maxInfluences = 4,
}) {
  final list = vertices.toList(growable: false);
  for (var iteration = 0; iteration < iterations; iteration++) {
    final next = <int, List<WeightPair>>{};
    for (final vertex in list) {
      final neighbors = mesh.neighborsOf(vertex);
      if (neighbors.isEmpty) continue;

      final own = <int, double>{
        for (final pair in weightsOf(mesh, vertex)) pair.joint: pair.weight,
      };
      final average = <int, double>{};
      for (final neighbor in neighbors) {
        for (final pair in weightsOf(mesh, neighbor)) {
          average[pair.joint] =
              (average[pair.joint] ?? 0) + pair.weight / neighbors.length;
        }
      }

      final joints = <int>{...own.keys, ...average.keys};
      final blended = <WeightPair>[
        for (final joint in joints)
          WeightPair(
            joint,
            (own[joint] ?? 0) +
                ((average[joint] ?? 0) - (own[joint] ?? 0)) * lambda,
          ),
      ];
      next[vertex] = limitInfluences(blended, maxInfluences);
    }
    for (final entry in next.entries) {
      mesh.setSkin(entry.key, toVertexAttributes(entry.value));
    }
  }
}

/// Blends [vertices] linearly from [jointA] at full weight where their
/// position projects to [start] along the line to [end], to [jointB] at
/// full weight at [end] — a rig's own "paint this whole limb as one smooth
/// gradient" starting point, before a brush touches up the seams. The
/// projection `t` is clamped to `[0, 1]`, so a vertex beyond either end is
/// left fully on the joint at that end rather than extrapolated past it.
void gradientWeights(
  EditMesh mesh,
  Iterable<int> vertices, {
  required int jointA,
  required int jointB,
  required Vector3 start,
  required Vector3 end,
}) {
  final axis = end - start;
  final lengthSquared = axis.length2;
  for (final vertex in vertices) {
    final offset = mesh.positionOf(vertex) - start;
    final t = lengthSquared <= 1e-12
        ? 0.0
        : (offset.dot(axis) / lengthSquared).clamp(0.0, 1.0);
    mesh.setSkin(
      vertex,
      toVertexAttributes(<WeightPair>[
        if (t < 1.0) WeightPair(jointA, 1.0 - t),
        if (t > 0.0) WeightPair(jointB, t),
      ]),
    );
  }
}

double _axisComponent(Vector3 v, int axis) => switch (axis) {
  0 => v.x,
  1 => v.y,
  _ => v.z,
};

void _setAxisComponent(Vector3 v, int axis, double value) {
  switch (axis) {
    case 0:
      v.x = value;
    case 1:
      v.y = value;
    default:
      v.z = value;
  }
}
