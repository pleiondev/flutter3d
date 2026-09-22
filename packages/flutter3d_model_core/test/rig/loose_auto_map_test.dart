/// `anim-18`'s own `looseAutoMap` — Mixamo/Biped prefixes, case, and the
/// synonym table, kept apart from [autoMap]'s own exact-match tests.
///
///     dart test test/loose_auto_map_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

void main() {
  group('looseAutoMap', () {
    test('a Mixamo rig maps onto a canonical humanoid target', () {
      final source = <String>[
        'mixamorig:Hips',
        'mixamorig:Spine',
        'mixamorig:Spine1',
        'mixamorig:Spine2',
        'mixamorig:Neck',
        'mixamorig:Head',
        'mixamorig:LeftArm',
        'mixamorig:LeftForeArm',
        'mixamorig:LeftHand',
        'mixamorig:RightArm',
        'mixamorig:RightForeArm',
        'mixamorig:RightHand',
        'mixamorig:LeftUpLeg',
        'mixamorig:LeftLeg',
        'mixamorig:LeftFoot',
        'mixamorig:RightUpLeg',
        'mixamorig:RightLeg',
        'mixamorig:RightFoot',
      ];
      final boneMap = looseAutoMap(source, humanoidBoneNames);

      expect(boneMap.targetOf('mixamorig:Hips'), 'hips');
      expect(boneMap.targetOf('mixamorig:Spine'), 'spine');
      // Spine1 and Spine2 both read as `chest` — a mocap rig's own extra
      // spine segment has nowhere else among the eleven keys to land.
      expect(boneMap.targetOf('mixamorig:Spine2'), 'chest');
      expect(boneMap.targetOf('mixamorig:Neck'), 'neck');
      expect(boneMap.targetOf('mixamorig:Head'), 'head');
      expect(boneMap.targetOf('mixamorig:LeftArm'), 'leftShoulder');
      expect(boneMap.targetOf('mixamorig:LeftForeArm'), 'leftElbow');
      expect(boneMap.targetOf('mixamorig:LeftHand'), 'leftWrist');
      expect(boneMap.targetOf('mixamorig:RightArm'), 'rightShoulder');
      expect(boneMap.targetOf('mixamorig:LeftUpLeg'), 'leftHip');
      expect(boneMap.targetOf('mixamorig:LeftLeg'), 'leftKnee');
      expect(boneMap.targetOf('mixamorig:LeftFoot'), 'leftAnkle');
      expect(boneMap.targetOf('mixamorig:RightUpLeg'), 'rightHip');
      expect(boneMap.targetOf('mixamorig:RightLeg'), 'rightKnee');
      expect(boneMap.targetOf('mixamorig:RightFoot'), 'rightAnkle');
    });

    test('a 3ds Max Biped rig maps the same way, underscore- or '
        'space-separated', () {
      final underscored = <String>[
        'Bip01_Pelvis',
        'Bip01_L_UpperArm',
        'Bip01_L_Forearm',
        'Bip01_L_Hand',
        'Bip01_L_Thigh',
        'Bip01_L_Calf',
        'Bip01_L_Foot',
      ];
      final spaced = <String>[
        'Bip01 Pelvis',
        'Bip01 L UpperArm',
        'Bip01 L Forearm',
        'Bip01 L Hand',
        'Bip01 L Thigh',
        'Bip01 L Calf',
        'Bip01 L Foot',
      ];
      for (final source in <List<String>>[underscored, spaced]) {
        final boneMap = looseAutoMap(source, humanoidBoneNames);
        expect(boneMap.targetOf(source[0]), 'hips');
        expect(boneMap.targetOf(source[1]), 'leftShoulder');
        expect(boneMap.targetOf(source[2]), 'leftElbow');
        expect(boneMap.targetOf(source[3]), 'leftWrist');
        expect(boneMap.targetOf(source[4]), 'leftHip');
        expect(boneMap.targetOf(source[5]), 'leftKnee');
        expect(boneMap.targetOf(source[6]), 'leftAnkle');
      }
    });

    test('case-insensitive: shouting or all-lowercase names still map', () {
      final boneMap = looseAutoMap(<String>[
        'MIXAMORIG:LEFTUPLEG',
        'mixamorig:lefthand',
      ], humanoidBoneNames);
      expect(boneMap.targetOf('MIXAMORIG:LEFTUPLEG'), 'leftHip');
      expect(boneMap.targetOf('mixamorig:lefthand'), 'leftWrist');
    });

    test('every canonical name reads back onto itself — this loose pass '
        'never does worse than autoMap for two engine-built rigs', () {
      final boneMap = looseAutoMap(humanoidBoneNames, humanoidBoneNames);
      expect(boneMap.length, humanoidBoneNames.length);
      for (final name in humanoidBoneNames) {
        expect(boneMap.targetOf(name), name);
      }
    });

    test('a name neither table recognises is dropped, not guessed at', () {
      final boneMap = looseAutoMap(<String>[
        'mixamorig:LeftArm',
        'mixamorig:Ponytail1',
      ], humanoidBoneNames);
      expect(boneMap.targetOf('mixamorig:LeftArm'), 'leftShoulder');
      expect(boneMap.targetOf('mixamorig:Ponytail1'), isNull);
      expect(boneMap.length, 1);
    });

    test('a target that itself carries no matching bone leaves the source '
        'name unmapped', () {
      final boneMap = looseAutoMap(
        <String>['mixamorig:LeftHand'],
        <String>['hips', 'spine'],
      );
      expect(boneMap.isEmpty, isTrue);
    });

    // `tut-13`: `_looseSide` used to require the side marker at the very
    // start of the (prefix-stripped) name, so a name that puts it mid-word
    // — Blender's own `.L`/`.R` export suffix, or a rig that spells the
    // side between two other words — read as no side at all and fell
    // through to the centreline table, which does not know the word either.
    test('a side marker in the middle of a name still maps, once the rest '
        'of the word is one the dictionary already knows', () {
      final boneMap = looseAutoMap(<String>[
        'UpperArm_L',
        'Hand.R',
        'Thigh_R',
        'Foot_L',
      ], humanoidBoneNames);
      expect(boneMap.targetOf('UpperArm_L'), 'leftShoulder');
      expect(boneMap.targetOf('Hand.R'), 'rightWrist');
      expect(boneMap.targetOf('Thigh_R'), 'rightHip');
      expect(boneMap.targetOf('Foot_L'), 'leftAnkle');
    });

    test('the start-anchored Mixamo/Biped shapes still win over the '
        'mid-name fallback — widening does not change an already-'
        'recognised name', () {
      final boneMap = looseAutoMap(<String>[
        'mixamorig:LeftUpLeg',
        'Bip01_L_Thigh',
      ], humanoidBoneNames);
      expect(boneMap.targetOf('mixamorig:LeftUpLeg'), 'leftHip');
      expect(boneMap.targetOf('Bip01_L_Thigh'), 'leftHip');
    });

    // `tut-13`, closed: `RiggedFigure.glb`'s own joint words
    // (`torso`/`arm`/`leg`/`neck`) are generic placeholders in neither
    // synonym table, disambiguated only by a trailing numeric chain index
    // (`arm_joint_L_1` = shoulder, `arm_joint_L_2` = elbow, ...) — a third
    // matching path, [_chainCanonicalOf] via `_looseCanonicalOf`, reads that
    // shape by chain position now, so this file's own real nineteen joint
    // names (decoded straight off `RiggedFigure.glb` while diagnosing this
    // row, in this exact order) map onto all but the two toe-tip bones
    // `RigTemplate.humanoid` has no joint for.
    test("RiggedFigure.glb's own real joint names auto-map onto "
        'RigTemplate.humanoid by chain position', () {
      final boneMap = looseAutoMap(<String>[
        'torso_joint_1',
        'torso_joint_2',
        'torso_joint_3',
        'neck_joint_1',
        'neck_joint_2',
        'arm_joint_L_1',
        'arm_joint_R_1',
        'arm_joint_L_2',
        'arm_joint_R_2',
        'arm_joint_L_3',
        'arm_joint_R_3',
        'leg_joint_L_1',
        'leg_joint_R_1',
        'leg_joint_L_2',
        'leg_joint_R_2',
        'leg_joint_L_3',
        'leg_joint_R_3',
        'leg_joint_L_5',
        'leg_joint_R_5',
      ], humanoidBoneNames);

      expect(boneMap.length, 17);
      expect(boneMap.targetOf('torso_joint_1'), 'hips');
      expect(boneMap.targetOf('torso_joint_2'), 'spine');
      expect(boneMap.targetOf('torso_joint_3'), 'chest');
      expect(boneMap.targetOf('neck_joint_1'), 'neck');
      expect(boneMap.targetOf('neck_joint_2'), 'head');
      expect(boneMap.targetOf('arm_joint_L_1'), 'leftShoulder');
      expect(boneMap.targetOf('arm_joint_L_2'), 'leftElbow');
      expect(boneMap.targetOf('arm_joint_L_3'), 'leftWrist');
      expect(boneMap.targetOf('arm_joint_R_1'), 'rightShoulder');
      expect(boneMap.targetOf('arm_joint_R_2'), 'rightElbow');
      expect(boneMap.targetOf('arm_joint_R_3'), 'rightWrist');
      expect(boneMap.targetOf('leg_joint_L_1'), 'leftHip');
      expect(boneMap.targetOf('leg_joint_L_2'), 'leftKnee');
      expect(boneMap.targetOf('leg_joint_L_3'), 'leftAnkle');
      expect(boneMap.targetOf('leg_joint_R_1'), 'rightHip');
      expect(boneMap.targetOf('leg_joint_R_2'), 'rightKnee');
      expect(boneMap.targetOf('leg_joint_R_3'), 'rightAnkle');
      // The toe-tip bones: no joint on `RigTemplate.humanoid` for either to
      // land on, dropped exactly the way a source bone the target lacks
      // always is — not a chain-length mismatch this reading gets wrong.
      expect(boneMap.targetOf('leg_joint_L_5'), isNull);
      expect(boneMap.targetOf('leg_joint_R_5'), isNull);
    });

    // No false positives: `RobotExpressive.glb`'s own real joint names
    // (decoded the same way) carry Blender-style numbered names of their
    // own — `Middle1.L`, `Thumb2.R`, `Ring1.L` — where the number sits
    // glued onto the word with no delimiter before the side suffix, the
    // shape [_chainCanonicalOf] is built to never read (its own trailing
    // index has to be a separate token). None of them should suddenly gain
    // a chain-position mapping they have no business getting.
    test("RobotExpressive.glb's own numbered finger joints are not "
        'mistaken for a chain-index name', () {
      final boneMap = looseAutoMap(<String>[
        'Middle1.L',
        'Middle2.L',
        'Thumb.L',
        'Thumb2.L',
        'Palm1.L',
        'Index.L',
        'Index2.L',
        'Palm3.L',
        'Ring1.L',
        'Ring2.L',
      ], humanoidBoneNames);
      expect(boneMap.isEmpty, isTrue);
    });
  });
}
