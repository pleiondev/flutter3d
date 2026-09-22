/// `anim-17`'s own acceptance: same skeleton is an identity; a height-x2
/// retarget keeps the foot within 1cm of the ground once `lockFeet` runs.
///
///     dart test test/retarget_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final _bounds = Aabb3.minMax(Vector3(-3, -2, -3), Vector3(3, 5, 3));

/// A humanoid rig standing on `y = 0`, built from a hand-picked marker set.
/// [scale] multiplies every marker uniformly except that the leg (hip→knee→
/// ankle) is instead scaled by [legScale] — the two differ in the "height
/// x2" test below so a naive height-ratio-only retarget leaves the target's
/// own leg unable to reach the ground on its own, which is exactly the case
/// `lockFeet` exists for.
({List<ModelObject> objects, ProjectSkeleton skeleton, Map<String, int> idOf})
_buildHumanoid({double scale = 1.0, double? legScale}) {
  final leg = legScale ?? scale;
  final markers = <String, Vector3>{
    'hips': Vector3(0, 1.0 * leg, 0),
    'spine': Vector3(0, 1.0 * leg + 0.2 * scale, 0),
    'chest': Vector3(0, 1.0 * leg + 0.4 * scale, 0),
    'neck': Vector3(0, 1.0 * leg + 0.6 * scale, 0),
    'head': Vector3(0, 1.0 * leg + 0.7 * scale, 0),
    'leftShoulder': Vector3(-0.2 * scale, 1.0 * leg + 0.4 * scale, 0),
    'leftElbow': Vector3(-0.2 * scale, 1.0 * leg + 0.1 * scale, 0),
    'leftWrist': Vector3(-0.2 * scale, 1.0 * leg - 0.2 * scale, 0),
    'leftHip': Vector3(-0.1 * leg, 1.0 * leg, 0),
    'leftKnee': Vector3(-0.1 * leg, 0.5 * leg, 0.05 * leg),
    'leftAnkle': Vector3(-0.1 * leg, 0.0, 0),
  };
  final built = buildSkeleton(
    RigTemplate.humanoid,
    markers,
    bounds: _bounds,
    firstObjectId: 1,
  );
  final idOf = <String, int>{
    for (final object in built.objects) object.name: object.id,
  };
  return (objects: built.objects, skeleton: built.skeleton, idOf: idOf);
}

ModelProject _projectOf(
  ({List<ModelObject> objects, ProjectSkeleton skeleton, Map<String, int> idOf})
  rig,
) => ModelProject(objects: rig.objects, skeletons: [rig.skeleton]);

AnimationTrack _rotationTrack(int nodeIndex, Quaternion value) =>
    AnimationTrack(
      nodeIndex: nodeIndex,
      path: AnimationPath.rotation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList([0.0]),
      values: Float32List.fromList([value.x, value.y, value.z, value.w]),
      componentCount: 4,
    );

AnimationTrack _translationTrack(int nodeIndex, Vector3 value) =>
    AnimationTrack(
      nodeIndex: nodeIndex,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList([0.0]),
      values: Float32List.fromList([value.x, value.y, value.z]),
      componentCount: 3,
    );

AnimationTrack _scaleTrack(int nodeIndex, Vector3 value) => AnimationTrack(
  nodeIndex: nodeIndex,
  path: AnimationPath.scale,
  interpolation: AnimationInterpolation.linear,
  times: Float32List.fromList([0.0]),
  values: Float32List.fromList([value.x, value.y, value.z]),
  componentCount: 3,
);

