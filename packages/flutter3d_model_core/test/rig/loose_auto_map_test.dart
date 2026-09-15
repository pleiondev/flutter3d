/// `anim-18`'s own `looseAutoMap` — Mixamo/Biped prefixes, case, and the
/// synonym table, kept apart from [autoMap]'s own exact-match tests.
///
///     dart test test/loose_auto_map_test.dart
library;

import 'package:flutter3d_rig/flutter3d_rig.dart';
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
  });
}
