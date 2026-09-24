import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

import 'default_image_decoder.dart';
import 'material_loader.dart';

// `ModelPart` is a plain value type with no coupling to the loading logic
// below, so it is re-exported from its own file rather than declared here —
// the same shape as `render_settings.dart` off `renderer.dart`. `instantiate`
// is the opposite case: a genuine method of this class that has to stay
// reachable through every existing import of this file, which is what a
// `part` buys and an ordinary file cannot — see `model_instance.dart`'s doc
// comment.
export 'package:flutter3d_core/flutter3d_core.dart' show ModelPart;

part 'model_instance.dart';

/// An impostor level's uploaded card and atlases — see [ModelAsset.impostors].
typedef ImpostorPart = ({
  DeviceMesh card,
  TextureHandle albedo,
  TextureHandle normalDepth,
});

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
    List<ModelSkin> skins = const <ModelSkin>[],
    this.clips = const <AnimationClip>[],
    this.warnings = const <String>[],
    this.name,
    this.variants = const <String>[],
    this.materials = const <int, Material>{},
    Map<ModelImpostor, ImpostorPart> impostors =
        const <ModelImpostor, ImpostorPart>{},
  }) : impostors = Map.unmodifiable(impostors),
       skins = List.unmodifiable(skins),
       nodes = nodes ?? _flatNodesFor(parts),
       roots = roots ?? <int>[for (var i = 0; i < parts.length; i++) i];

  final List<ModelPart> parts;

  /// What each impostor level in [nodes] draws with — `C4`: its card and its
  /// two atlases, uploaded once however many instances stand in a scene.
  /// Keyed by the level's own [ModelImpostor]; empty for the model with none,
  /// which is nearly every model.
  final Map<ModelImpostor, ImpostorPart> impostors;

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

  /// The material variants the file offers, by name — see
  /// [ModelInstance.selectVariant] and [ModelPart.variantMaterials].
  final List<String> variants;

  /// The bound material for each of the document's materials that anything
  /// uses, by its index there.
  ///
  /// Kept because an animation pointer addresses a material by that index,
  /// not by the part that happens to wear it: one material on three parts is
  /// one roughness track, and a material only a variant uses is still one a
  /// clip may animate.
  final Map<int, Material> materials;

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
    ImageDecoder decodeImage = defaultImageDecoder,
  }) async {
    final warnings = <String>[...document.warnings];

    // Surfaces may share a MeshData, and materials may share an image; upload
    // each distinct one once.
    //
    // Keyed on the transform as well as the mesh, because one set of vertices
    // drawn with two atlas-packed materials is two sets of coordinates. The
    // transform is compared by identity, which is the material's own object:
    // two surfaces sharing a mesh and a material share the upload, and that is
    // the case there is.
    final meshCache = <(MeshData, TextureTransform?), DeviceMesh>{};
    // Keyed on the image **and on whether it carries a chain**, not on the
    // image alone. One image can be bound by two materials that sample it
    // differently — a decal atlas sampled without mips in one place and with
    // them in another — and the chain is part of the texture rather than part
    // of the sampler. Keying on the index alone would hand the second caller
    // whichever answer the first happened to ask for.
    final textureCache = <(int, bool), TextureHandle?>{};
    final materialCache = <int, Material>{};
    // Deltas belong to the geometry and are keyed with it: two surfaces sharing
    // a MeshData share one upload, and a model whose face is drawn twice pays
    // for its expressions once.
    final morphCache =
        <
          MeshData,
          ({TextureHandle? texture, int count, List<Aabb3> reaches})
        >{};

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
        decodeImage: decodeImage,
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

    // The pixels of each image the layers' maps pack, decoded once however
    // many materials pack it — `M1`.
    final decodedCache = <int, Future<Rgba8Image?>>{};
    Future<Rgba8Image?> decodedImage(int imageIndex) {
      if (imageIndex < 0 || imageIndex >= document.images.length) {
        return Future<Rgba8Image?>.value();
      }
      return decodedCache[imageIndex] ??= () async {
        try {
          return await decodeImage(document.images[imageIndex].bytes);
        } catch (_) {
          warnings.add(
            'images[$imageIndex] could not be decoded for a packed map; the '
            'material falls back to its factors.',
          );
          return null;
        }
      }();
    }

    /// Packs and uploads one mesh's morph deltas, or nothing when it has none.
    ///
    /// A failed upload is a model that draws its base shape, not a model that
    /// refuses to load: a device that will not take a float texture is a device
    /// on which every face is expressionless, and that is still a picture.
    ({TextureHandle? texture, int count, List<Aabb3> reaches}) morphFor(
      MeshData mesh,
      String where,
    ) => morphCache.putIfAbsent(mesh, () {
      final packed = MorphTexture.pack(mesh);
      if (packed == null) {
        return (texture: null, count: 0, reaches: const <Aabb3>[]);
      }

      final left = packed.dropped(mesh);
      if (left > 0) {
        warnings.add(
          '$where: $left of ${mesh.morphTargets.length} morph targets were '
          'left out; the shader blends ${packed.targetCount} at once.',
        );
      }

      final uploaded = device.createTextureFromPixels(
        width: packed.width,
        height: packed.height,
        format: TextureFormat.r32g32b32a32Float,
        pixels: packed.bytes,
      );
      if (uploaded == null) {
        warnings.add(
          '$where: the morph deltas could not be uploaded; the mesh draws '
          'its base shape.',
        );
        return (texture: null, count: 0, reaches: const <Aabb3>[]);
      }
      return (
        texture: uploaded,
        count: packed.targetCount,
        reaches: packed.reaches,
      );
    });

    Future<Material> materialAt(int index) async =>
        materialCache[index] ??= await bindSurfaceMaterial(
          document.materials[index],
          lighting: lighting,
          textureFor: textureFor,
          // `M1`–`M3`: the layer maps packed at load, for a variant's
          // material as for the default one.
          layerImages: (
            device: device,
            image: (binding) => decodedImage(binding.imageIndex),
          ),
        );

    final parts = <ModelPart>[];
    for (final surface in document.surfaces) {
      final index = surface.materialIndex;
      // `KHR_texture_transform`, honoured in the coordinates: see
      // `texture_transform_bake.dart` for why here and not in the decoder or
      // the sampler.
      final moved =
          index != null && index >= 0 && index < document.materials.length
          ? sharedTextureTransform(document.materials[index])
          : null;
      final mesh = meshCache.putIfAbsent(
        (surface.mesh, moved),
        () => DeviceMesh.upload(
          device,
          moved == null
              ? surface.mesh
              : withTextureTransform(surface.mesh, moved),
        ),
      );
      final morph = morphFor(surface.mesh, surface.name ?? 'a surface');

      final material =
          index != null && index >= 0 && index < document.materials.length
          ? await materialAt(index)
          : materialCache[-1] ??= Material(lighting: lighting);

      // Each variant's material is bound now, with the default one, so that
      // switching variants is an assignment rather than an upload. The mesh
      // is not re-uploaded per variant: the texture transform baked into it
      // is the default material's, and a variant whose own transform differs
      // is said so rather than drawn quietly with the wrong one.
      final variantMaterials = <int, Material>{};
      for (final MapEntry(key: variant, value: other)
          in surface.variantMaterials.entries) {
        if (other < 0 || other >= document.materials.length) continue;
        variantMaterials[variant] = await materialAt(other);
        final theirs = sharedTextureTransform(document.materials[other]);
        final same = theirs == null
            ? moved == null
            : moved != null && theirs.sameAs(moved);
        if (!same) {
          warnings.add(
            '${surface.name ?? 'a surface'}: variant $variant\'s material has '
            'a different KHR_texture_transform from the default one; the '
            'default\'s is the one baked into the mesh.',
          );
        }
      }

      parts.add(
        ModelPart(
          mesh: mesh,
          material: material,
          transform: surface.transform,
          name: surface.name,
          skinIndex: surface.skinIndex,
          flipWinding: surface.flipWinding,
          morphTexture: morph.texture,
          morphTargetCount: morph.count,
          morphWeights: surface.morphWeights,
          morphReaches: morph.reaches,
          variantMaterials: variantMaterials,
        ),
      );
    }

    // `C4`: an impostor's atlases are read by view, so no mip chain — a chain
    // averages each view's cell into its neighbours'. A level whose atlases
    // will not decode is dropped with a warning, and the chain ends at the
    // coarsest mesh instead.
    const atlasSampling = TextureSampling(
      useMipmaps: false,
      wrapS: TextureWrap.clampToEdge,
      wrapT: TextureWrap.clampToEdge,
    );
    final impostors = <ModelImpostor, ImpostorPart>{};
    for (final node in document.nodes) {
      for (final lod in node.lods) {
        final impostor = lod.impostor;
        if (impostor == null) continue;
        final albedo = await textureFor(impostor.albedoImage, atlasSampling);
        final normalDepth = await textureFor(
          impostor.normalDepthImage,
          atlasSampling,
        );
        if (albedo == null || normalDepth == null) {
          warnings.add(
            '${node.name ?? 'a node'}: its impostor atlases did not decode; '
            'its levels end at the coarsest mesh.',
          );
          continue;
        }
        impostors[impostor] = (
          card: DeviceMesh.upload(
            device,
            impostorCard(centre: impostor.centre, radius: impostor.radius),
          ),
          albedo: albedo,
          normalDepth: normalDepth,
        );
      }
    }

    return ModelAsset(
      variants: document.variants,
      materials: <int, Material>{
        for (final MapEntry(:key, :value) in materialCache.entries)
          if (key >= 0) key: value,
      },
      name: name,
      parts: parts,
      impostors: impostors,
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
    for (final impostor in impostors.values) {
      meshes.add(impostor.card);
      textures
        ..add(impostor.albedo)
        ..add(impostor.normalDepth);
    }
    for (final part in parts) {
      meshes.add(part.mesh);
      // A variant's material holds textures the default one may not.
      for (final material in <Material>[
        part.material,
        ...part.variantMaterials.values,
      ]) {
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
    }
    for (final mesh in meshes) {
      device.releaseGeometry(mesh.vertices);
      device.releaseGeometry(mesh.indices);
    }
    for (final texture in textures) {
      device.releaseTexture(texture);
    }
  }
}