void main() {
  group('anim-17\'s own acceptance', () {
    test('the same skeleton — identity', () {
      final rig = _buildHumanoid();
      final project = _projectOf(rig);

      final elbowRot = Quaternion.axisAngle(Vector3(1, 0, 0), 0.7)..normalize();
      final hipsPos = Vector3(0.05, 1.02, -0.01);

      final clip = ProjectClip(
        name: 'pose',
        tracks: [
          ProjectTrack(
            objectId: rig.idOf['leftElbow']!,
            track: _rotationTrack(0, elbowRot),
          ),
          ProjectTrack(
            objectId: rig.idOf['hips']!,
            track: _translationTrack(0, hipsPos),
          ),
        ],
      );

      final names = rig.objects.map((o) => o.name).toList();
      final boneMap = autoMap(names, names);
      expect(boneMap.length, humanoidBoneNames.length);

      final retargeted = retargetClip(
        sourceClip: clip,
        sourceProject: project,
        sourceSkeleton: rig.skeleton,
        targetProject: project,
        targetSkeleton: rig.skeleton,
        boneMap: boneMap,
        lockFeet: false, // rest pose is already grounded; isolate the math.
      );

      final elbowOut = retargeted.tracks.firstWhere(
        (t) => t.objectId == rig.idOf['leftElbow'],
      );
      expect(elbowOut.track.values[0], closeTo(elbowRot.x, 1e-6));
      expect(elbowOut.track.values[1], closeTo(elbowRot.y, 1e-6));
      expect(elbowOut.track.values[2], closeTo(elbowRot.z, 1e-6));
      expect(elbowOut.track.values[3], closeTo(elbowRot.w, 1e-6));

      final hipsOut = retargeted.tracks.firstWhere(
        (t) => t.objectId == rig.idOf['hips'],
      );
      expect(hipsOut.track.values[0], closeTo(hipsPos.x, 1e-6));
      expect(hipsOut.track.values[1], closeTo(hipsPos.y, 1e-6));
      expect(hipsOut.track.values[2], closeTo(hipsPos.z, 1e-6));
    });

    test('height x2, mismatched leg proportion — the foot lands within 1cm '
        'of the ground once lockFeet runs', () {
      final source = _buildHumanoid(scale: 1.0);
      // Standing height doubles exactly (head - lowest ankle: 1.7 -> 3.4:
      // legScale 1.8 for the leg, and scale solved so the upper-body span
      // makes up the rest of 3.4), but the leg alone only grows 1.8x, not
      // 2x — a target skeleton whose proportions are NOT a uniform scale
      // of the source's, the case a naive height-ratio-only translation
      // retarget does not handle by itself.
      final target = _buildHumanoid(scale: (3.4 - 1.8) / 0.7, legScale: 1.8);
      final sourceProject = _projectOf(source);
      final targetProject = _projectOf(target);

      // A crouch: the hip drops 0.1m below its own rest height with the
      // leg held unrotated (rest) — always within the leg's own reach
      // (crouching only ever needs less extension than standing fully
      // straight), unlike a "hop" that lifts the hip past what a straight
      // leg can even reach.
      final restHips = source.objects
          .firstWhere((o) => o.name == 'hips')
          .transform
          .getTranslation();
      final crouchHips = restHips - Vector3(0, 0.1, 0);

      final clip = ProjectClip(
        name: 'crouch',
        tracks: [
          ProjectTrack(
            objectId: source.idOf['hips']!,
            track: _translationTrack(0, crouchHips),
          ),
        ],
      );

      final sourceNames = source.objects.map((o) => o.name).toList();
      final targetNames = target.objects.map((o) => o.name).toList();
      final boneMap = autoMap(sourceNames, targetNames);

      final withoutLock = retargetClip(
        sourceClip: clip,
        sourceProject: sourceProject,
        sourceSkeleton: source.skeleton,
        targetProject: targetProject,
        targetSkeleton: target.skeleton,
        boneMap: boneMap,
        lockFeet: false,
      );
      final withLock = retargetClip(
        sourceClip: clip,
        sourceProject: sourceProject,
        sourceSkeleton: source.skeleton,
        targetProject: targetProject,
        targetSkeleton: target.skeleton,
        boneMap: boneMap,
      );

      double ankleY(ProjectClip retargeted) {
        final hipRest = target.objects
            .firstWhere((o) => o.name == 'leftHip')
            .transform;
        final kneeRest = target.objects
            .firstWhere((o) => o.name == 'leftKnee')
            .transform;
        final ankleRest = target.objects
            .firstWhere((o) => o.name == 'leftAnkle')
            .transform;

        Quaternion rotOf(int objectId, Quaternion fallback) {
          for (final t in retargeted.tracks) {
            if (t.objectId == objectId &&
                t.track.path == AnimationPath.rotation) {
              final v = t.track.values;
              return Quaternion(v[0], v[1], v[2], v[3]);
            }
          }
          return fallback;
        }

        Vector3 hipsWorld() {
          for (final t in retargeted.tracks) {
            if (t.objectId == target.idOf['hips'] &&
                t.track.path == AnimationPath.translation) {
              final v = t.track.values;
              return Vector3(v[0], v[1], v[2]);
            }
          }
          return target.objects
              .firstWhere((o) => o.name == 'hips')
              .transform
              .getTranslation();
        }

        final hipRot = rotOf(target.idOf['leftHip']!, Quaternion.identity());
        final kneeRot = rotOf(target.idOf['leftKnee']!, Quaternion.identity());

        final hipWorldPos =
            hipsWorld() +
            Quaternion.identity().rotated(hipRest.getTranslation());
        final hipWorldRot = hipRot;
        final kneeWorldPos =
            hipWorldPos + hipWorldRot.rotated(kneeRest.getTranslation());
        final kneeWorldRot = (kneeRot * hipWorldRot)..normalize();
        final ankleWorldPos =
            kneeWorldPos + kneeWorldRot.rotated(ankleRest.getTranslation());
        return ankleWorldPos.y;
      }

      // Without correction, the target's own straight leg (1.8m reach)
      // cannot make up for a hip translated by the full height-scaled
      // delta — the foot is left measurably off the ground.
      expect((ankleY(withoutLock) - 0.0).abs(), greaterThan(0.02));

      // `lockFeet` (the default) pulls it back within the row's own 1cm.
      expect((ankleY(withLock) - 0.0).abs(), lessThan(0.01));
    });

    test('tut-12: a joint carrying translation, rotation AND scale at once '
        "does not throw, and lockFeet still corrects the foot — "
        "RiggedFigure.glb's own clip animates every joint that way, not "
        "only the root's, and used to collapse onto whichever of the "
        "hip's own three retargeted tracks was built last", () {
      final source = _buildHumanoid(scale: 1.0);
      final target = _buildHumanoid(scale: (3.4 - 1.8) / 0.7, legScale: 1.8);
      final sourceProject = _projectOf(source);
      final targetProject = _projectOf(target);

      final restHips = source.objects
          .firstWhere((o) => o.name == 'hips')
          .transform
          .getTranslation();
      final crouchHips = restHips - Vector3(0, 0.1, 0);
      final hipTilt = Quaternion.axisAngle(Vector3(1, 0, 0), 0.05)..normalize();

      final clip = ProjectClip(
        name: 'crouch-with-scale',
        tracks: [
          // Translation, rotation and scale on the very same joint — the
          // exact shape that used to make `_lockFeet`'s own
          // `Map<int, RigTrack>` keep only the last of the three (the scale
          // track here) and silently drop the rotation the foot-lock math
          // actually reads, then run its per-key indexing past its own end.
          ProjectTrack(
            objectId: source.idOf['hips']!,
            track: _translationTrack(0, crouchHips),
          ),
          ProjectTrack(
            objectId: source.idOf['hips']!,
            track: _rotationTrack(0, hipTilt),
          ),
          ProjectTrack(
            objectId: source.idOf['hips']!,
            track: _scaleTrack(0, Vector3(1, 1, 1)),
          ),
        ],
      );

      final sourceNames = source.objects.map((o) => o.name).toList();
      final targetNames = target.objects.map((o) => o.name).toList();
      final boneMap = autoMap(sourceNames, targetNames);

      // No `lockFeet: false` here — the default (`true`) is the exact
      // repro tut-12 named, and must no longer throw.
      final withLock = retargetClip(
        sourceClip: clip,
        sourceProject: sourceProject,
        sourceSkeleton: source.skeleton,
        targetProject: targetProject,
        targetSkeleton: target.skeleton,
        boneMap: boneMap,
      );

      final hipRest = target.objects
          .firstWhere((o) => o.name == 'leftHip')
          .transform;
      final kneeRest = target.objects
          .firstWhere((o) => o.name == 'leftKnee')
          .transform;
      final ankleRest = target.objects
          .firstWhere((o) => o.name == 'leftAnkle')
          .transform;

      Quaternion rotOf(int objectId, Quaternion fallback) {
        for (final t in withLock.tracks) {
          if (t.objectId == objectId &&
              t.track.path == AnimationPath.rotation) {
            final v = t.track.values;
            return Quaternion(v[0], v[1], v[2], v[3]);
          }
        }
        return fallback;
      }

      Vector3 hipsWorld() {
        for (final t in withLock.tracks) {
          if (t.objectId == target.idOf['hips'] &&
              t.track.path == AnimationPath.translation) {
            final v = t.track.values;
            return Vector3(v[0], v[1], v[2]);
          }
        }
        return target.objects
            .firstWhere((o) => o.name == 'hips')
            .transform
            .getTranslation();
      }

      final hipRot = rotOf(target.idOf['leftHip']!, Quaternion.identity());
      final kneeRot = rotOf(target.idOf['leftKnee']!, Quaternion.identity());

      final hipWorldPos =
          hipsWorld() + Quaternion.identity().rotated(hipRest.getTranslation());
      final kneeWorldPos =
          hipWorldPos + hipRot.rotated(kneeRest.getTranslation());
      final kneeWorldRot = (kneeRot * hipRot)..normalize();
      final ankleWorldPos =
          kneeWorldPos + kneeWorldRot.rotated(ankleRest.getTranslation());

      // The foot still lands within the row's own 1cm of the ground —
      // lockFeet ran the real correction, not merely avoided the crash.
      expect((ankleWorldPos.y - 0.0).abs(), lessThan(0.01));

      // The hip's own scale track survived untouched alongside its
      // corrected rotation and translation — nothing else on the joint was
      // dropped to make room for the fix.
      final hipScale = withLock.tracks.firstWhere(
        (t) =>
            t.objectId == target.idOf['hips'] &&
            t.track.path == AnimationPath.scale,
      );
      expect(hipScale.track.values, [1.0, 1.0, 1.0]);
    });

    test('two forks — bone name mismatch is dropped, not guessed at', () {
      final source = _buildHumanoid();
      final target = _buildHumanoid();
      final sourceProject = _projectOf(source);
      final targetProject = _projectOf(target);

      final clip = ProjectClip(
        name: 'pose',
        tracks: [
          ProjectTrack(
            objectId: source.idOf['leftElbow']!,
            track: _rotationTrack(
              0,
              Quaternion.axisAngle(Vector3(0, 1, 0), 0.3),
            ),
          ),
        ],
      );

      // A bone map that only knows about 'hips' — 'leftElbow' has no
      // mapping, so its track must be dropped rather than left unmapped
      // and crash.
      final boneMap = const BoneMap({'hips': 'hips'});

      final retargeted = retargetClip(
        sourceClip: clip,
        sourceProject: sourceProject,
        sourceSkeleton: source.skeleton,
        targetProject: targetProject,
        targetSkeleton: target.skeleton,
        boneMap: boneMap,
        lockFeet: false,
      );

      expect(retargeted.tracks, isEmpty);
    });

    test('rest-relative math holds at a non-identity rest pose '
        '(every bone in _buildHumanoid is a pure translation, so this is the '
        'only test that actually exercises sourceRestRot.inverted())', () {
      ModelObject boneAt(Quaternion restRotation) => ModelObject(
        id: 1,
        name: 'bone',
        geometry: const SocketGeometry(),
        transform: Matrix4.compose(
          Vector3.zero(),
          restRotation,
          Vector3(1, 1, 1),
        ),
      );

      final sourceRest = Quaternion.axisAngle(Vector3(0, 1, 0), 0.9)
        ..normalize();
      final targetRest = Quaternion.axisAngle(Vector3(1, 0, 0), 0.4)
        ..normalize();
      final sourceObj = boneAt(sourceRest);
      final targetObj = boneAt(targetRest);
      final skeleton = ProjectSkeleton(
        joints: [1],
        inverseBindMatrices: [Matrix4.identity()],
      );
      final sourceProject = ModelProject(
        objects: [sourceObj],
        skeletons: [skeleton],
      );
      final targetProject = ModelProject(
        objects: [targetObj],
        skeletons: [skeleton],
      );

      final animated = Quaternion.axisAngle(Vector3(0, 0, 1), 1.1)..normalize();
      final clip = ProjectClip(
        tracks: [ProjectTrack(objectId: 1, track: _rotationTrack(0, animated))],
      );

      final retargeted = retargetClip(
        sourceClip: clip,
        sourceProject: sourceProject,
        sourceSkeleton: skeleton,
        targetProject: targetProject,
        targetSkeleton: skeleton,
        boneMap: const BoneMap({'bone': 'bone'}),
        lockFeet: false,
      );

      final relative = (sourceRest.inverted() * animated)..normalize();
      final expected = (targetRest * relative)..normalize();

      final out = retargeted.tracks.single.track.values;
      expect(out[0], closeTo(expected.x, 1e-6));
      expect(out[1], closeTo(expected.y, 1e-6));
      expect(out[2], closeTo(expected.z, 1e-6));
      expect(out[3], closeTo(expected.w, 1e-6));
    });
  });

  group('mirrorBoneName', () {
    test('left/right pairs mirror; a centerline name is unchanged', () {
      expect(mirrorBoneName('leftHip'), 'rightHip');
      expect(mirrorBoneName('rightAnkle'), 'leftAnkle');
      expect(mirrorBoneName('hips'), 'hips');
    });
  });
}
