/// Rest-relative retargeting of animation tracks between two rigs —
/// `anim-17`'s own `retargetClip`, over the rig as nodes and tracks.
///
/// **Nothing here knows what a project is.** A rig is read as [RigNode]s — a
/// name, a parent and a rest pose — and a clip as [RigTrack]s naming the node
/// each one moves. That is the whole of what retargeting needs, and it is what
/// lets anything with a skeleton call this: the modeller's own document adapts
/// to it in `flutter3d_model_core`'s `retargetClip`, and an engine or a game
/// holding a glTF skin builds the same two values without depending on a
/// modeller. The algorithm package depends on the vocabulary of animation;
/// the document depends on the algorithm.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

import 'bone_map.dart';
import 'two_bone_ik.dart';

/// One node of a rig as retargeting reads it.
final class RigNode {
  const RigNode({
    required this.id,
    required this.name,
    required this.restLocal,
    this.parent,
  });

  /// What [RigTrack.nodeId] and [RigNode.parent] name it by.
  final int id;

  /// What a [BoneMap] matches it by.
  final String name;

  /// The rest pose, relative to [parent].
  final Matrix4 restLocal;

  final int? parent;
}

/// A skeleton as retargeting reads it: every node a joint hangs from, and
/// which of them are the joints.
///
/// **More nodes than joints, on purpose.** A leg's world position starts at
/// whatever the hips hang from, and that is often not a joint at all — an
/// armature root, an empty the whole rig is parented to. Retargeting walks
/// those parents for heights and for the foot lock, so a rig carries them.
final class RetargetRig {
  RetargetRig({required Iterable<RigNode> nodes, required List<int> joints})
    : _nodes = <int, RigNode>{for (final RigNode node in nodes) node.id: node},
      joints = List<int>.unmodifiable(joints);

  final Map<int, RigNode> _nodes;

  /// The ids of the nodes that are joints, in the skeleton's own order.
  final List<int> joints;

  /// The node with [id], or null when the rig does not carry it.
  RigNode? operator [](int id) => _nodes[id];
}

/// A track and the node it moves.
final class RigTrack {
  const RigTrack({required this.nodeId, required this.track});

  final int nodeId;

  final AnimationTrack track;
}

Quaternion _rotationOf(Matrix4 local) =>
    Quaternion.fromRotation(local.getRotation());

/// The world-space standing height of [rig] in its rest pose — the highest
/// joint (a humanoid's own `head`) above the lowest (an ankle), which is what
/// "рост" (height) means for [retargetTracks]' own hip-translation scale.
/// Falls back to the full Y span of every joint when neither a `head` nor an
/// `*nkle` name is present, so a non-humanoid rig still gets *some*
/// defensible height rather than a division by a made-up number.
double _standingHeight(RetargetRig rig) {
  final worldY = <String, double>{};
  final worldOf = <int, Vector3>{};
  Vector3 worldPositionOf(int id) {
    final cached = worldOf[id];
    if (cached != null) return cached;
    final node = rig[id];
    if (node == null) return Vector3.zero();
    final parentWorld = node.parent == null
        ? Vector3.zero()
        : worldPositionOf(node.parent!);
    final parentRot = node.parent == null
        ? Quaternion.identity()
        : _rotationOf(_worldMatrix(rig, node.parent!));
    final world =
        parentWorld + parentRot.rotated(node.restLocal.getTranslation());
    worldOf[id] = world;
    return world;
  }

  for (final id in rig.joints) {
    final node = rig[id];
    if (node == null) continue;
    worldY[node.name] = worldPositionOf(id).y;
  }
  if (worldY.isEmpty) return 1.0;

  final head = worldY['head'];
  final ankles = worldY.entries
      .where((e) => e.key.toLowerCase().contains('ankle'))
      .map((e) => e.value);
  if (head != null && ankles.isNotEmpty) {
    final lowestAnkle = ankles.reduce((a, b) => a < b ? a : b);
    final height = head - lowestAnkle;
    if (height > 1e-6) return height;
  }

  final values = worldY.values;
  final height =
      values.reduce((a, b) => a > b ? a : b) -
      values.reduce((a, b) => a < b ? a : b);
  return height > 1e-6 ? height : 1.0;
}

