/// The scene walk: turns glTF's `nodes`/`meshes`/`scenes` into engine
/// [ModelNode]s and flattened [ModelSurface] instances.
///
/// **A part of `gltf_loader.dart`, not a file of its own**, and the reason is
/// sharing rather than size: `_decodeScene` calls `_decodeMesh`, which lives in
/// `gltf_loader_mesh.dart`, and every phase of the pipeline reads the same
/// private JSON helpers (`_mapList`, `_intList`, `_asInt`, ...) declared at the
/// bottom of `gltf_loader.dart`. Making any of that public just so two files
/// could see each other would widen `GltfLoader`'s surface for no reader's
/// benefit; a `part` keeps the phases in their own files without doing that.
part of 'gltf_loader.dart';

extension _GltfSceneWalk on GltfLoader {
  // ---------------------------------------------------------------- scene walk

  _SceneGraph _decodeScene(
    Map<String, Object?> json,
    GltfAccessorReader reader,
    List<String> warnings,
  ) {
    final nodes = _mapList(json['nodes']);
    final meshes = _mapList(json['meshes']);
    final scenes = _mapList(json['scenes']);

    // `scene` picks the default; if absent, the spec leaves the choice to the
    // viewer and scene 0 is the universal convention.
    final sceneIndex = _asInt(json['scene']) ?? 0;
    List<int> roots;
    if (sceneIndex >= 0 && sceneIndex < scenes.length) {
      roots = _intList(scenes[sceneIndex]['nodes']);
    } else if (scenes.isNotEmpty) {
      roots = _intList(scenes.first['nodes']);
    } else {
      // No scenes at all: draw every mesh-bearing node so the file is not
      // silently empty.
      roots = <int>[for (var i = 0; i < nodes.length; i++) i];
      if (nodes.isNotEmpty) {
        warnings.add('No scenes defined; treating all nodes as roots.');
      }
    }

    // Meshes are decoded once and reused: a node graph may reference the same
    // mesh many times, and re-decoding it per node would multiply both work and
    // memory.
    final meshCache = <int, List<_DecodedPrimitive>>{};
    final instances = <ModelSurface>[];
    final onPath = <int>{};

    // Index-aligned with the glTF `nodes` array, because that is what animation
    // channels address. Every node is kept, including the transform-only ones:
    // those are precisely the ones an animation moves.
    final modelNodes = <ModelNode>[
      for (final node in nodes) _modelNodeFrom(node),
    ];

    void visit(int nodeIndex, Matrix4 parentTransform) {
      if (nodeIndex < 0 || nodeIndex >= nodes.length) {
        warnings.add('Node index $nodeIndex is out of range; skipped.');
        return;
      }
      // A malformed file can make the hierarchy cyclic. Without this the walk
      // recurses until the stack dies.
      if (!onPath.add(nodeIndex)) {
        warnings.add('Node $nodeIndex forms a cycle; subtree skipped.');
        return;
      }

      final node = nodes[nodeIndex];
      // Typed, because `Matrix4.operator*` in vector_math is declared to take
      // and return `dynamic` — so without this the world transform is an
      // untyped value and every `world.determinant()` below it is a call
      // nothing checks.
      final Matrix4 world = parentTransform * _localTransform(node);

      final skinIndex = _asInt(node['skin']);
      final meshIndex = _asInt(node['mesh']);
      if (meshIndex != null && meshIndex >= 0 && meshIndex < meshes.length) {
        final primitives = meshCache.putIfAbsent(
          meshIndex,
          () => _decodeMesh(meshes[meshIndex], meshIndex, reader, warnings),
        );
        // A mirroring transform reverses on-screen winding, so record it here
        // rather than making the renderer recompute the determinant per draw.
        final mirrored = world.determinant() < 0.0;
        final nodeName = node['name'];

        for (final primitive in primitives) {
          modelNodes[nodeIndex].surfaces.add(instances.length);
          instances.add(
            ModelSurface(
              name: nodeName is String ? nodeName : null,
              mesh: primitive.mesh,
              // A skinned surface's vertices are already in the skin's own
              // space, so the node transform must NOT be baked in — the joints
              // place it. Baking it applies the node's placement twice, which
              // looks like a model launched away from its skeleton.
              transform: skinIndex == null
                  ? world.clone()
                  : Matrix4.identity(),
              materialIndex: primitive.materialIndex,
              skinIndex: skinIndex,
              flipWinding: skinIndex == null && mirrored,
            ),
          );
        }
      }

      for (final child in _intList(node['children'])) {
        visit(child, world);
      }
      onPath.remove(nodeIndex);
    }

    for (final root in roots) {
      visit(root, Matrix4.identity());
    }
    return _SceneGraph(
      surfaces: instances,
      nodes: modelNodes,
      roots: roots.where((i) => i >= 0 && i < modelNodes.length).toList(),
    );
  }

