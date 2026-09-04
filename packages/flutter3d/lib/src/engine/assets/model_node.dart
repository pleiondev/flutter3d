import 'package:vector_math/vector_math.dart';

import '../geometry/geometry.dart';

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
  }) : translation = translation ?? Vector3.zero(),
       rotation = rotation ?? Quaternion.identity(),
       scale = scale ?? Vector3(1.0, 1.0, 1.0),
       children = children ?? <int>[],
       surfaces = surfaces ?? <int>[];

  final String? name;

  final Vector3 translation;
  final Quaternion rotation;
  final Vector3 scale;

  /// Indices into `ModelDocument.nodes`.
  final List<int> children;

  /// Indices into `ModelDocument.surfaces` drawn at this node.
  final List<int> surfaces;

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

  int get jointCount => joints.length;

  @override
  String toString() =>
      'ModelSkin(${name ?? 'unnamed'}, ${joints.length} joints)';
}
