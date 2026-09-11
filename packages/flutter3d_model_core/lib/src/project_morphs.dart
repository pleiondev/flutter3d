/// A shape set: an object's own shape keys and their current preview
/// weights — `anim-19`'s own `ShapeSet`.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

/// [keys] and [weights] are index-aligned: `weights[i]` is how much
/// `keys[i]` currently pulls toward its own sculpted shape, the same
/// `base + Σ weightᵢ × deltaᵢ` blend `ShapeKey.blend` already computes.
///
/// **Lives on [ModelObject] directly, not inside [EditedGeometry].** A
/// shape key's own position count has to track `EditMesh`'s topology
/// through every edit that changes it — [ShapeKey.grownTo]/[remappedBy]
/// are how — and wiring that into every mesh-mutating command in this
/// package is a far larger change than this row's own five operations.
/// Keeping [ShapeSet] a plain field `ModelObject.copyWith` already carries
/// through unchanged means no existing call site has to change to avoid
/// silently dropping it — the same reasoning that put `skeletonIndex`
/// there rather than folding it into `EditedGeometry` too. What a shape
/// set does not yet do is stay in step with a topology-changing edit on
/// its own — the same, already-declared gap `mesh-61` left open.
final class ShapeSet {
  const ShapeSet({this.keys = const <ShapeKey>[], this.weights = const <double>[]});

  final List<ShapeKey> keys;
  final List<double> weights;

  bool get isEmpty => keys.isEmpty;

  ShapeSet copyWith({List<ShapeKey>? keys, List<double>? weights}) =>
      ShapeSet(keys: keys ?? this.keys, weights: weights ?? this.weights);

  @override
  String toString() => 'ShapeSet(${keys.length} keys)';
}
