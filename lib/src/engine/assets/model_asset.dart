import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

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
    this.warnings = const <String>[],
    this.name,
  });

  final List<ModelPart> parts;

  /// Bounds in the model's own space, for framing a camera before anything is
  /// instantiated.
  final Aabb3 localBounds;

  final List<String> warnings;
  final String? name;

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

  /// Adds this model to [scene] and returns the node that roots it.
  ///
  /// Materials are shared by default, so tinting one instance would tint all of
  /// them; pass `shareMaterials: false` when instances need to differ.
  SceneNode instantiate(
    Scene scene, {
    SceneNode? parent,
    String? name,
    bool shareMaterials = true,
  }) {
    final root = SceneNode(name: name ?? this.name ?? 'model');
    (parent ?? scene.root).add(root);

    for (final part in parts) {
      final material =
          shareMaterials ? part.material : _copyMaterial(part.material);
      final node = MeshNode(part.mesh, material, name: part.name);
      node.setLocalMatrix(part.transform);
      root.add(node);
    }

    return root;
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
