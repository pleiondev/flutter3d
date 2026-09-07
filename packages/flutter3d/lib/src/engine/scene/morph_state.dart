import 'package:flutter3d_hardware/flutter3d_hardware.dart';

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
  MorphState({required this.texture, required int targetCount})
    : weights = List<double>.filled(targetCount, 0.0);

  /// The packed deltas, uploaded once with the mesh.
  final TextureHandle texture;

  /// One weight per target, from nought to one, in the order the file had them.
  ///
  /// Mutable and mutable in place: this is written every frame by whatever is
  /// driving the face, and a list rebuilt per frame would be an allocation per
  /// model per frame for a value that almost never changes.
  final List<double> weights;

  int get targetCount => weights.length;

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
      weights[i] = i < values.length ? values[i] : 0.0;
    }
  }

  @override
  String toString() => 'MorphState($targetCount targets)';
}