/// [id]'s own world transform in [rig], composed by walking its ancestors —
/// used only where a caller needs the *rotation* half; [_standingHeight]'s own
/// accumulation above handles translation itself so as not to build a full
/// `Matrix4` per joint per call there.
Matrix4 _worldMatrix(RetargetRig rig, int id) {
  final node = rig[id];
  if (node == null) return Matrix4.identity();
  if (node.parent == null) return node.restLocal.clone();
  return _worldMatrix(rig, node.parent!) * node.restLocal;
}

/// One leg's own three joint names, humanoid convention — see
/// [humanoidBoneNames].
class _LegChain {
  const _LegChain(this.hip, this.knee, this.ankle);
  final String hip;
  final String knee;
  final String ankle;
}

const _legChains = <_LegChain>[
  _LegChain('leftHip', 'leftKnee', 'leftAnkle'),
  _LegChain('rightHip', 'rightKnee', 'rightAnkle'),
];

/// Retargets [tracks] — tracks moving [source]'s own nodes — onto [target]'s
/// joints, through [boneMap].
///
/// **Rest-relative, not a raw copy.** Each rotation keyframe is expressed
/// relative to the *source* bone's own rest rotation, then re-applied on top
/// of the *target* bone's own rest rotation — the standard technique that
/// keeps a retarget correct across two skeletons whose rest poses (a T-pose
/// here, an A-pose there) or bone lengths differ. Translation keyframes
/// (ordinarily only the root/hips track carries one) are instead re-based on
/// the target's own rest translation and scaled by the ratio of the two rigs'
/// own standing heights, so a root-motion clip retargeted onto a taller rig
/// covers proportionally more ground. A track whose source node [boneMap]
/// does not answer for is dropped rather than guessed at.
///
/// **Retargeting a rig onto itself is the identity.** When [source] and
/// [target] are the same rig ([boneMap] the identity on every name), every
/// rest rotation/translation above is the bone's own, the height ratio is
/// exactly `1.0`, and "relative to rest, then re-applied on top of rest"
/// composes back to the original value bit for bit — `anim-17`'s own first
/// acceptance clause.
///
/// [lockFeet] runs a two-bone IK correction (`solveTwoBoneIk`) after
/// retargeting, per humanoid leg (`leftHip`/`leftKnee`/`leftAnkle` and the
/// right-side mirror), snapping each foot back to [groundY] at every keyframe
/// the retargeted hip or knee track carries — the row's own "прижим стоп"
/// (foot clamp), needed because scaling only the root translation by a height
/// ratio does not, by itself, guarantee a leg of a different proportion still
/// reaches the ground exactly.
List<RigTrack> retargetTracks({
  required List<RigTrack> tracks,
  required RetargetRig source,
  required RetargetRig target,
  required BoneMap boneMap,
  bool lockFeet = true,
  double groundY = 0.0,
  double footTolerance = 1e-3,
}) {
  final heightRatio = _standingHeight(target) / _standingHeight(source);

  final targetJointByName = <String, RigNode>{
    for (final id in target.joints)
      if (target[id] case final RigNode node) node.name: node,
  };

  final retargeted = <RigTrack>[
    for (final track in tracks)
      if (_retargetOne(
            track,
            source: source,
            targetJointByName: targetJointByName,
            boneMap: boneMap,
            heightRatio: heightRatio,
          )
          case final RigTrack moved)
        moved,
  ];

  return lockFeet
      ? _lockFeet(
          retargeted,
          target: target,
          groundY: groundY,
          tolerance: footTolerance,
        )
      : retargeted;
}

