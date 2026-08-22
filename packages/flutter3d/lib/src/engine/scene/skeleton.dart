import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'scene_node.dart';

/// A posed skeleton: joint nodes plus the matrices that undo their bind pose.
///
/// Sits on top of [SceneNode] rather than replacing it, which is what keeps
/// skinning and animation independent of each other. A joint is an ordinary
/// node; the animation player writes its transform the way it writes any other,
/// and this reads the result. Neither feature contains a line about the other.
///
/// The matrices go into a uniform array, the same mechanism the lights use and
/// for the same reason: shaders are compiled ahead of time, so a permutation per
/// joint count is not on the table. The spike behind that decision is recorded
/// in RESEARCH.md §4.
final class Skeleton {
  Skeleton({
    required this.joints,
    required List<Matrix4> inverseBindMatrices,
    this.skeletonRoot,
    this.name,
  }) : _inverseBind = List<Matrix4>.of(inverseBindMatrices) {
    if (_inverseBind.length != joints.length) {
      throw ArgumentError(
        'Skeleton "${name ?? 'unnamed'}" has ${joints.length} joints and '
        '${_inverseBind.length} inverse bind matrices.',
      );
    }
    if (joints.length > maxJoints) {
      throw ArgumentError(
        'Skeleton "${name ?? 'unnamed'}" has ${joints.length} joints; the '
        'shader holds $maxJoints. Split the mesh or raise kMaxJoints in '
        'shaders/lib/skin.glsl and rebuild the bundle.',
      );
    }
  }

  /// Joints the shader can hold. Must match `kMaxJoints` in the GLSL.
  ///
  /// 64 rather than a larger round number because the whole array is written
  /// into the per-frame host buffer on every skinned draw: at 64 bytes a matrix
  /// this is a 4 KB upload, and doubling it doubles that cost for every skinned
  /// mesh whether or not it has the joints to justify it.
  static const int maxJoints = 64;

  final String? name;

  /// The nodes being followed, in the order the vertex attribute indexes them.
  final List<SceneNode> joints;

  /// The node the skin hangs from, when the model named one.
  final SceneNode? skeletonRoot;

  final List<Matrix4> _inverseBind;

  /// Column-major joint matrices, laid out for the uniform array.
  ///
  /// Allocated once and rewritten in place: a skinned model updates this every
  /// frame, and a fresh list per frame is exactly the allocation pattern the
  /// render list was shaped to avoid.
  final Float32List matrices = Float32List(maxJoints * 16);

  int get jointCount => joints.length;

  final Matrix4 _scratch = Matrix4.identity();
  final Matrix4 _measure = Matrix4.identity();

  /// How far one unit of the mesh's own space reaches once it is skinned.
  ///
  /// **A skinned mesh's vertex positions are not in metres.** A rig exported
  /// from Blender routinely carries them at a hundredth of one: the size lives
  /// in the joint hierarchy, and `jointWorld * inverseBind` is what carries a
  /// vertex out into the world. So anything measured off the vertex buffer — a
  /// bounding box, a bounding radius, a reach — is a number in that small space
  /// and means nothing beside a joint position until it is brought out.
  ///
  /// Both models this repository ships are like that. The crypt's monsters are
  /// authored at a hundredth and the platformer's hero at a fortieth, so a mesh
  /// whose own radius reads 0.02 is a body that reaches half a metre off the
  /// bone.
  ///
  /// Read off the first joint, because at any one moment every joint carries
  /// the same skin-to-world scale — they differ in rotation and position, which
  /// is what a pose is, not in how big the space is.
  double get skinScale {
    if (joints.isEmpty) return 1.0;
    _measure
      ..setFrom(joints.first.worldMatrix)
      ..multiply(_inverseBind.first);
    final storage = _measure.storage;
    return math.sqrt(
      storage[0] * storage[0] +
          storage[1] * storage[1] +
          storage[2] * storage[2],
    );
  }

  /// Recomputes [matrices] for the current pose.
  ///
  /// [meshWorld] is the world transform of the node the skinned mesh hangs
  /// from. The glTF formula is
  ///
  /// ```
  /// jointMatrix = inverse(meshWorld) * jointWorld * inverseBind
  /// ```
  ///
  /// and every term earns its place. `inverseBind` takes a vertex from model
  /// space into the joint's local space as it was when the model was bound;
  /// `jointWorld` puts it back out into the world through wherever the joint has
  /// since moved; `inverse(meshWorld)` returns it to the mesh's own space,
  /// because the renderer is about to apply that transform again. Drop the last
  /// term and a skinned model is placed twice.
  void update(Matrix4 meshWorld) {
    _scratch.setFrom(meshWorld);
    _scratch.invert();

    for (var i = 0; i < joints.length; i++) {
      final joint = Matrix4.copy(_scratch);
      joint.multiply(joints[i].worldMatrix);
      joint.multiply(_inverseBind[i]);

      final storage = joint.storage;
      final base = i * 16;
      for (var e = 0; e < 16; e++) {
        matrices[base + e] = storage[e];
      }
    }

    // Everything past the joint count stays identity, so a shader reading a
    // stale slot — a mesh whose weights name a joint the skeleton does not have
    // — leaves the vertex where it is instead of sending it to the origin.
    for (var i = joints.length; i < maxJoints; i++) {
      final base = i * 16;
      for (var e = 0; e < 16; e++) {
        matrices[base + e] = e % 5 == 0 ? 1.0 : 0.0;
      }
    }
  }

  /// World-space bounds of the posed skeleton, padded by [reach].
  ///
  /// A skinned mesh's own bounds describe its bind pose, which is a different
  /// shape from wherever the animation has put it — culling against them makes
  /// a running character vanish as it leans out of a box it left several frames
  /// ago. The joints are where the mesh actually is, and [reach] covers the
  /// distance flesh hangs off the bone.
  Aabb3 computeBounds({double reach = 0.0}) {
    if (joints.isEmpty) return Aabb3();

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;

    final position = Vector3.zero();
    for (final joint in joints) {
      joint.readWorldPosition(position);
      if (position.x < minX) minX = position.x;
      if (position.y < minY) minY = position.y;
      if (position.z < minZ) minZ = position.z;
      if (position.x > maxX) maxX = position.x;
      if (position.y > maxY) maxY = position.y;
      if (position.z > maxZ) maxZ = position.z;
    }

    return Aabb3.minMax(
      Vector3(minX - reach, minY - reach, minZ - reach),
      Vector3(maxX + reach, maxY + reach, maxZ + reach),
    );
  }

  /// A version stamp that changes whenever any joint moves.
  ///
  /// Lets a consumer skip the update entirely for a skeleton at rest, using the
  /// same mechanism the world matrices already use. Summed rather than hashed
  /// because the stamps are globally unique and monotonic, so a sum cannot
  /// repeat without one of them going backwards.
  int get poseVersion {
    var total = joints.length;
    for (final joint in joints) {
      total += joint.worldVersion;
    }
    return total;
  }

  @override
  String toString() =>
      'Skeleton(${name ?? 'unnamed'}, ${joints.length} joints)';
}
