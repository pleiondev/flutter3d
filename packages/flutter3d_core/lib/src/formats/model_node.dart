import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'splat/splat_cloud.dart';

/// One drawable piece of a decoded model.
final class ModelSurface {
  ModelSurface({
    required this.mesh,
    Matrix4? transform,
    this.materialIndex,
    this.skinIndex,
    this.flipWinding = false,
    this.name,
    this.meshName,
    List<double>? morphWeights,
    Set<String>? authoredAttributes,
  }) : transform = transform ?? Matrix4.identity(),
       morphWeights = morphWeights ?? const <double>[],
       authoredAttributes =
           authoredAttributes ??
           <String>{for (final a in mesh.layout.attributes) a.name};

  final MeshData mesh;

  /// Placement relative to the model's own origin.
  final Matrix4 transform;

  final int? materialIndex;

  /// Index into `ModelDocument.skins`, when this surface is skinned.
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

  /// The name of the mesh asset [mesh] was built from, distinct from [name].
  ///
  /// glTF separates a node's own name from the mesh it draws — two nodes can
  /// share one mesh under two different names — and [name] here already
  /// prefers the node's, which is what an outliner wants to show. This is the
  /// other one, kept for a writer that wants to say "this surface came from
  /// the asset called X" rather than "the node that draws it is called Y".
  /// Null for a format with no such distinction — OBJ's groups are already
  /// the only name a surface has.
  final String? meshName;

  /// The rest weights of [mesh]'s morph targets: the expression the model wears
  /// before anything animates it.
  ///
  /// On the surface and not on the mesh because a node overrides them — glTF
  /// puts a default on the mesh and lets each node that draws it disagree, so
  /// two copies of one face can start in different moods. Empty for the models
  /// that morph nothing, which is nearly all of them.
  final List<double> morphWeights;

  /// Which of [mesh.layout]'s attribute names the source file actually
  /// declared, as opposed to a value a decoder filled in to satisfy a
  /// requested [VertexLayout].
  ///
  /// **Both decoders in this package fill in slots the file never had.** A
  /// glTF primitive with no `NORMAL` gets a flat one computed from its faces
  /// when the requested layout wants one; one with no `TEXCOORD_0` gets a
  /// vertex zeroed at that slot rather than an attribute the layout does not
  /// have room to omit. OBJ has no tangent record at all, so a requested
  /// tangent is *always* generated. A writer re-exporting the surface reads
  /// this to decide what to write back rather than re-declaring a value that
  /// was never really there.
  ///
  /// Defaults to every name [mesh.layout] has, so a document built by hand —
  /// every test in this repository before `fmt-03`, and any future one that
  /// does not care — behaves as if the whole layout was authored, which is
  /// also what a `.f3d` written before this field existed means when it is
  /// read back.
  final Set<String> authoredAttributes;
}

/// One level of detail a node offers in place of its own full surface list
/// — `pro-eng-06`'s own row.
///
/// **Surfaces, not sibling nodes.** glTF's own `MSFT_lod` extension names
/// alternate *nodes* of decreasing detail rather than alternate surface
/// lists on one node, which is a real, different shape from this one — a
/// `.f3d` file round-trips [ModelNode.lods] directly; a glTF file does not
/// yet, because doing so correctly means deciding how this node's own
/// surface-level LODs become `MSFT_lod`'s sibling-node ones, and that
/// mapping is not built.
final class ModelLod {
  const ModelLod({
    required this.surfaceIndices,
    required this.maxScreenFraction,
  });

  /// Indices into `ModelDocument.surfaces`, replacing the node's own
  /// [ModelNode.surfaces] when this level is the one in use.
  final List<int> surfaceIndices;

  /// The largest fraction of the screen this level is meant for — a viewer
  /// switches to a coarser level once the node would cover less of the
  /// screen than the next level's own threshold.
  final double maxScreenFraction;

  @override
  String toString() =>
      'ModelLod(${surfaceIndices.length} surfaces, '
      'maxScreenFraction: $maxScreenFraction)';
}

/// The colour space a splat's colours were fitted in, as
/// `KHR_gaussian_splatting`'s `colorSpace` names it.
enum SplatColourSpace {
  /// `srgb_rec709_display`: the fitted colours are sRGB-encoded.
  srgb,

  /// `lin_rec709_display`: the fitted colours are already linear.
  linear,
}

/// A cloud of Gaussian splats a node of a decoded model carries — `C1`.
///
/// **Beside the surfaces, not one of them.** A splat primitive is a glTF mesh
/// primitive, but nothing about it is a mesh: no triangles, no material (the
/// extension says the primitive's material is ignored), and a draw of its own
/// through `SplatContributor`. So it is listed here with the node that
/// instantiates it rather than bent into a [ModelSurface] every surface
/// consumer would then have to know to skip.
final class ModelSplat {
  ModelSplat({
    required this.node,
    required this.cloud,
    required this.colourSpace,
    Matrix4? transform,
    this.meshIndex,
  }) : transform = transform ?? Matrix4.identity();

