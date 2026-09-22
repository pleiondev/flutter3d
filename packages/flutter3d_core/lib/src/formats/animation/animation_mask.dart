/// Which joints a layer is allowed to write.
///
/// **Node indices, not nodes, and that is the boundary talking.**
/// [AnimationTarget] is three setters and no hierarchy, deliberately: the
/// animation layer is reached from the asset decoders, so a dependency on
/// `SceneNode` would drag `Material` — and through it the graphics backend and
/// `dart:ui` — into everything that merely reads a glTF file. A mask built by
/// walking parents would need exactly that hierarchy.
///
/// So the walking happens where the hierarchy already is. `ModelDocument.nodes`
/// is a tree of indices, and those indices are what an animation channel
/// addresses — the same numbers, in the same order. `ModelDocument.maskUnder`
/// turns a joint's name into this, and the player never learns what a parent is.
///
/// A mask is a set and not a range because a skeleton's indices are not
/// contiguous by limb: a glTF exporter numbers nodes in whatever order its
/// scene had, and the spine's descendants are scattered through the list.
library;

/// The joints one animation layer writes, by node index.
///
/// Immutable: a mask is built once from a skeleton and read every frame by
/// every layer that shares it. One that could be edited underneath a running
/// layer would change which joints a pose covers halfway through a blend.
final class AnimationMask {
  /// A mask over exactly [indices].
  AnimationMask(Iterable<int> indices)
    : _indices = Set<int>.unmodifiable(indices),
      _all = false;

  const AnimationMask._all() : _indices = const <int>{}, _all = true;

  /// The mask that stops nothing, for a layer meant to cover the whole
  /// skeleton.
  ///
  /// Named rather than expressed as a null: a layer whose mask is absent and a
  /// layer whose mask is everything are the same thing, and having two spellings
  /// of it is how a caller ends up asking which one a null meant.
  static const AnimationMask everything = AnimationMask._all();

  final Set<int> _indices;
  final bool _all;

  /// Whether a layer holding this may write the joint at [nodeIndex].
  bool covers(int nodeIndex) => _all || _indices.contains(nodeIndex);

  /// How many joints it names. Zero for [everything], which names none and
  /// covers all — see [covers].
  int get length => _indices.length;

  bool get isEmpty => !_all && _indices.isEmpty;

  @override
  String toString() => _all
      ? 'AnimationMask(everything)'
      : 'AnimationMask(${_indices.length} joints)';
}
