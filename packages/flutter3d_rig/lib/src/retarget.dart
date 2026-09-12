/// Rest-relative clip retargeting between two skeletons — `anim-17`'s own
/// `retargetClip`.
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

import 'bone_map.dart';
import 'two_bone_ik.dart';

Quaternion _rotationOf(Matrix4 local) => Quaternion.fromRotation(
  local.getRotation(),
);

/// The world-space standing height of [skeleton]'s own rig in [project]'s
/// rest pose — the highest joint (a humanoid's own `head`) above the lowest
/// (an ankle), which is what "рост" (height) means for `retargetClip`'s own
/// hip-translation scale. Falls back to the full Y span of every joint in
/// the skeleton when neither a `head` nor an `*nkle` name is present, so a
/// non-humanoid rig still gets *some* defensible height rather than a
/// division by a made-up number.
double _standingHeight(ModelProject project, ProjectSkeleton skeleton) {
  final worldY = <String, double>{};
  final worldOf = <int, Vector3>{};
  Vector3 worldPositionOf(int id) {
    final cached = worldOf[id];
    if (cached != null) return cached;
    final object = project[id];
    if (object == null) return Vector3.zero();
    final parentWorld = object.parent == null
        ? Vector3.zero()
        : worldPositionOf(object.parent!);
    final parentRot = object.parent == null
        ? Quaternion.identity()
        : _rotationOf(_worldMatrix(project, object.parent!));
    final world = parentWorld + parentRot.rotated(object.transform.getTranslation());
    worldOf[id] = world;
    return world;
  }

  for (final id in skeleton.joints) {
    final object = project[id];
    if (object == null) continue;
    worldY[object.name] = worldPositionOf(id).y;
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
  final height = values.reduce((a, b) => a > b ? a : b) -
      values.reduce((a, b) => a < b ? a : b);
  return height > 1e-6 ? height : 1.0;
}

/// [id]'s own world transform in [project], composed by walking its
/// ancestors — used only where a caller needs the *rotation* half; the
/// simpler [_standingHeight]'s own accumulation above handles translation
/// itself so as not to build a full `Matrix4` per joint per call there.
Matrix4 _worldMatrix(ModelProject project, int id) {
  final object = project[id];
  if (object == null) return Matrix4.identity();
  if (object.parent == null) return object.transform.clone();
  return _worldMatrix(project, object.parent!) * object.transform;
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

/// Retargets [sourceClip] — a clip whose tracks address [sourceSkeleton]'s
/// own joints in [sourceProject] — onto [targetSkeleton]'s joints in
/// [targetProject], through [boneMap].
///
/// **Rest-relative, not a raw copy.** Each rotation keyframe is expressed
/// relative to the *source* bone's own rest rotation, then re-applied on
/// top of the *target* bone's own rest rotation — the standard technique
/// that keeps a retarget correct across two skeletons whose rest poses
/// (a T-pose here, an A-pose there) or bone lengths differ. Translation
/// keyframes (ordinarily only the root/hips track carries one) are instead
/// re-based on the target's own rest translation and scaled by the ratio
/// of the two skeletons' own standing heights, so a root-motion clip
/// retargeted onto a taller rig covers proportionally more ground. A track
/// whose source bone [boneMap] does not answer for is dropped rather than
/// guessed at.
///
/// **Retargeting a skeleton onto itself is the identity.** When
/// [sourceSkeleton] and [targetSkeleton] are the same rig ([boneMap] the
/// identity on every name), every rest rotation/translation above is the
/// bone's own, the height ratio is exactly `1.0`, and "relative to rest,
/// then re-applied on top of rest" composes back to the original value bit
/// for bit — `anim-17`'s own first acceptance clause.
///
/// [lockFeet] runs a two-bone IK correction (`solveTwoBoneIk`) after
/// retargeting, per humanoid leg (`leftHip`/`leftKnee`/`leftAnkle` and the
/// right-side mirror), snapping each foot back to [groundY] at every
/// keyframe the retargeted hip or knee track carries — the row's own
/// "прижим стоп" (foot clamp), needed because scaling only the root
/// translation by a height ratio does not, by itself, guarantee a leg of a
/// different proportion still reaches the ground exactly.
ProjectClip retargetClip({
  required ProjectClip sourceClip,
  required ModelProject sourceProject,
  required ProjectSkeleton sourceSkeleton,
  required ModelProject targetProject,
  required ProjectSkeleton targetSkeleton,
  required BoneMap boneMap,
  bool lockFeet = true,
  double groundY = 0.0,
  double footTolerance = 1e-3,
}) {
  final heightRatio =
      _standingHeight(targetProject, targetSkeleton) /
      _standingHeight(sourceProject, sourceSkeleton);

  final targetJointByName = <String, ModelObject>{};
  for (final id in targetSkeleton.joints) {
    final object = targetProject[id];
    if (object != null) targetJointByName[object.name] = object;
  }

  final newTracks = <ProjectTrack>[];
  for (final track in sourceClip.tracks) {
    final sourceObject = sourceProject[track.objectId];
    if (sourceObject == null) continue;
    final targetName = boneMap.targetOf(sourceObject.name);
    if (targetName == null) continue;
    final targetObject = targetJointByName[targetName];
    if (targetObject == null) continue;

    final retargeted = _retargetTrack(
      track.track,
      sourceRestLocal: sourceObject.transform,
      targetRestLocal: targetObject.transform,
      heightRatio: heightRatio,
    );
    if (retargeted == null) continue;
    newTracks.add(ProjectTrack(objectId: targetObject.id, track: retargeted));
  }

  var clip = ProjectClip(
    name: sourceClip.name,
    tracks: newTracks,
    extras: sourceClip.extras,
  );

  if (lockFeet) {
    clip = _lockFeet(
      clip,
      targetProject: targetProject,
      targetSkeleton: targetSkeleton,
      groundY: groundY,
      tolerance: footTolerance,
    );
  }

  return clip;
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
      // Passed through unchanged: this row's own acceptance names rotation
      // (rest-relative) and translation (height-scaled) only.
      return AnimationTrack(
        nodeIndex: track.nodeIndex,
        path: track.path,
        interpolation: track.interpolation,
        times: track.times,
        values: Float32List.fromList(track.values),
        componentCount: track.componentCount,
      );
  }
}

ProjectClip _lockFeet(
  ProjectClip clip, {
  required ModelProject targetProject,
  required ProjectSkeleton targetSkeleton,
  required double groundY,
  required double tolerance,
}) {
  final jointByName = <String, ModelObject>{};
  for (final id in targetSkeleton.joints) {
    final object = targetProject[id];
    if (object != null) jointByName[object.name] = object;
  }
  final tracksByObjectId = <int, ProjectTrack>{
    for (final track in clip.tracks) track.objectId: track,
  };

  final replaced = Map<int, AnimationTrack>.fromEntries(
    tracksByObjectId.entries.map((e) => MapEntry(e.key, e.value.track)),
  );

  final newTrackObjectIds = <int>{};

  for (final chain in _legChains) {
    final hip = jointByName[chain.hip];
    final knee = jointByName[chain.knee];
    final ankle = jointByName[chain.ankle];
    if (hip == null || knee == null || ankle == null) continue;

    // `hips`, the shared root both legs hang from — its own retargeted
    // rotation and translation tracks, when present, since the leg chain's
    // own FK starts from wherever the pelvis actually is at this keyframe,
    // not from its rest pose.
    final rootObject = hip.parent == null ? null : targetProject[hip.parent!];
    final rootTrack = rootObject == null
        ? null
        : tracksByObjectId[rootObject.id]?.track;

    final hipTrack = tracksByObjectId[hip.id]?.track;
    final kneeTrack = tracksByObjectId[knee.id]?.track;

    // Every bone in this rig is a pure translation at rest (`rig_template
    // .dart`'s own doc comment), so a bone with no rotation track at all is
    // simply at rest — identity, not "nothing to correct". Picking a
    // timeline from whichever of hip/knee/root actually carries one (in
    // that order) is what lets a clip that only ever animates the root
    // translation — a crouch with the legs otherwise held straight, this
    // row's own acceptance case — still get its foot corrected.
    final times =
        hipTrack?.times ?? kneeTrack?.times ?? rootTrack?.times;
    if (times == null) continue;

    Float32List identityRotations() {
      final values = Float32List(times.length * 4);
      for (var i = 0; i < times.length; i++) {
        values[i * 4 + 3] = 1.0;
      }
      return values;
    }

    final hipValues = Float32List.fromList(
      replaced[hip.id]?.values ?? hipTrack?.values ?? identityRotations(),
    );
    final kneeValues = Float32List.fromList(
      replaced[knee.id]?.values ?? kneeTrack?.values ?? identityRotations(),
    );

    final rootRestT = rootObject?.transform.getTranslation() ?? Vector3.zero();
    final rootRestR = rootObject == null
        ? Quaternion.identity()
        : _rotationOf(rootObject.transform);
    final hipOffset = hip.transform.getTranslation();
    final kneeOffset = knee.transform.getTranslation();
    final ankleOffset = ankle.transform.getTranslation();

    final rootTranslationValues = rootTrack != null &&
            rootTrack.path == AnimationPath.translation
        ? (replaced[rootObject!.id]?.values ?? rootTrack.values)
        : null;
    final rootRotationValues =
        rootTrack != null && rootTrack.path == AnimationPath.rotation
        ? (replaced[rootObject!.id]?.values ?? rootTrack.values)
        : null;

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

      final target = Vector3(ankleWorldPos.x, groundY, ankleWorldPos.z);
      final pole = kneeWorldPos + Vector3(0.0, 0.0, 1.0);
      final result = solveTwoBoneIk(
        rootWorldPosition: hipWorldPos,
        midWorldPosition: kneeWorldPos,
        tipWorldPosition: ankleWorldPos,
        rootParentWorldRotation: rootWorldR,
        rootWorldRotation: hipWorldR,
        midWorldRotation: kneeWorldR,
        target: target,
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

    replaced[hip.id] = AnimationTrack(
      nodeIndex: hipTrack?.nodeIndex ?? 0,
      path: AnimationPath.rotation,
      interpolation: hipTrack?.interpolation ?? AnimationInterpolation.linear,
      times: times,
      values: hipValues,
      componentCount: 4,
    );
    if (hipTrack == null) newTrackObjectIds.add(hip.id);
    replaced[knee.id] = AnimationTrack(
      nodeIndex: kneeTrack?.nodeIndex ?? 0,
      path: AnimationPath.rotation,
      interpolation:
          kneeTrack?.interpolation ?? AnimationInterpolation.linear,
      times: times,
      values: kneeValues,
      componentCount: 4,
    );
    if (kneeTrack == null) newTrackObjectIds.add(knee.id);
  }

  return ProjectClip(
    name: clip.name,
    tracks: [
      for (final track in clip.tracks)
        ProjectTrack(
          objectId: track.objectId,
          track: replaced[track.objectId] ?? track.track,
        ),
      for (final objectId in newTrackObjectIds)
        ProjectTrack(objectId: objectId, track: replaced[objectId]!),
    ],
    extras: clip.extras,
  );
}