  /// Index into `ModelDocument.nodes` of the node that instantiates it.
  final int node;

  /// The splats, in the node's own space, with linear colours whatever
  /// [colourSpace] the file declared — see `gltf_loader_mesh.dart`.
  final SplatCloud cloud;

  /// What the file declared, kept for a writer and for anyone who wants to
  /// know why the colours were decoded.
  final SplatColourSpace colourSpace;

  /// The node's placement relative to the model's origin, the same thing
  /// [ModelSurface.transform] is for a surface.
  final Matrix4 transform;

  /// The source mesh's index, when the format has meshes. Two nodes drawing
  /// one mesh share one [cloud].
  final int? meshIndex;

  @override
  String toString() =>
      'ModelSplat(node $node, ${cloud.count} splats, ${colourSpace.name})';
}

/// A node in a decoded model's hierarchy.
///
/// The hierarchy exists so animation has something to target. A flattened list
/// of surfaces with baked transforms is enough to draw a static model, but an
/// animation track says "move node 7", and a node that moves has to carry its
/// subtree with it — which is exactly the information flattening throws away.
///
/// TRS rather than a matrix, because that is what animation interpolates and
/// what `SceneNode` stores.
final class ModelNode {
  ModelNode({
    this.name,
    Vector3? translation,
    Quaternion? rotation,
    Vector3? scale,
    List<int>? children,
    List<int>? surfaces,
    this.extras,
    this.lightIndex,
    this.cameraIndex,
    List<ModelLod>? lods,
  }) : translation = translation ?? Vector3.zero(),
       rotation = rotation ?? Quaternion.identity(),
       scale = scale ?? Vector3(1.0, 1.0, 1.0),
       children = children ?? <int>[],
       surfaces = surfaces ?? <int>[],
       // Growable, not `const`, matching [surfaces]'s own default: glTF's
       // `MSFT_lod` decode appends to this in place as it discovers a node's
       // lower-detail siblings, the same way the scene walk appends to
       // `surfaces` as it discovers primitives.
       lods = lods ?? <ModelLod>[];

  final String? name;

  final Vector3 translation;
  final Quaternion rotation;
  final Vector3 scale;

  /// Indices into `ModelDocument.nodes`.
  final List<int> children;

  /// Indices into `ModelDocument.surfaces` drawn at this node.
  final List<int> surfaces;

  /// glTF's own `extras` on this node, carried opaquely — `fmt-19`'s own
  /// row. Nothing here reads a key out of it; a decoder copies the JSON
  /// object verbatim and a writer copies it back, so whatever an authoring
  /// tool put here survives a round trip even though nothing in this engine
  /// interprets it.
  final Map<String, Object?>? extras;

  /// Index into `ModelDocument.lights`, when a `KHR_lights_punctual` light
  /// is attached to this node — `fmt-28`'s own row. Null for the ordinary
  /// node, which is nearly all of them.
  final int? lightIndex;

  /// Index into `ModelDocument.cameras`, when glTF's own `camera` key
  /// names one on this node.
  final int? cameraIndex;

  /// Coarser stand-ins for [surfaces], each good up to its own
  /// [ModelLod.maxScreenFraction] — `pro-eng-06`'s own row. Empty for the
  /// ordinary node, which is nearly all of them, and for every node in a
  /// `.f3d` written before this field existed: the section is absent
  /// rather than empty, and an absent section reads as no LODs for exactly
  /// that file.
  final List<ModelLod> lods;

  Matrix4 toMatrix() => Matrix4.compose(translation, rotation, scale);

  @override
  String toString() =>
      'ModelNode(${name ?? 'unnamed'}, '
      '${children.length} children, ${surfaces.length} surfaces)';
}

/// A skeleton: which nodes are joints, and how each undoes the bind pose.
///
/// Indices into `ModelDocument.nodes`, because a joint *is* a node — glTF says
/// so, and it is what makes an animation clip drive a skeleton without the two
/// features knowing about each other. The player writes node transforms; the
/// skin reads them.
final class ModelSkin {
  ModelSkin({
    required List<int> joints,
    required this.inverseBindMatrices,
    this.skeletonRoot,
    this.name,
    this.extras,
  }) : joints = List.unmodifiable(joints) {
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

  /// glTF's own `extras` on this skin, carried opaquely — see
  /// [ModelNode.extras] for what that means and why.
  final Map<String, Object?>? extras;

  int get jointCount => joints.length;

  @override
  String toString() =>
      'ModelSkin(${name ?? 'unnamed'}, ${joints.length} joints)';
}
