/// What a weights track can be written to.
///
/// **A second list beside the targets rather than a fourth setter on
/// [AnimationTarget].** That interface is three setters — position, rotation,
/// scale — and it is an `abstract interface class` in a published package, so
/// a fourth member breaks every implementer that exists. A morph weight is
/// also not a transform: it belongs to the *mesh* a node draws and not to the
/// node's placement, and the two are separate things that a glTF file keeps
/// separate.
///
/// So the player takes an optional second index-aligned list, exactly the shape
/// `targets` already has, and a caller that never morphs passes nothing and
/// pays nothing.
library;

/// A mesh whose morph weights an animation can drive.
///
/// `MorphState` implements it, which is the only implementation the engine
/// ships: the weights live on the scene node so that two copies of a model can
/// wear different expressions from one set of deltas.
abstract interface class MorphSink {
  /// Sets every weight from [values].
  ///
  /// Longer than the mesh has is tolerated and shorter leaves the rest at
  /// nought — see `MorphState.setWeights`, which says why each direction is
  /// the useful one.
  void setWeights(List<double> values);
}
