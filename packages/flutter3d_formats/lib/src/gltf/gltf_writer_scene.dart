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

      // glTF puts default morph weights and target names on the mesh, one
      // level above where this document keeps them (on the surface, per
      // `ModelSurface.morphWeights`'s own doc comment on why) — every surface
      // sharing one mesh entry came from one node in the original file, so
      // the first one's values are the node's, and writing them once here is
      // exactly the fold a decoder already did in the other direction.
      final weights = document.surfaces[surfaces.first].morphWeights;
      final targetNames = _targetNamesFor(surfaces.first);

      meshes.add(<String, Object?>{
        'primitives': <Object?>[for (final s in surfaces) primitives[s]],
        if (weights.isNotEmpty) 'weights': weights,
        if (targetNames.any((name) => name != null))
          'extras': <String, Object?>{'targetNames': targetNames},
      });
      final index = meshes.length - 1;
      meshIndexByShape[key] = index;
      return index;
    }

    // Registered up front rather than inside the node loop below, which
    // builds a list literal and has no room for a side-effecting statement
    // without turning each entry into its own closure.
    if (document.nodes.any((node) => node.lightIndex != null)) {
      _extensionsUsed.add('KHR_lights_punctual');
    }
    if (document.nodes.any((node) => node.lods.isNotEmpty)) {
      _extensionsUsed.add('MSFT_lod');
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
          if (node.extras != null) 'extras': node.extras,
          'mesh': ?meshIndexFor(node.surfaces),
          'camera': ?node.cameraIndex,
          if (node.lightIndex != null)
            'extensions': <String, Object?>{
              'KHR_lights_punctual': <String, Object?>{
                'light': node.lightIndex,
              },
            },
          // Per-node in glTF and per-surface here (`ModelSurface.skinIndex`,
          // since a skin binds vertices, not a mesh entry) — every surface a
          // node draws shares one skin already, the decoder's own invariant,
          // so the first one's is the node's.
          'skin': ?(node.surfaces.isEmpty
              ? null
              : document.surfaces[node.surfaces.first].skinIndex),
        },
    ];

    // `MSFT_lod`'s own shape names *sibling nodes*, not surface lists on one
    // node — see `ModelLod`'s own doc comment on why that is a real,
    // different shape from this document's. Each level becomes one new node,
    // appended after every node this document already named, so every index
    // written above (children, roots, skins, lights) stays exactly what it
    // was; nothing already on the list moves.
    //
    // A LOD sibling is placed at identity and never listed in `children` or
    // `roots` — nothing walks to it on its own, the way a viewer that does
    // not understand `MSFT_lod` would draw the base node's own mesh and never
    // notice the sibling exists. `extras.MSFT_screencoverage` carries one
    // entry per id, in the same order — this writer's own reader is the only
    // consumer proven against, since no third-party MSFT_lod validator or
    // reference implementation is available here to check the exact
    // convention (whether the base node's own coverage belongs in that array
    // too) against; this pairs each id with its own [ModelLod.maxScreenFraction]
    // and nothing else, which round-trips through this package's own writer
    // and loader exactly.
    for (var i = 0; i < document.nodes.length; i++) {
      final node = document.nodes[i];
      if (node.lods.isEmpty) continue;

      final ids = <int>[];
      final coverage = <double>[];
      for (final lod in node.lods) {
        final meshIndex = meshIndexFor(lod.surfaceIndices);
        ids.add(nodes.length);
        coverage.add(lod.maxScreenFraction);
        nodes.add(<String, Object?>{
          'translation': const <double>[0, 0, 0],
          'rotation': const <double>[0, 0, 0, 1],
          'scale': const <double>[1, 1, 1],
          'mesh': ?meshIndex,
        });
      }

      final base = nodes[i];
      base['extensions'] = <String, Object?>{
        ...?base['extensions'] as Map<String, Object?>?,
        'MSFT_lod': <String, Object?>{'ids': ids},
      };
      base['extras'] = <String, Object?>{
        ...?base['extras'] as Map<String, Object?>?,
        'MSFT_screencoverage': coverage,
      };
    }

    final scenes = nodes.isEmpty
        ? const <Map<String, Object?>>[]
        : <Map<String, Object?>>[
            <String, Object?>{'nodes': document.roots},
          ];

    return (meshes, nodes, scenes);
  }
}
