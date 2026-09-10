/// The rig: two eyes under a head under a stage.
///
///     flutter test test/stereo_rig_test.dart
///
/// The arrangement is three nodes deep for one reason, and it is the reason
/// worth testing: the head's pose is *given* by whatever is tracking it, so
/// everything an application wants to do — walk, ride, start somewhere other
/// than the origin — has to happen below it. A rig that answered a stick by
/// turning the head would be arguing with the sensor sixty times a second.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

StereoRig inScene({double ipd = 0.064}) {
  final scene = Scene();
  final rig = StereoRig(interpupillaryDistance: ipd);
  scene.add(rig.stage);
  return rig;
}

void main() {
  group('where the eyes are', () {
    test('half the interpupillary distance either side of the head', () {
      final rig = inScene(ipd: 0.07);
      expect(
        rig.camera(Eye.left).readWorldPosition().x,
        closeTo(-0.035, 1e-9),
      );
      expect(rig.camera(Eye.right).readWorldPosition().x, closeTo(0.035, 1e-9));
    });

    test('and they move with the stage rather than with the world', () {
      final rig = inScene();
      rig.stage.setPosition(10.0, 0.0, -4.0);
      expect(rig.camera(Eye.left).readWorldPosition().x, closeTo(9.968, 1e-6));
      expect(rig.camera(Eye.left).readWorldPosition().z, closeTo(-4.0, 1e-6));
    });

    test('the head turns the pair, not each eye', () {
      final rig = inScene();
      // A quarter turn to the left about the world's up: the left eye swings
      // to where the camera is now looking away from.
      rig.applyHead(
        HeadPose(
          rotation: Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), math.pi / 2),
          position: Vector3.zero(),
        ),
      );
      final left = rig.camera(Eye.left).readWorldPosition();
      expect(left.x, closeTo(0.0, 1e-6));
      expect(left.z, closeTo(0.032, 1e-6));
    });
  });

  group('the two views', () {
    test('are the left and right halves of one target', () {
      final rig = inScene();
      expect(rig.views, hasLength(2));
      expect(rig.views[0].viewportFraction.x, 0.0);
      expect(rig.views[0].viewportFraction.width, 0.5);
      expect(rig.views[1].viewportFraction.x, 0.5);
      expect(rig.views[1].viewportFraction.width, 0.5);
      expect(identical(rig.views[0].camera, rig.camera(Eye.left)), isTrue);
    });

    test('and the list is the same list every frame', () {
      // Rebuilt per frame it would allocate two views sixty times a second for
      // a pair that never changes.
      final rig = inScene();
      expect(identical(rig.views, rig.views), isTrue);
    });
  });

  group('the frusta while nothing better is known', () {
    test('are as wide as half the surface is', () {
      final rig = inScene();
      rig.fitToViewport(width: 2000, height: 500);
      final projection = rig.camera(Eye.left).projection as OffAxisProjection;
      // Half of 2000 against 500: an eye two units wide for every one tall.
      expect(
        (projection.tanRight - projection.tanLeft) /
            (projection.tanUp - projection.tanDown),
        closeTo(2.0, 1e-9),
      );
    });

    test('are symmetric, because a screen has no lenses to be off-centre', () {
      final rig = inScene();
      rig.fitToViewport(width: 1000, height: 500);
      final projection = rig.camera(Eye.right).projection as OffAxisProjection;
      expect(projection.tanLeft, closeTo(-projection.tanRight, 1e-12));
      expect(projection.tanDown, closeTo(-projection.tanUp, 1e-12));
    });

    test('and both eyes get the same one', () {
      final rig = inScene();
      rig.fitToViewport(width: 1000, height: 500);
      final left = rig.camera(Eye.left).projection as OffAxisProjection;
      final right = rig.camera(Eye.right).projection as OffAxisProjection;
      expect(left.tanRight, right.tanRight);
      expect(left.tanUp, right.tanUp);
    });
  });

  group('once a runtime has stated the frusta', () {
    test('the viewport stops overwriting them', () {
      final rig = inScene();
      const stated = OffAxisProjection(
        tanLeft: -1.2,
        tanRight: 1.0,
        tanDown: -1.1,
        tanUp: 1.1,
      );
      rig.applyEye(Eye.left, projection: stated);
      rig.fitToViewport(width: 4000, height: 100);

      final left = rig.camera(Eye.left).projection as OffAxisProjection;
      expect(left.tanLeft, -1.2, reason: 'a headset knows its own lenses');
    });

    test('an eye can be moved as well as shaped', () {
      final rig = inScene();
      rig.applyEye(
        Eye.right,
        projection: OffAxisProjection.symmetric(),
        offset: Vector3(0.033, 0.01, 0.0),
      );
      expect(rig.camera(Eye.right).readWorldPosition().y, closeTo(0.01, 1e-9));
    });
  });

  group('what an application is allowed to move', () {
    test('facing a direction turns the stage and leaves the head alone', () {
      final rig = inScene();
      rig.applyHead(
        HeadPose(
          rotation: Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), 0.3),
          position: Vector3.zero(),
        ),
      );
      rig.faceYaw(math.pi);

      // The head keeps the pitch the sensor reported; the stage carries the
      // yaw. Looking down thirty degrees and turned about, the gaze runs
      // backwards along +Z rather than along −Z.
      final gaze = rig.gaze();
      expect(gaze.z, greaterThan(0.0));
      expect(gaze.y, greaterThan(0.0));
    });

    test('the vertical angle is the one the eyes actually have', () {
      final rig = inScene();
      rig.fitToViewport(width: 1000, height: 500, verticalFieldOfView: 0.9);
      expect(rig.verticalFieldOfView, closeTo(0.9, 1e-9));
    });
  });
}
