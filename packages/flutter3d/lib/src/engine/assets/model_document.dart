import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../animation/animation.dart';
import '../geometry/geometry.dart';

/// How a surface treats the alpha channel.
enum SurfaceAlphaMode { opaque, mask, blend }

enum TextureWrap { repeat, clampToEdge, mirroredRepeat }

/// Filtering and wrapping requested for a texture.
final class TextureSampling {
  const TextureSampling({
    this.magLinear = true,
    this.minLinear = true,
    this.useMipmaps = true,
    this.wrapS = TextureWrap.repeat,
    this.wrapT = TextureWrap.repeat,
  });

  final bool magLinear;
  final bool minLinear;

  /// Assets almost always request mipmapped minification. Recorded and, so far,
  /// ignored by the renderer — the visible cost is aliasing on minified
  /// surfaces.
  ///
  /// Not a fact about rendering: one backend exposes no mip levels, another has
  /// them. The engine builds none either way today, so the field is carried
  /// rather than acted on, and honouring it would start with asking the device
  /// rather than assuming this.
  final bool useMipmaps;

  final TextureWrap wrapS;
  final TextureWrap wrapT;
}

/// A reference from a material to one of the document's images.
///
/// Always an index, never a path: glTF addresses images by index while OBJ uses
/// relative filenames, and normalizing to an index in the decoder is what lets
/// consumers upload images without knowing which format they came from.
final class TextureBinding {
  const TextureBinding({
    required this.imageIndex,
    this.texCoordSet = 0,
    this.sampling = const TextureSampling(),
  });

  final int imageIndex;

  /// Which texcoord set to sample with. Only set 0 is decoded today.
  final int texCoordSet;

  final TextureSampling sampling;
}

/// An image still in its source encoding (PNG, JPEG, …).
///
/// Decoding is left to the caller because it needs `dart:ui`, and keeping that
/// out of the decoders is what lets the whole asset layer be unit tested with no
/// Flutter binding.
final class EncodedImage {
  const EncodedImage({required this.bytes, this.name, this.mimeType});

  final Uint8List bytes;
  final String? name;
  final String? mimeType;

  bool get isEmpty => bytes.isEmpty;
}

/// Format-neutral description of how a surface looks.
///
/// The single material abstraction every decoder produces. Metal-rough is the
/// target because it is what glTF defines and what the shaders implement; formats
/// that predate it (OBJ's Phong parameters) are approximated at decode time, with
/// the approximation documented where it happens rather than hidden.
final class SurfaceMaterial {
  SurfaceMaterial({
    this.name,
    Vector4? baseColor,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.baseColorTexture,
    this.metallicRoughnessTexture,
    this.normalTexture,
    this.normalScale = 1.0,
    this.occlusionTexture,
    this.occlusionStrength = 1.0,
    this.emissiveTexture,
    Vector3? emissive,
    this.emissiveStrength = 1.0,
    this.alphaMode = SurfaceAlphaMode.opaque,
    this.alphaCutoff = 0.5,
    this.doubleSided = false,
    this.unlit = false,
  })  : baseColor = baseColor ?? Vector4(1.0, 1.0, 1.0, 1.0),
        emissive = emissive ?? Vector3.zero();

  final String? name;

  /// RGBA tint as authored, i.e. non-linear for the colour channels.
  final Vector4 baseColor;

  final double metallic;
  final double roughness;

  final TextureBinding? baseColorTexture;
  final TextureBinding? metallicRoughnessTexture;
  final TextureBinding? normalTexture;
  final double normalScale;
  final TextureBinding? occlusionTexture;
  final double occlusionStrength;
  final TextureBinding? emissiveTexture;
  final Vector3 emissive;
  final double emissiveStrength;

  final SurfaceAlphaMode alphaMode;
  final double alphaCutoff;
  final bool doubleSided;

  /// Shade with albedo only, from glTF's `KHR_materials_unlit` or an OBJ material
  /// with no specular response at all.
  final bool unlit;

  @override
  String toString() => 'SurfaceMaterial(${name ?? 'unnamed'}, '
      'metallic: $metallic, roughness: $roughness)';
}

/// One drawable piece of a decoded model.
final class ModelSurface {
  ModelSurface({
    required this.mesh,
    Matrix4? transform,
    this.materialIndex,
    this.skinIndex,
    this.flipWinding = false,
    this.name,
  }) : transform = transform ?? Matrix4.identity();

  final MeshData mesh;

  /// Placement relative to the model's own origin.
  final Matrix4 transform;

  final int? materialIndex;

  /// Index into [ModelDocument.skins], when this surface is skinned.
  ///
  /// On the surface rather than the node because that is where glTF puts it and
  /// where it belongs: two nodes can draw the same mesh with different skins.
  final int? skinIndex;

  /// True when [transform] mirrors, i.e. has a negative determinant.
  ///
  /// Mirroring reverses on-screen triangle orientation, so the renderer must flip
  /// its front-face winding or backface culling discards exactly the faces meant
  /// to be visible.
  final bool flipWinding;

  final String? name;
}

/// A node in a decoded model's hierarchy.
///
/// The hierarchy exists so animation has something to target. A flattened list
/// of surfaces with baked transforms is enough to draw a static model, but an
/// animation track says "move node 7", and a node that moves has to carry its
/// subtree with it — which is exactly the information flattening throws away.
///
/// TRS rather than a matrix, because that is what animation interpolates and
/// what [SceneNode] stores.
final class ModelNode {
  ModelNode({
    this.name,
    Vector3? translation,
    Quaternion? rotation,
    Vector3? scale,
    List<int>? children,
    List<int>? surfaces,
  })  : translation = translation ?? Vector3.zero(),
        rotation = rotation ?? Quaternion.identity(),
        scale = scale ?? Vector3(1.0, 1.0, 1.0),
        children = children ?? <int>[],
        surfaces = surfaces ?? <int>[];