/// [track] moved onto the target joint [boneMap] names for its source node, or
/// null when there is no such node, no such name or no such joint.
RigTrack? _retargetOne(
  RigTrack track, {
  required RetargetRig source,
  required Map<String, RigNode> targetJointByName,
  required BoneMap boneMap,
  required double heightRatio,
}) {
  final sourceNode = source[track.nodeId];
  if (sourceNode == null) return null;
  final targetName = boneMap.targetOf(sourceNode.name);
  if (targetName == null) return null;
  final targetNode = targetJointByName[targetName];
  if (targetNode == null) return null;
  final moved = _retargetTrack(
    track.track,
    sourceRestLocal: sourceNode.restLocal,
    targetRestLocal: targetNode.restLocal,
    heightRatio: heightRatio,
  );
  return moved == null ? null : RigTrack(nodeId: targetNode.id, track: moved);
}

AnimationTrack? _retargetTrack(
  AnimationTrack track, {
  required Matrix4 sourceRestLocal,
  required Matrix4 targetRestLocal,
  required double heightRatio,
}) {
  switch (track.path) {
    case AnimationPath.rotation:
      final sourceRestRot = _rotationOf(sourceRestLocal);
      final targetRestRot = _rotationOf(targetRestLocal);
      final values = Float32List.fromList(track.values);
      final valuesPerKey = track.interpolation.valuesPerKey;
      for (var key = 0; key < track.times.length; key++) {
        for (var sample = 0; sample < valuesPerKey; sample++) {
          final base = (key * valuesPerKey + sample) * 4;
          final animated = Quaternion(
            values[base],
            values[base + 1],
            values[base + 2],
            values[base + 3],
          );
          final relative = (sourceRestRot.inverted() * animated)..normalize();
          final result = (targetRestRot * relative)..normalize();
          values[base] = result.x;
          values[base + 1] = result.y;
          values[base + 2] = result.z;
          values[base + 3] = result.w;
        }
      }
      return AnimationTrack(
        nodeIndex: track.nodeIndex,
        path: track.path,
        interpolation: track.interpolation,
        times: track.times,
        values: values,
        componentCount: track.componentCount,
      );

    case AnimationPath.translation:
      final sourceRestT = sourceRestLocal.getTranslation();
      final targetRestT = targetRestLocal.getTranslation();
      final values = Float32List.fromList(track.values);
      final valuesPerKey = track.interpolation.valuesPerKey;
      for (var key = 0; key < track.times.length; key++) {
        for (var sample = 0; sample < valuesPerKey; sample++) {
          final base = (key * valuesPerKey + sample) * 3;
          final animated = Vector3(
            values[base],
            values[base + 1],
            values[base + 2],
          );
          final delta = (animated - sourceRestT) * heightRatio;
          final result = targetRestT + delta;
          values[base] = result.x;
          values[base + 1] = result.y;
          values[base + 2] = result.z;
        }
      }
      return AnimationTrack(
        nodeIndex: track.nodeIndex,
        path: track.path,
        interpolation: track.interpolation,
        times: track.times,
        values: values,
        componentCount: track.componentCount,
      );

    case AnimationPath.scale:
    case AnimationPath.weights:
    case AnimationPath.pointer:
      // Passed through unchanged: this row's own acceptance names rotation
      // (rest-relative) and translation (height-scaled) only.
      return AnimationTrack(
        nodeIndex: track.nodeIndex,
        path: track.path,
        interpolation: track.interpolation,
        times: track.times,
        values: Float32List.fromList(track.values),
        componentCount: track.componentCount,
        pointer: track.pointer,
      );
  }
}

