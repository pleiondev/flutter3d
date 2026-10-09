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
  final Map<SceneNode, Vector3?> _applied = <SceneNode, Vector3?>{};

  /// Rings every mesh under [root] in [color], or takes the ring off for
  /// null, unless that is what [root] already wears.
  void mark(SceneNode root, Vector3? color) {
    if (_applied.containsKey(root) && _applied[root] == color) return;
    _applied[root] = color?.clone();
    root.traverse((SceneNode node) {
      // A display colour, as a `Color` gives it: sRGB.
      if (node is MeshNode) {
        node.outlineColor = color == null
            ? null
            : LinearColor.fromSrgb(color.x, color.y, color.z);
      }
    });
  }

  /// Forgets [root], which has left the scene.
  void forget(SceneNode root) => _applied.remove(root);

  /// Forgets everything, for a level that is over.
  void clear() => _applied.clear();
}

/// A display colour as `MeshNode.outlineColor` takes it: the channels a
/// `Color` gives, unconverted, since the ring is drawn on the finished
/// picture.
Vector3 outlineColorOf(Color color) => Vector3(color.r, color.g, color.b);
