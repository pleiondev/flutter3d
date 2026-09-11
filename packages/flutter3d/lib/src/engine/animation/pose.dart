import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:vector_math/vector_math.dart';

import '../scene/skeleton.dart';
import 'animation_target.dart';

/// A flat, scene-graph-free pose: one hierarchy's local TRS, sampled from a
/// clip and composed into world and joint matrices without ever touching a
/// [SceneNode] — `anim-01`'s own row.
///
/// **Why this exists beside [AnimationPlayer] and [Skeleton].**
/// `AnimationPlayer` writes onto `AnimationTarget`s: live nodes that cache
/// their own matrix and version stamp, the right shape for one skeleton on
/// screen. Phase 3's rig pipeline needs the opposite shape more than once —
/// a mocap importer walking a clip a thousand samples at a time, a retarget
/// pass comparing two poses side by side, a bake that never touches a
/// running `Scene` at all. None of those wants a scene node, and building
/// one just to throw it away is real allocation for a question that is
/// really just arithmetic on three typed arrays.
///
/// **The formula is not reinvented.** [worldMatrices] composes parent then
/// child in exactly the order `SceneNode.worldMatrix` does
/// (`parentWorld * localMatrix`), and [jointMatrices] applies the same
/// `inverse(meshWorld) * jointWorld * inverseBind` [Skeleton.update]
/// documents — read that doc comment for why each term is there. The two
/// paths are meant to agree to floating-point rounding, and
/// `test/pose_test.dart` holds them to it on `RiggedSimple.glb` and
/// `BoxAnimated.glb`, sampled through the ordinary scene-graph pipeline and
/// through this one, at several times across the clip.
final class Pose {
  Pose({
    required List<int> parents,
    required Float32List restTranslations,
    required Float32List restRotations,
    required Float32List restScales,
  }) : parents = List<int>.unmodifiable(parents),
       translations = Float32List.fromList(restTranslations),
       rotations = Float32List.fromList(restRotations),
       scales = Float32List.fromList(restScales),
       _restTranslations = restTranslations,
       _restRotations = restRotations,
       _restScales = restScales {
    final n = parents.length;
    if (restTranslations.length != n * 3 ||
        restScales.length != n * 3 ||
        restRotations.length != n * 4) {
      throw ArgumentError(
        'Pose has $n nodes but ${restTranslations.length ~/ 3} translations, '
        '${restRotations.length ~/ 4} rotations and '
        '${restScales.length ~/ 3} scales.',
      );
    }
  }

  /// One node's parent index into this same pose, or -1 for a root.
  ///
  /// Not required to precede its child in array order — glTF's own `nodes`
  /// array makes no such promise, and [worldMatrices] does not rely on one.
  final List<int> parents;

  /// The bind/rest pose every [sampleClip] call starts back from, so a track
  /// that says nothing about a node leaves it exactly where the file put it.
  final Float32List _restTranslations;
  final Float32List _restRotations;
  final Float32List _restScales;

  /// Current local translation, 3 floats per node.
  final Float32List translations;

  /// Current local rotation, 4 floats per node, glTF's own xyzw order.
  final Float32List rotations;

  /// Current local scale, 3 floats per node.
  final Float32List scales;

  int get nodeCount => parents.length;

  /// Builds a pose from a document's own node list.
  ///
  /// [parents] is inverted out of each node's `children` rather than stored
  /// anywhere — nothing in [ModelNode] carries it, since the hierarchy is
  /// ordinarily walked top-down. Rest TRS is read straight off
  /// [ModelNode.translation]/[ModelNode.rotation]/[ModelNode.scale], which is
  /// the pose the file loads into before any clip has touched it.
  factory Pose.fromNodes(List<ModelNode> nodes) {
    final parents = List<int>.filled(nodes.length, -1);
    for (var i = 0; i < nodes.length; i++) {
      for (final child in nodes[i].children) {
        if (child >= 0 && child < nodes.length) parents[child] = i;
      }
    }

    final t = Float32List(nodes.length * 3);
    final r = Float32List(nodes.length * 4);
    final s = Float32List(nodes.length * 3);
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      t[i * 3] = node.translation.x;
      t[i * 3 + 1] = node.translation.y;
      t[i * 3 + 2] = node.translation.z;
      r[i * 4] = node.rotation.x;
      r[i * 4 + 1] = node.rotation.y;
      r[i * 4 + 2] = node.rotation.z;
      r[i * 4 + 3] = node.rotation.w;
      s[i * 3] = node.scale.x;
      s[i * 3 + 1] = node.scale.y;
      s[i * 3 + 2] = node.scale.z;
    }

