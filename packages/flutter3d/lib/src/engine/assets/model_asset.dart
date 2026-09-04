import 'package:flutter3d_hardware/flutter3d_hardware.dart';
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
import 'model_part.dart';
import 'texture_upload.dart';

// `ModelPart` is a plain value type with no coupling to the loading logic
// below, so it is re-exported from its own file rather than declared here —
// the same shape as `render_settings.dart` off `renderer.dart`. `instantiate`
// is the opposite case: a genuine method of this class that has to stay
// reachable through every existing import of this file, which is what a
// `part` buys and an ordinary file cannot — see `model_instance.dart`'s doc
// comment.
export 'model_part.dart';

part 'model_instance.dart';

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
  }) : nodes = nodes ?? _flatNodesFor(parts),
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

  /// Whether the file brought any animation with it.
  ///
  /// Nothing here asks: the engine plays the clips it was given and does nothing
  /// when there are none. It is for an application deciding what to build around
  /// a model it did not choose — whether to make a player for it at all, or
  /// whether an asset browser shows it as a still.
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
        report: (message) => warnings.add('images[$imageIndex]: $message'),
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

  /// Gives every uploaded mesh and texture back to [device].
  ///
  /// The counterpart to [fromDocument], and the same contract as
  /// `SharedMeshes.dispose`: call it when whoever owns this asset — normally
  /// one level load — is over, after every instance has left its scene. On
  /// flutter_gpu the release calls are no-ops and the collector does the work;
  /// on WebGL2 they are the only thing that ever calls `gl.deleteBuffer` and
  /// `gl.deleteTexture`, which is where not calling this was a real leak per
  /// level.
  ///
  /// Meshes and textures are deduplicated on the way in — surfaces share
  /// meshes, materials share maps, and one image can sit in two slots of the
  /// same material — so each distinct resource is released once, by identity.
  void release(GraphicsDevice device) {
    final meshes = Set<DeviceMesh>.identity();
    final textures = Set<TextureHandle>.identity();
    for (final part in parts) {
      meshes.add(part.mesh);
      final material = part.material;
      for (final texture in <TextureHandle?>[
        material.albedo,
        material.normal,
        material.metallicRoughness,
        material.occlusion,
        material.emissiveTexture,
      ]) {
        if (texture != null) textures.add(texture);
      }
    }
    for (final mesh in meshes) {
      device.releaseGeometry(mesh.vertices);
      device.releaseGeometry(mesh.indices);
    }
    for (final texture in textures) {
      device.releaseTexture(texture);
    }
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
    final (occlusion, occlusionSampler) = await resolve(
      source.occlusionTexture,
    );
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
