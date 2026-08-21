import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:vector_math/vector_math.dart';

import '../animation/animation.dart';
import '../geometry/geometry.dart';
import '../render/lighting_model.dart';
import '../render/material.dart';
import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';
import '../scene/skeleton.dart';
import 'model_document.dart';
import 'texture_upload.dart';

/// One drawable piece of a model: geometry, appearance, and where it sits
/// relative to the model's own origin.
final class ModelPart {
  ModelPart({
    required this.mesh,
    required this.material,
    Matrix4? transform,
    this.name,
    this.skinIndex,
    this.flipWinding = false,
  }) : transform = transform ?? Matrix4.identity();

  final DeviceMesh mesh;
  final Material material;
  final Matrix4 transform;
  final String? name;

  /// Index into [ModelAsset.skins], when this part is skinned.
  final int? skinIndex;

  final bool flipWinding;
}

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

/// An immutable, GPU-resident model that can be placed in a scene any number of
/// times.
///
/// The asset/instance split matters: without it a loaded model *is* the thing
/// being drawn, so putting it in a scene twice means loading it twice.
/// [instantiate] creates nodes that share the uploaded meshes and textures.
final class ModelAsset {
  ModelAsset({
    required this.parts,
    required this.localBounds,
    List<ModelNode>? nodes,
    List<int>? roots,
    this.skins = const <ModelSkin>[],
    this.clips = const <AnimationClip>[],
    this.warnings = const <String>[],
    this.name,
  })  : nodes = nodes ?? _flatNodesFor(parts),
        roots = roots ?? <int>[for (var i = 0; i < parts.length; i++) i];

  final List<ModelPart> parts;

  /// The model's hierarchy, index-aligned with whatever the decoder produced.
  ///
  /// Preserved rather than flattened because animation addresses nodes by index
  /// and because a moving node has to carry its subtree; flattening is exactly
  /// the information loss that made the old `GpuModel` unable to express a glTF
  /// scene.
  final List<ModelNode> nodes;

  final List<int> roots;

  final List<AnimationClip> clips;

  /// Skeletons, index-aligned with what the decoder produced.
  final List<ModelSkin> skins;

  /// Bounds in the model's own space, for framing a camera before anything is
  /// instantiated.
  final Aabb3 localBounds;

  final List<String> warnings;
  final String? name;

  bool get isAnimated => clips.isNotEmpty;

  bool get isSkinned => skins.isNotEmpty;

  static List<ModelNode> _flatNodesFor(List<ModelPart> parts) {
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3(1.0, 1.0, 1.0);

    return <ModelNode>[
      for (var i = 0; i < parts.length; i++)
        () {
          parts[i].transform.decompose(translation, rotation, scale);
          return ModelNode(
            name: parts[i].name,
            translation: translation.clone(),
            rotation: rotation.clone(),
            scale: scale.clone(),
            surfaces: <int>[i],
          );
        }(),
    ];
  }

  int get vertexCount {
    var total = 0;
    for (final part in parts) {
      total += part.mesh.vertexCount;
    }
    return total;
  }

  int get triangleCount {
    var total = 0;
    for (final part in parts) {
      total += part.mesh.indexCount ~/ 3;
    }
    return total;
  }

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

  /// Wraps a single procedurally generated mesh.
  factory ModelAsset.fromMesh(
    GraphicsDevice device,
    MeshData mesh, {
    Material? material,
    String? name,
  }) {
    final uploaded = DeviceMesh.upload(device, mesh);
    return ModelAsset(
      name: name,
      parts: <ModelPart>[
        ModelPart(mesh: uploaded, material: material ?? Material()),
      ],
      localBounds: uploaded.bounds,
    );
  }

