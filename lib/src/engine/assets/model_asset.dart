import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import '../animation/animation.dart';
import '../geometry/geometry.dart';
import '../gpu/gpu_mesh.dart';
import '../gpu/texture_upload.dart';
import '../render/lighting_model.dart';
import '../render/material.dart';
import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';
import 'model_document.dart';

/// One drawable piece of a model: geometry, appearance, and where it sits
/// relative to the model's own origin.
final class ModelPart {
  ModelPart({
    required this.mesh,
    required this.material,
    Matrix4? transform,
    this.name,
    this.flipWinding = false,
  }) : transform = transform ?? Matrix4.identity();

  final GpuMesh mesh;
  final Material material;
  final Matrix4 transform;
  final String? name;
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
    required this.player,
  });

  /// The node the whole model hangs from.
  final SceneNode root;

  /// Scene node for each of the asset's nodes, index-aligned.
  final List<SceneNode> nodes;

  final List<MeshNode> meshes;

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

  /// Bounds in the model's own space, for framing a camera before anything is
  /// instantiated.
  final Aabb3 localBounds;

  final List<String> warnings;
  final String? name;

  bool get isAnimated => clips.isNotEmpty;

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
      }

      for (final child in model.children.reversed) {
        if (child >= 0 && child < nodes.length) pending.add((child, node));
      }
    }

    return ModelInstance(
      root: root,
      nodes: <SceneNode>[
        for (var i = 0; i < created.length; i++) created[i] ?? root,
      ],
      meshes: meshNodes,
      player: clips.isEmpty
          ? null
          : AnimationPlayer(
              clips: clips,
              targets: List<SceneNode?>.of(created),
            ),
    );
  }

  static Material _copyMaterial(Material source) => Material(
        name: source.name,
        lighting: source.lighting,
        baseColor: source.baseColor.clone(),
        metallic: source.metallic,
        roughness: source.roughness,
        albedo: source.albedo,
        albedoSampler: source.albedoSampler,
        alphaMode: source.alphaMode,
        alphaCutoff: source.alphaCutoff,
        doubleSided: source.doubleSided,
        drawBucket: source.drawBucket,
      );

  /// Wraps a single procedurally generated mesh.
  factory ModelAsset.fromMesh(
    MeshData mesh, {
    Material? material,
    String? name,
  }) {
    final uploaded = GpuMesh.upload(mesh);
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
  static Future<ModelAsset> fromDocument(
    ModelDocument document, {
    required gpu.Texture fallbackAlbedo,
    LightingModel lighting = LightingModel.pbr,
    String? name,
  }) async {
    final warnings = <String>[...document.warnings];

    // Surfaces may share a MeshData, and materials may share an image; upload
    // each distinct one once.
    final meshCache = <MeshData, GpuMesh>{};
    final textureCache = <int, gpu.Texture?>{};
    final materialCache = <int, Material>{};

    Future<gpu.Texture?> textureFor(int imageIndex) async {
      if (imageIndex < 0 || imageIndex >= document.images.length) return null;
      if (textureCache.containsKey(imageIndex)) return textureCache[imageIndex];

      final uploaded =
          await uploadEncodedImage(document.images[imageIndex].bytes);
      if (uploaded == null) {
        warnings.add(
          'images[$imageIndex] could not be decoded; the material falls back to '
          'its base colour factor.',
        );
      }
      textureCache[imageIndex] = uploaded;
      return uploaded;
    }

    final parts = <ModelPart>[];
    for (final surface in document.surfaces) {
      final mesh = meshCache.putIfAbsent(
        surface.mesh,
        () => GpuMesh.upload(surface.mesh),
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
          flipWinding: surface.flipWinding,
        ),
      );
    }

    return ModelAsset(
      name: name,
      parts: parts,
      nodes: document.nodes,
      roots: document.roots,
      clips: document.animations,
      localBounds: document.computeBounds(),
      warnings: warnings,
    );
  }

  static Future<Material> _convertMaterial(
    SurfaceMaterial source, {
    required LightingModel lighting,
    required Future<gpu.Texture?> Function(int) textureFor,
  }) async {
    gpu.Texture? albedo;
    gpu.SamplerOptions? sampler;
    final binding = source.baseColorTexture;
    if (binding != null) {
      albedo = await textureFor(binding.imageIndex);
      sampler = samplerOptionsFor(binding.sampling);
    }

    return Material(
      name: source.name,
      // An unlit material asks for unlit shading regardless of the scene's
      // preferred model; ignoring the flag would light something authored flat.
      lighting: source.unlit ? LightingModel.unlit : lighting,
      baseColor: source.baseColor.clone(),
      metallic: source.metallic,
      roughness: source.roughness,
      albedo: albedo,
      albedoSampler: sampler,
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
