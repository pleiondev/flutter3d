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
    this.variants = const <String>[],
    this._drawn = const <(MeshNode, ModelPart)>[],
    Material Function(Material)? materialFor,
    PointerTargets? pointerTargets,
  }) : _materialFor = materialFor ?? _same,
       pointerTargets = pointerTargets ?? PointerTargets();

  static Material _same(Material material) => material;

  /// The material variants this model offers, by name — the asset's own.
  final List<String> variants;

  /// Each mesh node with the part it was built from, for [selectVariant].
  final List<(MeshNode, ModelPart)> _drawn;

  /// The instance's own copy of an asset material, or the material itself
  /// when materials are shared — see [ModelAssetInstantiate.instantiate].
  final Material Function(Material) _materialFor;

  /// Where the player's `KHR_animation_pointer` tracks land: this instance's
  /// materials by the file's index, and whatever lights the caller binds
  /// with [bindLight].
  ///
  /// With shared materials — the default — a material track moves the
  /// asset's material, and so every instance wearing it, the same way
  /// tinting one does. Instantiate with `shareMaterials: false` for copies
  /// that animate on their own.
  final PointerTargets pointerTargets;

  /// The variant [selectVariant] last chose, or null for the default look.
  String? get variant => _variant;
  String? _variant;

  /// Dresses every part in its material for the variant called [name], or
  /// in its default material when [name] is null.
  ///
  /// A part the variant does not mention wears its default, which is what
  /// `KHR_materials_variants` says. Returns false, changing nothing, when no
  /// variant has that name.
  ///
  /// Switching changes which material each mesh node points at, never the
  /// materials themselves, so two instances sharing the asset's materials
  /// can still wear two variants at once.
  bool selectVariant(String? name) {
    final index = name == null ? -1 : variants.indexOf(name);
    if (name != null && index < 0) return false;
    for (final (mesh, part) in _drawn) {
      mesh.material = _materialFor(
        part.variantMaterials[index] ?? part.material,
      );
    }
    _variant = name;
    return true;
  }

  /// Lets animation pointer tracks aimed at the file's light [index] drive
  /// [light]. Instantiating a model creates no lights, so a clip that
  /// animates one reaches only a light the caller has put in its place.
  void bindLight(int index, LightNode light) =>
      pointerTargets.lights[index] = light;

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
    final drawn = <(MeshNode, ModelPart)>[];
    final materials = <Material, Material>{};
    // Skeletons are attached after the walk: a joint may be created later than
    // the mesh that references it, so binding as we go would capture nulls.
    final pendingSkins = <(MeshNode, int)>[];
    // Index-aligned with `nodes`, because a weights track names a node index
    // and not a surface. A node drawing several primitives — one glTF mesh
    // split by material — has one set of weights across all of them, so the
    // sinks are gathered per node and fanned out below.
    final morphSinks = List<List<MorphState>?>.filled(nodes.length, null);

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

      MeshNode? addSurface(int surfaceIndex) {
        if (surfaceIndex < 0 || surfaceIndex >= parts.length) return null;
        final part = parts[surfaceIndex];
        final mesh = MeshNode(
          part.mesh,
          materialFor(part.material),
          name: part.name,
        );
        meshNodes.add(mesh);
        drawn.add((mesh, part));
        if (part.skinIndex != null) pendingSkins.add((mesh, part.skinIndex!));

        final deltas = part.morphTexture;
        if (deltas != null) {
          final state = MorphState(
            texture: deltas,
            targetCount: part.morphTargetCount,
            reaches: part.morphReaches,
          )..setWeights(part.morphWeights);
          mesh.morph = state;
          (morphSinks[index] ??= <MorphState>[]).add(state);
        }
        return mesh;
      }

      // `pro-eng-06`'s own row: a node with lods draws through an `LodGroup`
      // instead of its surfaces directly, so the engine actually picks a
      // level rather than drawing every one of them at once. Scoped to the
      // case an `LodGroup` can express without new machinery of its own:
      // `LodLevel.node` is one `MeshNode`, so this only builds automatically
      // when the base surfaces and every `ModelLod` are each exactly one
      // surface — a node split across several materials at any level falls
      // back to the ordinary path below, still correct, just not switched by
      // distance. `maxScreenFraction: 2.0` on the base level is past the
      // largest fraction `LodGroup.screenFraction` can ever return (capped at
      // 1.0), so it is always the finest and always sorts first.
      final singleSurfaceLevels =
          model.surfaces.length == 1 &&
          // An impostor level whose atlases did not upload is skipped below
          // rather than sinking the whole chain: the mesh levels still switch.
          model.lods.every(
            (lod) => lod.surfaceIndices.length == 1 || lod.impostor != null,
          );
      if (model.lods.isNotEmpty && singleSurfaceLevels) {
        final baseMesh = addSurface(model.surfaces.single);
        if (baseMesh != null) {
          final levels = <LodLevel>[
            LodLevel(node: baseMesh, maxScreenFraction: 2.0),
            for (final lod in model.lods)
              // `C4`: the card a chain ends in, drawn from the atlases the
              // asset uploaded once for every instance.
              if (impostors[lod.impostor] case final ImpostorPart part)
                LodLevel(
                  node: ImpostorNode.withCard(
                    part.card,
                    albedo: part.albedo,
                    normalDepth: part.normalDepth,
                    centre: lod.impostor!.centre,
                    radius: lod.impostor!.radius,
                    name: '${model.name ?? 'node'} impostor',
                  ),
                  maxScreenFraction: lod.maxScreenFraction,
                )
              else if (lod.surfaceIndices.length == 1)
                if (addSurface(lod.surfaceIndices.single) case final MeshNode m)
                  LodLevel(node: m, maxScreenFraction: lod.maxScreenFraction),
          ];
          node.add(LodGroup(levels: levels, name: model.name));
        }
      } else {
        for (final surfaceIndex in model.surfaces) {
          final mesh = addSurface(surfaceIndex);
          if (mesh != null) node.add(mesh);
        }
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

    // By the file's material index, through the same copy the parts got, so
    // a track on an unshared instance moves that instance's material only.
    final pointerTargets = PointerTargets(
      materials: <int, Material>{
        for (final MapEntry(:key, :value) in this.materials.entries)
          key: materialFor(value),
      },
    );

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
              morphs: morphSinks.any((states) => states != null)
                  ? <MorphSink?>[for (final states in morphSinks) _sink(states)]
                  : null,
              pointers: pointerTargets,
            ),
      variants: variants,
      drawn: drawn,
      materialFor: materialFor,
      pointerTargets: pointerTargets,
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

  /// One sink for the meshes one node draws.
  ///
  /// The common case is a single mesh and it is handed back as it is; the case
  /// that needs wrapping is a glTF mesh split across materials, where one set of
  /// weights drives several primitives and the file still calls them one shape.
  static MorphSink? _sink(List<MorphState>? states) => switch (states) {
    null => null,
    [final only] => only,
    _ => _MorphFan(states),
  };

  static Material _copyMaterial(Material source) => source.copy();
}

/// A weights track reaching every primitive of one split mesh.
final class _MorphFan implements MorphSink {
  _MorphFan(this.states);

  final List<MorphState> states;

  @override
  void setWeights(List<double> values) {
    for (final state in states) {
      state.setWeights(values);
    }
  }
}