  /// Uploads any decoded [ModelDocument].
  ///
  /// One implementation for every format: glTF and OBJ both produce a document
  /// with [SurfaceMaterial]s and [EncodedImage]s, so the upload path — mesh
  /// dedup, image dedup, material conversion — is written once. Adding a third
  /// format means writing a decoder, not touching this.
  /// **There was a `fallbackAlbedo` here and nothing ever read it.** Required,
  /// so every caller uploaded a one-pixel white texture to satisfy it — nine of
  /// them, one per model load, each leaving a texture on the device that was
  /// then dropped on the floor. It cannot have done anything since the day the
  /// packages were split: a material with no base-colour map keeps a null
  /// albedo all the way to the draw, where the *renderer* substitutes its own
  /// fallback, which is the only place that can know what white this frame is
  /// being lit against.
  static Future<ModelAsset> fromDocument(
    ModelDocument document, {
    required GraphicsDevice device,
    LightingModel lighting = LightingModel.pbr,
    String? name,
  }) async {
    final warnings = <String>[...document.warnings];

    // Surfaces may share a MeshData, and materials may share an image; upload
    // each distinct one once.
    final meshCache = <MeshData, DeviceMesh>{};
    // Keyed on the image **and on whether it carries a chain**, not on the
    // image alone. One image can be bound by two materials that sample it
    // differently — a decal atlas sampled without mips in one place and with
    // them in another — and the chain is part of the texture rather than part
    // of the sampler. Keying on the index alone would hand the second caller
    // whichever answer the first happened to ask for.
    final textureCache = <(int, bool), TextureHandle?>{};
    final materialCache = <int, Material>{};

    Future<TextureHandle?> textureFor(
      int imageIndex,
      TextureSampling sampling,
    ) async {
      if (imageIndex < 0 || imageIndex >= document.images.length) return null;
      final key = (imageIndex, sampling.useMipmaps);
      if (textureCache.containsKey(key)) return textureCache[key];

      final uploaded = await uploadEncodedImage(
        device,
        document.images[imageIndex].bytes,
        sampling: sampling,
      );
      if (uploaded == null) {
        warnings.add(
          'images[$imageIndex] could not be decoded; the material falls back to '
          'its base colour factor.',
        );
      }
      textureCache[key] = uploaded;
      return uploaded;
    }

    final parts = <ModelPart>[];
    for (final surface in document.surfaces) {
      final mesh = meshCache.putIfAbsent(
        surface.mesh,
        () => DeviceMesh.upload(device, surface.mesh),
      );

      final index = surface.materialIndex;
      Material material;
      if (index != null && index >= 0 && index < document.materials.length) {
        material = materialCache[index] ??= await _convertMaterial(
          document.materials[index],
          lighting: lighting,
          textureFor: textureFor,
        );
      } else {
        material = materialCache[-1] ??= Material(lighting: lighting);
      }

      parts.add(
        ModelPart(
          mesh: mesh,
          material: material,
          transform: surface.transform,
          name: surface.name,
          skinIndex: surface.skinIndex,
          flipWinding: surface.flipWinding,
        ),
      );
    }

    return ModelAsset(
      name: name,
      parts: parts,
      nodes: document.nodes,
      roots: document.roots,
      skins: document.skins,
      clips: document.animations,
      localBounds: document.computeBounds(),
      warnings: warnings,
    );
  }

  static Future<Material> _convertMaterial(
    SurfaceMaterial source, {
    required LightingModel lighting,
    required Future<TextureHandle?> Function(int, TextureSampling) textureFor,
  }) async {
    /// Resolves one texture slot, returning both the image and its sampler.
    ///
    /// A slot the file does not declare comes back null and the renderer binds
    /// a neutral texture instead, which is why nothing here has to record
    /// "this material has no normal map".
    Future<(TextureHandle?, SamplerOptions?)> resolve(
      TextureBinding? binding,
    ) async {
      if (binding == null) return (null, null);
      return (
        await textureFor(binding.imageIndex, binding.sampling),
        samplerOptionsFor(binding.sampling),
      );
    }

    final (albedo, albedoSampler) = await resolve(source.baseColorTexture);
    final (normal, normalSampler) = await resolve(source.normalTexture);
    final (orm, ormSampler) = await resolve(source.metallicRoughnessTexture);
    final (occlusion, occlusionSampler) = await resolve(source.occlusionTexture);
    final (emissive, emissiveSampler) = await resolve(source.emissiveTexture);

    return Material(
      name: source.name,
      // An unlit material asks for unlit shading regardless of the scene's
      // preferred model; ignoring the flag would light something authored flat.
      lighting: source.unlit ? LightingModel.unlit : lighting,
      baseColor: source.baseColor.clone(),
      metallic: source.metallic,
      roughness: source.roughness,
      albedo: albedo,
      albedoSampler: albedoSampler,
      normal: normal,
      normalSampler: normalSampler,
      normalScale: source.normalScale,
      metallicRoughness: orm,
      metallicRoughnessSampler: ormSampler,
      occlusion: occlusion,
      occlusionSampler: occlusionSampler,
      occlusionStrength: source.occlusionStrength,
      emissiveTexture: emissive,
      emissiveSampler: emissiveSampler,
      emissive: source.emissive.clone(),
      emissiveStrength: source.emissiveStrength,
      alphaMode: switch (source.alphaMode) {
        SurfaceAlphaMode.opaque => MaterialAlphaMode.opaque,
        SurfaceAlphaMode.mask => MaterialAlphaMode.mask,
        SurfaceAlphaMode.blend => MaterialAlphaMode.blend,
      },
      alphaCutoff: source.alphaCutoff,
      doubleSided: source.doubleSided,
    );
  }
}
