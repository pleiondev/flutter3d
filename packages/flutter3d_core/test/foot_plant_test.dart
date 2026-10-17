/// Feet put on the ground the game says is under them — N1.
///
///     dart test test/foot_plant_test.dart
///
/// A two-legged rig built the way the Quaternius characters are: each leg
/// hip, knee and ankle, and each foot a bone of its own on the root that
/// the clip puts where the ankle is. On flat ground nothing moves; a foot
/// on a step is lifted, the knee bending; a foot below the floor lowers the
/// hips; and the foot bones go with their ankles.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _hips = 1, _ankleL = 4, _footL = 5, _ankleR = 8, _footR = 9;

/// Root, hips a metre up, two legs of two half-metre bones with the knees a
/// little forward, and a foot bone on the root under each ankle.
AnimationPose _rig() => AnimationPose(
  parents: const <int>[-1, 0, 1, 2, 3, 0, 1, 6, 7, 0],
  restTranslations: Float32List.fromList(<double>[
    0, 0, 0, //
    0, 1, 0, // hips
    0.1, 0, 0, // upper leg L
    0, -0.5, 0.05, // knee L
    0, -0.5, -0.05, // ankle L
    0.1, 0, 0, // foot L, on the root
    -0.1, 0, 0, // upper leg R
    0, -0.5, 0.05, // knee R
    0, -0.5, -0.05, // ankle R
    -0.1, 0, 0, // foot R, on the root
  ]),
  restRotations: Float32List.fromList(<double>[
    for (var i = 0; i < 10; i++) ...<double>[0, 0, 0, 1],
  ]),
  restScales: Float32List.fromList(<double>[
    for (var i = 0; i < 10; i++) ...<double>[1, 1, 1],
  ]),
);

FootPlantGoal _plant({double l = 0.0, double r = 0.0, double weight = 1.0}) =>
    FootPlantGoal(
      hips: _hips,
      legs: <FootLeg>[
        FootLeg(root: 2, mid: 3, tip: _ankleL, foot: _footL)..ground = l,
        FootLeg(root: 6, mid: 7, tip: _ankleR, foot: _footR)..ground = r,
      ],
      weight: weight,
    );

Vector3 _at(AnimationPose pose, int joint) =>
    pose.worldMatrices()[joint].getTranslation();

void main() {
  test('on flat ground nothing moves', () {
    final pose = _rig();
    final before = (pose.translations.toList(), pose.rotations.toList());
    _plant().apply(pose);
    expect(pose.translations.toList(), before.$1);
    for (var i = 0; i < before.$2.length; i++) {
      expect(pose.rotations[i], closeTo(before.$2[i], 1e-6));
    }
  });

  test('a foot on a step is lifted onto it, the knee bending forward', () {
    final pose = _rig();
    final kneeBefore = _at(pose, 3).z;
    _plant(l: 0.2).apply(pose);
    expect(_at(pose, _ankleL).y, closeTo(0.2, 1e-4));
    expect(_at(pose, _ankleL).x, closeTo(0.1, 1e-4));
    expect(_at(pose, _footL).y, closeTo(0.2, 1e-4), reason: 'with its ankle');
    expect(_at(pose, 3).z, greaterThan(kneeBefore), reason: 'bent forward');
    expect(_at(pose, _ankleR).y, closeTo(0.0, 1e-4));
    expect(_at(pose, _hips).y, closeTo(1.0, 1e-6), reason: 'hips stay');
  });

  test('a foot below the floor lowers the hips by as much', () {
    final pose = _rig();
    _plant(l: -0.15, r: 0.1).apply(pose);
    expect(_at(pose, _hips).y, closeTo(0.85, 1e-5));
    expect(_at(pose, _ankleL).y, closeTo(-0.15, 1e-4));
    expect(_at(pose, _ankleR).y, closeTo(0.1, 1e-4));
    expect(_at(pose, _footR).y, closeTo(0.1, 1e-4));
    expect(_at(pose, _footL).y, closeTo(-0.15, 1e-4));
  });

  test('at half weight, half the way', () {
    final pose = _rig();
    _plant(l: 0.2, r: -0.1, weight: 0.5).apply(pose);
    expect(_at(pose, _hips).y, closeTo(0.95, 1e-5));
    expect(_at(pose, _ankleL).y, closeTo(0.1, 1e-4));
    expect(_at(pose, _ankleR).y, closeTo(-0.05, 1e-4));
  });

  test('through a turned parent, the hips still go straight down', () {
    final pose = _rig();
    // The root turned a quarter about z — lying on its side: the hips'
    // parent frame is not the pose's, so a drop written straight into the
    // local translation would go sideways.
    final q = Quaternion.axisAngle(Vector3(0, 0, 1), 1.5707963);
    pose.rotations
      ..[0] = q.x
      ..[1] = q.y
      ..[2] = q.z
      ..[3] = q.w;
    final hips = _at(pose, _hips);
    _plant(l: -0.2).apply(pose);
    final after = _at(pose, _hips);
    expect(after.y, closeTo(hips.y - 0.2, 1e-5));
    expect(after.x, closeTo(hips.x, 1e-5));
    expect(after.z, closeTo(hips.z, 1e-5));
  });
}