  /// One glTF node as a [ModelNode], with its transform kept as TRS.
  ///
  /// A `matrix` node is decomposed, which loses shear — the same trade-off
  /// three.js and Babylon make, and shear in authored assets is vanishingly
  /// rare. TRS is what the scene graph stores and what animation interpolates,
  /// so keeping a matrix here would only move the decomposition later.
  ModelNode _modelNodeFrom(Map<String, Object?> node) {
    final name = node['name'];
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3(1.0, 1.0, 1.0);

    final matrix = node['matrix'];
    if (matrix is List && matrix.length == 16) {
      _localTransform(node).decompose(translation, rotation, scale);
    } else {
      final t = _vec3(node['translation']);
      if (t != null) translation.setFrom(t);
      final s = _vec3(node['scale']);
      if (s != null) scale.setFrom(s);
      final r = node['rotation'];
      if (r is List && r.length == 4) {
        rotation
          ..setValues(
            _asDouble(r[0]) ?? 0.0,
            _asDouble(r[1]) ?? 0.0,
            _asDouble(r[2]) ?? 0.0,
            _asDouble(r[3]) ?? 1.0,
          )
          ..normalize();
      }
    }

    return ModelNode(
      name: name is String ? name : null,
      translation: translation,
      rotation: rotation,
      scale: scale,
      children: _intList(node['children']),
    );
  }

  /// Node-local transform: either an explicit matrix or a TRS triple, never
  /// both per the spec.
  Matrix4 _localTransform(Map<String, Object?> node) {
    final matrix = node['matrix'];
    if (matrix is List && matrix.length == 16) {
      // glTF stores matrices column-major, which is also vector_math's storage
      // order, so the values go straight in.
      final storage = Float32List(16);
      for (var i = 0; i < 16; i++) {
        storage[i] = _asDouble(matrix[i]) ?? 0.0;
      }
      return Matrix4.fromFloat32List(storage);
    }

    final translation = _vec3(node['translation']) ?? Vector3.zero();
    final scale = _vec3(node['scale']) ?? Vector3(1.0, 1.0, 1.0);
    final rotationList = node['rotation'];
    // glTF quaternions are stored xyzw; Quaternion(x, y, z, w) matches.
    final rotation = rotationList is List && rotationList.length == 4
        ? Quaternion(
            _asDouble(rotationList[0]) ?? 0.0,
            _asDouble(rotationList[1]) ?? 0.0,
            _asDouble(rotationList[2]) ?? 0.0,
            _asDouble(rotationList[3]) ?? 1.0,
          )
        : Quaternion.identity();

    return Matrix4.compose(translation, rotation.normalized(), scale);
  }
}

/// The scene walk's two outputs: the flattened surfaces and the hierarchy they
/// came from.
final class _SceneGraph {
  const _SceneGraph({
    required this.surfaces,
    required this.nodes,
    required this.roots,
  });

  final List<ModelSurface> surfaces;

  /// Index-aligned with the file's `nodes` array.
  final List<ModelNode> nodes;

  final List<int> roots;
}