  final String? name;

  final Vector3 translation;
  final Quaternion rotation;
  final Vector3 scale;

  /// Indices into [ModelDocument.nodes].
  final List<int> children;

  /// Indices into [ModelDocument.surfaces] drawn at this node.
  final List<int> surfaces;

  Matrix4 toMatrix() => Matrix4.compose(translation, rotation, scale);

  @override
  String toString() => 'ModelNode(${name ?? 'unnamed'}, '
      '${children.length} children, ${surfaces.length} surfaces)';
}

/// A skeleton: which nodes are joints, and how each undoes the bind pose.
///
/// Indices into [ModelDocument.nodes], because a joint *is* a node — glTF says
/// so, and it is what makes an animation clip drive a skeleton without the two
/// features knowing about each other. The player writes node transforms; the
/// skin reads them.
final class ModelSkin {
  ModelSkin({
    required this.joints,
    required this.inverseBindMatrices,
    this.skeletonRoot,
    this.name,
  }) {
    if (inverseBindMatrices.length != joints.length) {
      throw ArgumentError(
        'Skin "${name ?? 'unnamed'}" has ${joints.length} joints but '
        '${inverseBindMatrices.length} inverse bind matrices.',
      );
    }
  }

  final String? name;

  /// Node indices, in the order the vertex attribute addresses them.
  final List<int> joints;

  /// One per joint: the transform that takes a vertex from model space into
  /// that joint's local space at bind time.
  ///
  /// Without it a joint's world transform would move the mesh by the joint's
  /// *absolute* placement rather than by how far it has moved since binding, so
  /// the model would fly apart the moment it was posed.
  final List<Matrix4> inverseBindMatrices;

  /// The node the skeleton hangs from, when the file names one.
  final int? skeletonRoot;

  int get jointCount => joints.length;

  @override
  String toString() =>
      'ModelSkin(${name ?? 'unnamed'}, ${joints.length} joints)';
}

/// A decoded model, whatever format it came from.
///
/// The seam between decoders and the rest of the engine: glTF and OBJ both
/// produce one of these, so uploading, instancing and material conversion are
/// written once instead of per format.
abstract class ModelDocument {
  const ModelDocument();

  List<ModelSurface> get surfaces;
  List<SurfaceMaterial> get materials;
  List<EncodedImage> get images;

  /// The model's node hierarchy.
  ///
  /// Defaults to one node per surface, which is the truth for a format that has
  /// no hierarchy at all — OBJ groups are siblings, not a tree. A decoder with a
  /// real hierarchy overrides this, and animation then has something to target.
  List<ModelNode> get nodes {
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3(1.0, 1.0, 1.0);

    return <ModelNode>[
      for (var i = 0; i < surfaces.length; i++)
        () {
          surfaces[i].transform.decompose(translation, rotation, scale);
          return ModelNode(
            name: surfaces[i].name,
            translation: translation.clone(),
            rotation: rotation.clone(),
            scale: scale.clone(),
            surfaces: <int>[i],
          );
        }(),
    ];
  }

  /// Indices into [nodes] with no parent.
  List<int> get roots => <int>[for (var i = 0; i < nodes.length; i++) i];

  /// Clips that drive [nodes]. Empty for formats that carry no animation.
  List<AnimationClip> get animations => const <AnimationClip>[];

  /// Skeletons. Empty for formats that carry no skinning.
  List<ModelSkin> get skins => const <ModelSkin>[];

  /// Non-fatal findings from decoding: ignored extensions, skipped primitives,
  /// unresolved references. Surfaced rather than logged so callers can decide
  /// whether to care.
  List<String> get warnings;

  int get vertexCount {
    var total = 0;
    for (final surface in surfaces) {
      total += surface.mesh.vertexCount;
    }
    return total;
  }

  int get triangleCount {
    var total = 0;
    for (final surface in surfaces) {
      total += surface.mesh.triangleCount;
    }
    return total;
  }

  /// Bounds in the model's own space.
  ///
  /// Transforms the eight corners of each surface's local box rather than the box
  /// itself, because rotating a box and taking its extents is only correct for
  /// axis-aligned rotations.
  Aabb3 computeBounds() {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    var any = false;

    final corner = Vector3.zero();
    for (final surface in surfaces) {
      if (surface.mesh.vertexCount == 0) continue;
      final local = surface.mesh.computeBounds();
      for (var i = 0; i < 8; i++) {
        corner.setValues(
          (i & 1) == 0 ? local.min.x : local.max.x,
          (i & 2) == 0 ? local.min.y : local.max.y,
          (i & 4) == 0 ? local.min.z : local.max.z,
        );
        surface.transform.transform3(corner);
        any = true;
        if (corner.x < minX) minX = corner.x;
        if (corner.y < minY) minY = corner.y;
        if (corner.z < minZ) minZ = corner.z;
        if (corner.x > maxX) maxX = corner.x;
        if (corner.y > maxY) maxY = corner.y;
        if (corner.z > maxZ) maxZ = corner.z;
      }
    }

    if (!any) return Aabb3();
    return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
  }
}
