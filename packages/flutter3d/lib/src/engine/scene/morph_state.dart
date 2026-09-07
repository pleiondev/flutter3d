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
  MorphState({
    required this.texture,
    required int targetCount,
    List<double>? reaches,
  }) : weights = List<double>.filled(targetCount, 0.0),
       _reaches = reaches ?? const <double>[];

  /// The packed deltas, uploaded once with the mesh.
  final TextureHandle texture;

  /// One weight per target, from nought to one, in the order the file had them.
  ///
  /// Mutable and mutable in place: this is written every frame by whatever is
  /// driving the face, and a list rebuilt per frame would be an allocation per
  /// model per frame for a value that almost never changes.
  final List<double> weights;

  int get targetCount => weights.length;

  /// How far each target moves the vertex it moves most, in the mesh's own
  /// space, index-aligned with [weights]. Empty when the caller did not say.
  final List<double> _reaches;

  /// Bumped whenever a weight changes, so a bounding box can tell whether the
  /// shape it was fitted to is still the shape being drawn.
  int get version => _version;
  int _version = 0;

  /// How far past the mesh's own bounds this expression can put a vertex.
  ///
  /// **A bounding box has to be told.** A mesh's bounds describe its base
  /// vertices, so a face that opens its jaw past that box is culled while it is
  /// on screen and its shadow leaves the cascade fitted to it — the same trap
  /// skinning has, closed there by `MeshNode.skinReach`. It cost this feature a
  /// whole model once: a cube whose target slid it twelve metres sideways drew
  /// nothing at all, because the frustum was tested against a box half a metre
  /// wide back at the origin.
  ///
  /// The sum rather than the largest, and the absolute weight rather than the
  /// weight: two shapes at half strength can reach further than either alone,
  /// and glTF permits a negative weight, which moves a vertex just as far in
  /// the other direction. It is an upper bound and deliberately loose — a box a
  /// little too large draws something that could have been culled, and a box
  /// too small loses a model.
  double get reach {
    if (_reaches.isEmpty) return 0.0;
    if (_reachVersion == _version) return _reach;
    _reachVersion = _version;
    var total = 0.0;
    for (var i = 0; i < weights.length && i < _reaches.length; i++) {
      total += weights[i].abs() * _reaches[i];
    }
    return _reach = total;
  }

  double _reach = 0.0;
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
