import 'dart:ui' show Color;

import 'package:flutter3d/flutter3d.dart';

/// The colour each drawn thing was last ringed in, so a frame that asks for
/// the same colour again walks nothing — `N9`.
///
/// **Applied rather than computed per frame**, and the reason is what a
/// thing is drawn as. A monster is a capsule until its model arrives and a
/// model is a tree of meshes, and the engine asks each mesh it draws for its
/// `MeshNode.outlineColor`, not the mesh's parents. So a colour has to be
/// written onto every mesh under the node, again whenever the node is
/// replaced — and only then, or a level of thirty monsters walks thirty trees
/// a frame to write what is already there.
final class OutlineMarks {
  final Map<SceneNode, LinearColor?> _applied = <SceneNode, LinearColor?>{};

  /// Rings every mesh under [root] in [color], or takes the ring off for
  /// null, unless that is what [root] already wears.
  void mark(SceneNode root, LinearColor? color) {
    if (_applied.containsKey(root) && _applied[root] == color) return;
    _applied[root] = color;
    root.traverse((SceneNode node) {
      if (node is MeshNode) node.outlineColor = color;
    });
  }

  /// Forgets [root], which has left the scene.
  void forget(SceneNode root) => _applied.remove(root);

  /// Forgets everything, for a level that is over.
  void clear() => _applied.clear();
}

/// [color], a display colour a player picked from a swatch, as
/// `MeshNode.outlineColor` takes it: linear, like every colour the engine
/// takes. The ring is drawn on the finished picture and encoded back to the
/// display there, so it comes out the colour of the swatch. The alpha is
/// dropped: a ring is opaque.
LinearColor outlineColorOf(Color color) =>
    LinearColor.fromSrgb(color.r, color.g, color.b);
