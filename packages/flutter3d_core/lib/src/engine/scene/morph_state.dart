import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../animation/morph_sink.dart';

/// What one drawn mesh is morphing towards, and by how much.
///
/// **The deltas are shared and the weights are not.** Two copies of one model
/// draw from the same delta texture and must be able to wear different
/// expressions, exactly as two copies of a rigged model share a mesh and pose
/// from their own skeletons. So this lives on the node and the texture it
/// points at lives with the geometry.
///
/// The renderer reads [weights] once per draw and writes them into the uniform
/// the vertex stage reads — see `lib/morph.glsl`. Nothing here is recomputed:
/// a weight is set by an animation clip, by a game, or by nobody, and the cost
/// of a face holding an expression is the same as the cost of one at rest.
final class MorphState implements MorphSink {
  MorphState({
    required this.texture,
    required int targetCount,
    List<Aabb3>? reaches,
  }) : weights = List<double>.filled(targetCount, 0.0),
       _reaches = reaches ?? const <Aabb3>[];

  /// The packed deltas, uploaded once with the mesh.
  final TextureHandle texture;

  /// One weight per target, from nought to one, in the order the file had them.
  ///
  /// Mutable and mutable in place: this is written every frame by whatever is
  /// driving the face, and a list rebuilt per frame would be an allocation per
  /// model per frame for a value that almost never changes.
  final List<double> weights;

  int get targetCount => weights.length;

  /// The box each target's deltas span, in the mesh's own space,
  /// index-aligned with [weights]. Empty when the caller did not say.
  final List<Aabb3> _reaches;

  /// Bumped whenever a weight changes, so a bounding box can tell whether the
  /// shape it was fitted to is still the shape being drawn.
  int get version => _version;
  int _version = 0;

  /// How far past the mesh's own bounds this expression puts a vertex, per
  /// axis and in each direction.
  ///
  /// **A bounding box has to be told.** A mesh's bounds describe its base
  /// vertices, so a face that opens its jaw past that box is culled while it is
  /// on screen and its shadow leaves the cascade fitted to it — the same trap
  /// skinning has, closed there by `MeshNode.skinReach`. It cost this feature a
  /// whole model once: a cube whose target slid it twelve metres sideways drew
  /// nothing at all, because the frustum was tested against a box half a metre
  /// wide back at the origin.
  ///
  /// The sum of the targets' boxes scaled by their weights, which is the exact
  /// span of the sum — two shapes at half strength can reach where neither
  /// alone does. A negative weight swaps a box's ends rather than being taken
  /// as its size, because glTF permits one and it moves a vertex the other way.
  ///
  /// Per axis rather than a radius, for the reason `MorphTarget.displacement`
  /// gives: a radius grows the box in directions the deltas never point, and on
  /// a model whose targets are large next to itself that is the difference
  /// between a subject filling a frame and a third of one.
  Aabb3 get growth {
    if (_reachVersion == _version) return _growth;
    _reachVersion = _version;
    _growth.min.setZero();
    _growth.max.setZero();
    for (var i = 0; i < weights.length && i < _reaches.length; i++) {
      final weight = weights[i];
      if (weight == 0.0) continue;
      final span = _reaches[i];
      // A negative weight sends the low end high and the high end low.
      final low = weight > 0.0 ? span.min : span.max;
      final high = weight > 0.0 ? span.max : span.min;
      _growth.min.addScaled(low, weight);
      _growth.max.addScaled(high, weight);
    }
    return _growth;
  }

  /// Whether this expression moves anything at all, for a caller deciding
  /// whether to widen a box.
  bool get grows => _reaches.isNotEmpty;

  final Aabb3 _growth = Aabb3();
  int _reachVersion = -1;

  /// Sets every weight from [values], ignoring any past the end.
  ///
  /// The shape an animation clip's weights track arrives in — see [MorphSink],
  /// which is how a player reaches this without the scene graph reaching back.
  /// Longer is
  /// tolerated for the reason `MorphBlend` gives — a clip authored against a
  /// model with more shapes is worth playing — and shorter leaves the rest at
  /// nought rather than at whatever they were, so a clip that stops mentioning
  /// a shape relaxes it instead of freezing it.
  @override
  void setWeights(List<double> values) {
    for (var i = 0; i < weights.length; i++) {
      final value = i < values.length ? values[i] : 0.0;
      if (weights[i] != value) {
        weights[i] = value;
        _version++;
      }
    }
  }

  @override
  String toString() => 'MorphState($targetCount targets)';
}