    return Pose(
      parents: parents,
      restTranslations: t,
      restRotations: r,
      restScales: s,
    );
  }

  /// Puts every node back at its rest transform.
  void resetToRest() {
    translations.setAll(0, _restTranslations);
    rotations.setAll(0, _restRotations);
    scales.setAll(0, _restScales);
  }

  final Float32List _sample3 = Float32List(3);
  final Float32List _sample4 = Float32List(4);

  /// Resets to rest, then samples every track of [clip] at [time] onto the
  /// nodes it names.
  ///
  /// **A node no track in [clip] touches keeps its rest transform** — the
  /// same rule `AnimationPlayer.apply` follows for the identical reason: an
  /// animation that says nothing about an arm has not asked for the arm to
  /// move. Weight tracks are skipped outright; they drive morph targets, not
  /// a joint's TRS, and this pose has nowhere to put them.
  void sampleClip(AnimationClip clip, double time) {
    resetToRest();
    for (final track in clip.tracks) {
      final node = track.nodeIndex;
      if (node < 0 || node >= nodeCount) continue;

      switch (track.path) {
        case AnimationPath.translation:
          track.sample(time, _sample3);
          translations[node * 3] = _sample3[0];
          translations[node * 3 + 1] = _sample3[1];
          translations[node * 3 + 2] = _sample3[2];

        case AnimationPath.rotation:
          track.sample(time, _sample4);
          rotations[node * 4] = _sample4[0];
          rotations[node * 4 + 1] = _sample4[1];
          rotations[node * 4 + 2] = _sample4[2];
          rotations[node * 4 + 3] = _sample4[3];

        case AnimationPath.scale:
          track.sample(time, _sample3);
          scales[node * 3] = _sample3[0];
          scales[node * 3 + 1] = _sample3[1];
          scales[node * 3 + 2] = _sample3[2];

        case AnimationPath.weights:
          break;
      }
    }
  }

  /// Node [index]'s local transform, composed the same way
  /// `SceneNode.worldMatrix` composes its own — see `Matrix4.compose`, which
  /// is `setFromTranslationRotationScale` under another name.
  Matrix4 localMatrix(int index) => Matrix4.compose(
    Vector3(
      translations[index * 3],
      translations[index * 3 + 1],
      translations[index * 3 + 2],
    ),
    Quaternion(
      rotations[index * 4],
      rotations[index * 4 + 1],
      rotations[index * 4 + 2],
      rotations[index * 4 + 3],
    ),
    Vector3(scales[index * 3], scales[index * 3 + 1], scales[index * 3 + 2]),
  );

  /// Node [index]'s *rest* local transform — what [localMatrix] would return
  /// right after [resetToRest], without disturbing whatever the pose is
  /// currently holding.
  ///
  /// A caller comparing a sampled pose against the bind pose — a retarget
  /// pass measuring how far a joint has moved, a tool asking "is this rig
  /// still at rest" — wants both numbers at once, and resetting the whole
  /// pose to get one of them would throw the other away.
  Matrix4 restOf(int index) => Matrix4.compose(
    Vector3(
      _restTranslations[index * 3],
      _restTranslations[index * 3 + 1],
      _restTranslations[index * 3 + 2],
    ),
    Quaternion(
      _restRotations[index * 4],
      _restRotations[index * 4 + 1],
      _restRotations[index * 4 + 2],
      _restRotations[index * 4 + 3],
    ),
    Vector3(
      _restScales[index * 3],
      _restScales[index * 3 + 1],
      _restScales[index * 3 + 2],
    ),
  );

  /// World matrices for every node, index-aligned with [parents].
  ///
  /// Composed parent before child regardless of array order: [parents] may
  /// name a later index as easily as an earlier one, so this walks each
  /// node's ancestry on demand and memoizes it, rather than assuming a
  /// single forward pass ever sees a parent before its child.
  List<Matrix4> worldMatrices() {
    final result = List<Matrix4>.generate(
      nodeCount,
      (_) => Matrix4.identity(),
      growable: false,
    );
    final done = List<bool>.filled(nodeCount, false);
    // A malformed rig could make the hierarchy cyclic; this stops a walk
    // that would otherwise recurse until the stack gives out, the same
    // guard `gltf_loader_scene.dart`'s own node walk carries.
    final visiting = <int>{};

    void compute(int index) {
      if (done[index]) return;
      if (!visiting.add(index)) {
        // A cycle: leave this node's own local transform as its "world" so
        // the walk terminates, rather than looping forever chasing an
        // ancestor that is chasing it back.
        result[index] = localMatrix(index);
        done[index] = true;
        return;
      }

      final parent = parents[index];
      if (parent < 0 || parent >= nodeCount) {
        result[index] = localMatrix(index);
      } else {
        compute(parent);
        result[index] = result[parent].clone()..multiply(localMatrix(index));
      }
      done[index] = true;
      visiting.remove(index);
    }

    for (var i = 0; i < nodeCount; i++) {
      compute(i);
    }
    return result;
  }

  /// Joint matrices for a skin, laid out the way [Skeleton.matrices] is:
  /// `joints.length * 16` used floats followed by identity padding out to
  /// [maxJoints], so a caller comparing the two need not special-case the
  /// tail.
  ///
  /// [meshWorld] means what it means in [Skeleton.update]: the world
  /// transform of the node the skinned mesh hangs from. The formula —
  /// `inverse(meshWorld) * jointWorld * inverseBind` — is that method's own;
  /// see its doc comment for what each term undoes.
  Float32List jointMatrices({
    required List<int> joints,
    required List<Matrix4> inverseBindMatrices,
    required Matrix4 meshWorld,
    int maxJoints = Skeleton.maxJoints,
  }) {
    if (joints.length != inverseBindMatrices.length) {
      throw ArgumentError(
        '${joints.length} joints but ${inverseBindMatrices.length} inverse '
        'bind matrices.',
      );
    }
    if (joints.length > maxJoints) {
      throw ArgumentError(
        '${joints.length} joints exceed the $maxJoints this pose was asked '
        'to fill.',
      );
    }

    final world = worldMatrices();
    final inverseMeshWorld = Matrix4.copy(meshWorld)..invert();
    final out = Float32List(maxJoints * 16);

    for (var i = 0; i < joints.length; i++) {
      final nodeIndex = joints[i];
      final joint = Matrix4.copy(inverseMeshWorld);
      if (nodeIndex >= 0 && nodeIndex < nodeCount) {
        joint.multiply(world[nodeIndex]);
      }
      joint.multiply(inverseBindMatrices[i]);

      final storage = joint.storage;
      final base = i * 16;
      for (var e = 0; e < 16; e++) {
        out[base + e] = storage[e];
      }
    }

    // Past the joint count, identity — the same padding `Skeleton.matrices`
    // carries, so a shader (or a test) reading a stale slot leaves the
    // vertex alone rather than sending it to the origin.
    for (var i = joints.length; i < maxJoints; i++) {
      final base = i * 16;
      for (var e = 0; e < 16; e++) {
        out[base + e] = e % 5 == 0 ? 1.0 : 0.0;
      }
    }
    return out;
  }

  /// Writes this pose's current local TRS onto [targets], index-aligned
  /// with [parents] — `anim-14`'s own row, the bridge back from a solver
  /// that works on [Pose] alone (inverse kinematics, a mocap importer) onto
  /// whatever a renderer actually reads.
  ///
  /// A null entry in [targets] — the ordinary case for a node this caller
  /// has no [AnimationTarget] for, or has chosen not to drive — is skipped
  /// rather than refused, the same tolerance `AnimationPlayer.apply` has
  /// for a track naming a node with none.
  void writeTo(List<AnimationTarget?> targets) {
    final count = nodeCount < targets.length ? nodeCount : targets.length;
    for (var i = 0; i < count; i++) {
      final target = targets[i];
      if (target == null) continue;
      target.setPosition(
        translations[i * 3],
        translations[i * 3 + 1],
        translations[i * 3 + 2],
      );
      target.setRotation(
        Quaternion(
          rotations[i * 4],
          rotations[i * 4 + 1],
          rotations[i * 4 + 2],
          rotations[i * 4 + 3],
        ),
      );
      target.setScale(scales[i * 3], scales[i * 3 + 1], scales[i * 3 + 2]);
    }
  }

  @override
  String toString() => 'Pose($nodeCount nodes)';
}
