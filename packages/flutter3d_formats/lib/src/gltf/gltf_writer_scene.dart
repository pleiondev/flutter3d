/// Turns `document.nodes`/`document.roots` into glTF's `nodes`/`scenes`, and
/// groups each node's surfaces into the `meshes` it draws.
///
/// **A part of `gltf_writer.dart`**, for the same reason as every other phase:
/// it reads `document.surfaces[i].materialIndex` through the primitives handed
/// to it and needs nothing private beyond that, but keeping the three phases
/// textually together is what lets a reader move from "how a node is built" to
/// "how a mesh is built" without an import to follow.
part of 'gltf_writer.dart';

extension _GltfWriterScene on GltfWriter {
  /// Builds `meshes`/`nodes`/`scenes` from [primitives] — one entry per
  /// `document.surfaces` index, already built by `_primitiveFor`.
  ///
  /// Node placement comes from `document.nodes` alone, never from a surface's
  /// own [ModelSurface.transform]: a decoder bakes the accumulated world
  /// transform into that field (skinning needs it there), while a node's own
  /// translation/rotation/scale is already the local placement the hierarchy
  /// wants — using the surface's baked copy here would double-apply every
  /// ancestor's transform the moment a node has one.
  (
    List<Map<String, Object?>>,
    List<Map<String, Object?>>,
    List<Map<String, Object?>>,
  )
  _writeScene(List<Map<String, Object?>> primitives) {
    final meshes = <Map<String, Object?>>[];
    // Two nodes drawing the exact same surfaces — an instanced prop — write
    // one glTF mesh and both nodes point at it, which is the node half of the
    // plan's dedup ask (the accessor half is `_accessorsFor`'s cache).
    final meshIndexByShape = <String, int>{};

    int? meshIndexFor(List<int> surfaces) {
      if (surfaces.isEmpty) return null;
      final key = surfaces.join(',');
      final existing = meshIndexByShape[key];
      if (existing != null) return existing;
      meshes.add(<String, Object?>{
        'primitives': <Object?>[for (final s in surfaces) primitives[s]],
      });
      final index = meshes.length - 1;
      meshIndexByShape[key] = index;
      return index;
    }

    final nodes = <Map<String, Object?>>[
      for (final node in document.nodes)
        <String, Object?>{
          if (node.name != null) 'name': node.name,
          'translation': <double>[
            node.translation.x,
            node.translation.y,
            node.translation.z,
          ],
          // glTF quaternions are stored xyzw; `Quaternion` matches that order
          // already, so this is a direct read rather than a reshuffle — the
          // reshuffle is the bug this order is written down to prevent.
          'rotation': <double>[
            node.rotation.x,
            node.rotation.y,
            node.rotation.z,
            node.rotation.w,
          ],
          'scale': <double>[node.scale.x, node.scale.y, node.scale.z],
          if (node.children.isNotEmpty) 'children': node.children,
          'mesh': ?meshIndexFor(node.surfaces),
        },
    ];

    final scenes = nodes.isEmpty
        ? const <Map<String, Object?>>[]
        : <Map<String, Object?>>[
            <String, Object?>{'nodes': document.roots},
          ];

    return (meshes, nodes, scenes);
  }
}