List<RigTrack> _lockFeet(
  List<RigTrack> tracks, {
  required RetargetRig target,
  required double groundY,
  required double tolerance,
}) {
  final jointByName = <String, RigNode>{
    for (final id in target.joints)
      if (target[id] case final RigNode node) node.name: node,
  };

  // Keyed by (node, path) rather than node alone — a joint routinely carries
  // translation, rotation *and* scale tracks at once (`RiggedFigure.glb`'s
  // own clip animates every joint that way, not only the root's), and a
  // plain `Map<int, RigTrack>` here used to keep only the last of a joint's
  // tracks built, silently dropping the others (tut-12).
  final tracksByNodeId = <int, Map<AnimationPath, RigTrack>>{};
  for (final track in tracks) {
    (tracksByNodeId[track.nodeId] ??=
            <AnimationPath, RigTrack>{})[track.track.path] =
        track;
  }

  final replaced = <(int, AnimationPath), AnimationTrack>{
    for (final track in tracks) (track.nodeId, track.track.path): track.track,
  };

  final newTrackKeys = <(int, AnimationPath)>{};

  for (final chain in _legChains) {
    final hip = jointByName[chain.hip];
    final knee = jointByName[chain.knee];
    final ankle = jointByName[chain.ankle];
    if (hip == null || knee == null || ankle == null) continue;

    // `hips`, the shared root both legs hang from — its own retargeted
    // rotation and translation tracks, when present, since the leg chain's
    // own FK starts from wherever the pelvis actually is at this keyframe,
    // not from its rest pose. Read by path explicitly rather than through a
    // single collapsed track: the root may carry both at once (and a scale
    // track besides), and each is read separately below.
    final rootNode = hip.parent == null ? null : target[hip.parent!];
    final rootTranslationTrack = rootNode == null
        ? null
        : tracksByNodeId[rootNode.id]?[AnimationPath.translation];
    final rootRotationTrack = rootNode == null
        ? null
        : tracksByNodeId[rootNode.id]?[AnimationPath.rotation];

    // Explicitly the *rotation* track for each — a joint carrying
    // translation/rotation/scale all at once (tut-12's own reproduction)
    // must not have one silently stand in for another.
    final hipTrack = tracksByNodeId[hip.id]?[AnimationPath.rotation];
    final kneeTrack = tracksByNodeId[knee.id]?[AnimationPath.rotation];

    // Every bone in this rig is a pure translation at rest (`rig_template
    // .dart`'s own doc comment), so a bone with no rotation track at all is
    // simply at rest — identity, not "nothing to correct". Picking a
    // timeline from whichever of hip/knee/root actually carries one (in
    // that order) is what lets a clip that only ever animates the root
    // translation — a crouch with the legs otherwise held straight, this
    // row's own acceptance case — still get its foot corrected.
    final times =
        hipTrack?.track.times ??
        kneeTrack?.track.times ??
        rootRotationTrack?.track.times ??
        rootTranslationTrack?.track.times;
    if (times == null) continue;

    Float32List identityRotations() {
      final values = Float32List(times.length * 4);
      for (var i = 0; i < times.length; i++) {
        values[i * 4 + 3] = 1.0;
      }
      return values;
    }

    final hipValues = Float32List.fromList(
      replaced[(hip.id, AnimationPath.rotation)]?.values ??
          hipTrack?.track.values ??
          identityRotations(),
    );
    final kneeValues = Float32List.fromList(
      replaced[(knee.id, AnimationPath.rotation)]?.values ??
          kneeTrack?.track.values ??
          identityRotations(),
    );

    final rootRestT = rootNode?.restLocal.getTranslation() ?? Vector3.zero();
    final rootRestR = rootNode == null
        ? Quaternion.identity()
        : _rotationOf(rootNode.restLocal);
    final hipOffset = hip.restLocal.getTranslation();
    final kneeOffset = knee.restLocal.getTranslation();
    final ankleOffset = ankle.restLocal.getTranslation();

    final rootTranslationValues = rootNode == null
        ? null
        : (replaced[(rootNode.id, AnimationPath.translation)]?.values ??
              rootTranslationTrack?.track.values);
    final rootRotationValues = rootNode == null
        ? null
        : (replaced[(rootNode.id, AnimationPath.rotation)]?.values ??
              rootRotationTrack?.track.values);

    for (var key = 0; key < times.length; key++) {
      final hipLocalRot = Quaternion(
        hipValues[key * 4],
        hipValues[key * 4 + 1],
        hipValues[key * 4 + 2],
        hipValues[key * 4 + 3],
      );
      final kneeLocalRot = Quaternion(
        kneeValues[key * 4],
        kneeValues[key * 4 + 1],
        kneeValues[key * 4 + 2],
        kneeValues[key * 4 + 3],
      );

      final rootWorldT = rootTranslationValues == null
          ? rootRestT
          : Vector3(
              rootTranslationValues[key * 3],
              rootTranslationValues[key * 3 + 1],
              rootTranslationValues[key * 3 + 2],
            );
      final rootWorldR = rootRotationValues == null
          ? rootRestR
          : Quaternion(
              rootRotationValues[key * 4],
              rootRotationValues[key * 4 + 1],
              rootRotationValues[key * 4 + 2],
              rootRotationValues[key * 4 + 3],
            );

      // Composition order: `local * parent`, not `parent * local` — see
      // `two_bone_ik.dart`'s own note on how this build of `vector_math`
      // actually composes `A * B` (`A` first, `B` second).
      final hipWorldR = (hipLocalRot * rootWorldR)..normalize();
      final hipWorldPos = rootWorldT + rootWorldR.rotated(hipOffset);
      final kneeWorldR = (kneeLocalRot * hipWorldR)..normalize();
      final kneeWorldPos = hipWorldPos + hipWorldR.rotated(kneeOffset);
      final ankleWorldPos = kneeWorldPos + kneeWorldR.rotated(ankleOffset);

      if ((ankleWorldPos.y - groundY).abs() <= tolerance) continue;

      final goal = Vector3(ankleWorldPos.x, groundY, ankleWorldPos.z);
      final pole = kneeWorldPos + Vector3(0.0, 0.0, 1.0);
      final result = solveTwoBoneIk(
        rootWorldPosition: hipWorldPos,
        midWorldPosition: kneeWorldPos,
        tipWorldPosition: ankleWorldPos,
        rootParentWorldRotation: rootWorldR,
        rootWorldRotation: hipWorldR,
        midWorldRotation: kneeWorldR,
        target: goal,
        pole: pole,
      );

      hipValues[key * 4] = result.rootLocalRotation.x;
      hipValues[key * 4 + 1] = result.rootLocalRotation.y;
      hipValues[key * 4 + 2] = result.rootLocalRotation.z;
      hipValues[key * 4 + 3] = result.rootLocalRotation.w;
      kneeValues[key * 4] = result.midLocalRotation.x;
      kneeValues[key * 4 + 1] = result.midLocalRotation.y;
      kneeValues[key * 4 + 2] = result.midLocalRotation.z;
      kneeValues[key * 4 + 3] = result.midLocalRotation.w;
    }

    replaced[(hip.id, AnimationPath.rotation)] = AnimationTrack(
      nodeIndex: hipTrack?.track.nodeIndex ?? 0,
      path: AnimationPath.rotation,
      interpolation:
          hipTrack?.track.interpolation ?? AnimationInterpolation.linear,
      times: times,
      values: hipValues,
      componentCount: 4,
    );
    if (hipTrack == null) newTrackKeys.add((hip.id, AnimationPath.rotation));
    replaced[(knee.id, AnimationPath.rotation)] = AnimationTrack(
      nodeIndex: kneeTrack?.track.nodeIndex ?? 0,
      path: AnimationPath.rotation,
      interpolation:
          kneeTrack?.track.interpolation ?? AnimationInterpolation.linear,
      times: times,
      values: kneeValues,
      componentCount: 4,
    );
    if (kneeTrack == null) newTrackKeys.add((knee.id, AnimationPath.rotation));
  }

  return <RigTrack>[
    for (final track in tracks)
      RigTrack(
        nodeId: track.nodeId,
        track: replaced[(track.nodeId, track.track.path)] ?? track.track,
      ),
    for (final key in newTrackKeys)
      RigTrack(nodeId: key.$1, track: replaced[key]!),
  ];
}
