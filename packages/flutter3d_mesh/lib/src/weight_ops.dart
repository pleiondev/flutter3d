import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';

/// One joint's pull on a vertex, before it is capped to the four slots
/// [VertexAttributes] actually stores — `mesh-60`'s own row.
///
/// `EditMesh.skinOf`/`setSkin` already carry a vertex's *stored* binding as a
/// fixed `Vector4` pair, because that is what the shader reads. A weight
/// brush accumulating strokes from several overlapping sources — or a vertex
/// a split has pulled influence from both sides of, `mesh-61`'s own
/// `VertexAttributes.lerp` already does this for exactly two sources — can
/// have more candidates than four slots hold before it is time to write
/// back. [WeightPair] is that wider, unbounded form; [weightsOf] reads the
/// stored four out as pairs, [limitInfluences] and [normalizeWeights] work on
/// them, and [toVertexAttributes] is the trip back down to what `setSkin`
/// wants.
final class WeightPair {
  const WeightPair(this.joint, this.weight);

  final int joint;
  final double weight;

  @override
  String toString() => 'WeightPair($joint, $weight)';
}

/// The weights stored at [vertex], as pairs rather than fixed `Vector4`
/// slots — zero-weight slots dropped, since they name no influence at all.
///
/// **A vertex nobody has ever skinned reads as one pair, joint 0 at full
/// weight — but only while that is true of the whole mesh.** That default
/// is [EditMesh.skinOf]'s own answer for "no binding was ever set", and it
/// only applies while the weights/joints layers themselves have never been
/// allocated. The first [EditMesh.setSkin] call on *any* vertex allocates
/// both layers for every vertex slot, zero-filled; every other,
/// still-unpainted vertex then reads its own real, stored zeros — an empty
/// list here, not a joint-0 default — because the mesh now has an actual
/// answer for that vertex rather than a placeholder for the whole thing.
///
/// The inverse of writing through [EditMesh.setSkin] by way of
/// [toVertexAttributes]: `toVertexAttributes(weightsOf(mesh, v))` round-trips
/// whatever was stored, up to the reordering [limitInfluences]' own sort by
/// weight makes irrelevant anyway.
List<WeightPair> weightsOf(EditMesh mesh, int vertex) {
  final skin = mesh.skinOf(vertex);
  return <WeightPair>[
    for (var i = 0; i < 4; i++)
      if (skin.weights[i] > 0) WeightPair(skin.joints[i].round(), skin.weights[i]),
  ];
}

/// Scales [pairs] so their weights sum to one.
///
/// A [pairs] whose weights already sum to (near) zero is returned unchanged
/// — nothing to spread across, and scaling by a near-zero divisor is how a
/// vertex an operation accidentally zeroed out turns into one with a single
/// joint at full, invented weight instead of staying at none.
List<WeightPair> normalizeWeights(List<WeightPair> pairs) {
  final total = pairs.fold<double>(0, (sum, pair) => sum + pair.weight);
  if (total <= 1e-9) return pairs;
  return <WeightPair>[
    for (final pair in pairs) WeightPair(pair.joint, pair.weight / total),
  ];
}

/// Keeps the [maxInfluences] largest weights in [pairs] and renormalizes what
/// is left, dropping non-positive weights first.
///
/// The renormalize is not a separate step a caller can skip: `mesh-60`'s own
/// acceptance line is "5 bones → 4, sum 1±1e-6", not "4 of the original
/// weights, summing to whatever is left of one" — the same rule
/// `VertexAttributes.lerp` already applies when a split gathers up to eight
/// candidates from its two source vertices, given a name here so a paint
/// stroke's own wider accumulation (`anim-09`, not yet built) can reach for
/// it instead of re-deriving the truncate-then-renormalize by hand.
List<WeightPair> limitInfluences(List<WeightPair> pairs, int maxInfluences) {
  final positive = pairs.where((pair) => pair.weight > 0).toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));
  final kept = positive.take(maxInfluences).toList(growable: false);
  return normalizeWeights(kept);
}

/// [pairs] as a fixed four-slot [VertexAttributes], the form `setSkin` wants.
///
/// Takes at most the four largest by way of [limitInfluences] first when
/// [pairs] holds more than four — the shader has no fifth slot to put a
/// fifth candidate in, whether or not the caller already capped it.
VertexAttributes toVertexAttributes(List<WeightPair> pairs) {
  final capped = pairs.length > 4 ? limitInfluences(pairs, 4) : pairs;
  final joints = List<double>.filled(4, 0.0);
  final weights = List<double>.filled(4, 0);
  for (var i = 0; i < capped.length; i++) {
    joints[i] = capped[i].joint.toDouble();
    weights[i] = capped[i].weight;
  }
  return VertexAttributes(
    joints: Vector4(joints[0], joints[1], joints[2], joints[3]),
    weights: Vector4(weights[0], weights[1], weights[2], weights[3]),
  );
}
