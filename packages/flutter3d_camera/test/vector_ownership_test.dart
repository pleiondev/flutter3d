/// Who owns a vector a camera hands out (docs/CONTRACTS.md, "Space").
///
///     dart test test/vector_ownership_test.dart
///
/// A getter answers a copy. The photo camera's eye was its own vector, so a
/// caller that scaled what it read moved the camera through the walls it
/// is held inside, while its target beside it was already a copy.
library;

import 'package:flutter3d_camera/flutter3d_camera.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the photo camera\'s eye and anchor are copies', () {
    final camera = PhotoCamera(world: CollisionWorld())
      ..begin(
        eye: Vector3(0.0, 2.0, 6.0),
        target: Vector3(0.0, 2.0, 0.0),
        anchor: Vector3(0.0, 1.0, 4.0),
      );
    // Mutation: return `_eye` from `PhotoCamera.eye`, `_anchor` from
    // `anchor`. The writes below move the camera and its tether.
    camera.eye.setValues(100.0, 100.0, 100.0);
    camera.anchor.setValues(100.0, 100.0, 100.0);
    expect(camera.eye, Vector3(0.0, 2.0, 6.0));
    expect(camera.anchor, Vector3(0.0, 1.0, 4.0));
  });

  test('a rig\'s eye, free eye and target are copies', () {
    final rig = CameraRig(world: CollisionWorld())
      ..place(
        desiredEye: Vector3(0.0, 3.0, 8.0),
        desiredTarget: Vector3(0.0, 1.0, 0.0),
        lag: 0.0,
        dt: 1.0 / 60.0,
      );
    final eye = rig.eye;
    // Mutation: return `_shown`, `_eye` or `_target` from the getters.
    rig.eye.setZero();
    rig.freeEye.setZero();
    rig.target.setZero();
    expect(rig.eye, eye);
    expect(rig.freeEye, isNot(Vector3.zero()));
    expect(rig.target, Vector3(0.0, 1.0, 0.0));
  });
}
