/// Turns a [ModelAsset] into a live [ModelInstance] in a [Scene].
///
/// **A part of `model_asset.dart`, not a file of its own.** `instantiate` is a
/// genuine public method of `ModelAsset` — every one of the apps in this
/// repo calls `asset.instantiate(scene)` after nothing more than
/// `import 'package:flutter3d/flutter3d.dart';`. An extension method only
/// applies where it is itself in scope, so as an ordinary file a second import
/// would be needed everywhere `instantiate` is called, and missing one would
/// be a silent compile error far from here. A `part` keeps `instantiate`
/// reachable exactly as before, through whichever import already reaches
/// `ModelAsset`.
part of 'model_asset.dart';

/// One placement of a [ModelAsset] in a scene.
///
/// More than the root node, because animation needs the node map: a track says
/// "move node 7", and 7 is an index into the asset's hierarchy, not a name. The
/// player handed back here is already bound to this instance's nodes, so two
/// copies of the same model animate independently.
final class ModelInstance {
  ModelInstance({
    required this.root,
    required this.nodes,
    required this.meshes,
    required this.skeletons,
    required this.player,
  });

  /// The node the whole model hangs from.
  final SceneNode root;

  /// Scene node for each of the asset's nodes, index-aligned.
  final List<SceneNode> nodes;

  final List<MeshNode> meshes;

  /// Skeletons bound to this instance's own nodes, so two copies of a rigged
  /// model pose independently.
  final List<Skeleton> skeletons;

  /// Null when the model carries no clips.
  final AnimationPlayer? player;

  void removeFromScene() => root.removeFromParent();
}

/// `instantiate` and its helpers, added to [ModelAsset].
///
/// Named and public — unlike the `part`s in the gltf/OBJ/f3d decoders, where
/// the extension only needs to be visible to itself — because `instantiate`
/// is called from other libraries throughout this repo, and a private
/// extension is invisible outside the library that declares it no matter how
/// many files `export` that library.
extension ModelAssetInstantiate on ModelAsset {
  /// Adds this model to [scene] and returns the instance.
  ///
  /// The asset's hierarchy is rebuilt as scene nodes, so a node the model
  /// animates moves everything below it. Mesh nodes sit at identity under the
  /// node that draws them: the placement already lives in the hierarchy, and
  /// applying `ModelPart.transform` here as well would compose it twice.
  ///
  /// Materials are shared by default, so tinting one instance would tint all of
  /// them; pass `shareMaterials: false` when instances need to differ.
  ModelInstance instantiate(
    Scene scene, {
    SceneNode? parent,
    String? name,
    bool shareMaterials = true,
  }) {
    final root = SceneNode(name: name ?? this.name ?? 'model');
    (parent ?? scene.root).add(root);

    final created = List<SceneNode?>.filled(nodes.length, null);
    final meshNodes = <MeshNode>[];
    final materials = <Material, Material>{};
    // Skeletons are attached after the walk: a joint may be created later than
    // the mesh that references it, so binding as we go would capture nulls.
    final pendingSkins = <(MeshNode, int)>[];

    Material materialFor(Material source) => shareMaterials
        ? source
        : materials.putIfAbsent(source, () => _copyMaterial(source));

    // Iterative rather than recursive: a deep hierarchy from a generated asset
    // should not be able to overflow the stack during a load.
    final pending = <(int nodeIndex, SceneNode parent)>[
      for (final rootIndex in roots.reversed)
        if (rootIndex >= 0 && rootIndex < nodes.length) (rootIndex, root),
    ];

    while (pending.isNotEmpty) {
      final (index, parentNode) = pending.removeLast();
      // A malformed hierarchy could name the same node twice; building it once
      // keeps the node map single-valued, which animation depends on.
      if (created[index] != null) continue;

      final model = nodes[index];
      final node = SceneNode(name: model.name);
      node.setPosition(
        model.translation.x,
        model.translation.y,
        model.translation.z,
      );
      node.setRotation(model.rotation);
      node.setScale(model.scale.x, model.scale.y, model.scale.z);
      parentNode.add(node);
      created[index] = node;

      for (final surfaceIndex in model.surfaces) {
        if (surfaceIndex < 0 || surfaceIndex >= parts.length) continue;
        final part = parts[surfaceIndex];
        final mesh = MeshNode(
          part.mesh,
          materialFor(part.material),
          name: part.name,
        );
        node.add(mesh);
        meshNodes.add(mesh);
        if (part.skinIndex != null) pendingSkins.add((mesh, part.skinIndex!));
      }

      for (final child in model.children.reversed) {
        if (child >= 0 && child < nodes.length) pending.add((child, node));
      }
    }

    final skeletons = <Skeleton>[];
    for (final (mesh, skinIndex) in pendingSkins) {
      final skeleton = _buildSkeleton(skins[skinIndex], created);
      if (skeleton == null) continue;
      mesh
        ..skeleton = skeleton
        // Measured from the bind pose once, not per frame: it is how far the
        // surface reaches from its bones, and that does not change as the model
        // moves. Without it a character is culled by the box around its
        // skeleton and clips as it leans.
        ..skinReach = mesh.mesh.boundingRadius;
      skeletons.add(skeleton);
    }

    return ModelInstance(
      root: root,
      nodes: <SceneNode>[
        for (var i = 0; i < created.length; i++) created[i] ?? root,
      ],
      meshes: meshNodes,
      skeletons: skeletons,
      player: clips.isEmpty
          ? null
          : AnimationPlayer(
              clips: clips,
              targets: List<AnimationTarget?>.of(created),
            ),
    );
  }

  /// Binds a decoded skin to the nodes this instance created.
  ///
  /// Returns null when a joint is missing, which can only happen if the
  /// hierarchy did not reach it — a skeleton with a hole would silently collapse
  /// part of the mesh to the origin, and no skeleton at all leaves the mesh in
  /// its bind pose, which is the more debuggable failure.
  static Skeleton? _buildSkeleton(ModelSkin skin, List<SceneNode?> created) {
    final joints = <SceneNode>[];
    for (final index in skin.joints) {
      if (index < 0 || index >= created.length) return null;
      final node = created[index];
      if (node == null) return null;
      joints.add(node);
    }
    if (joints.length > Skeleton.maxJoints) return null;

    final rootIndex = skin.skeletonRoot;
    return Skeleton(
      name: skin.name,
      joints: joints,
      inverseBindMatrices: skin.inverseBindMatrices,
      skeletonRoot: rootIndex != null && rootIndex < created.length
          ? created[rootIndex]
          : null,
    );
  }

  static Material _copyMaterial(Material source) => source.copy();
}
